import Foundation

/// Finds records of sessions whose transcript is gone. Scanning never modifies
/// anything.
///
/// A missing transcript alone proves nothing: a session that just started can
/// have records before its transcript exists. So running sessions are excluded,
/// and so is anything touched within `minimumAge`.
public struct LeftoverScanner: Sendable {
    public static let defaultMinimumAge: TimeInterval = 60 * 60

    private let paths: AgentPaths
    private let activity: SessionActivity
    private let minimumAge: TimeInterval

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let paths = AgentPaths(home: homeDirectory)
        self.init(paths: paths, activity: SessionActivity(paths: paths), minimumAge: Self.defaultMinimumAge)
    }

    init(paths: AgentPaths, activity: SessionActivity, minimumAge: TimeInterval) {
        self.paths = paths
        self.activity = activity
        self.minimumAge = minimumAge
    }

    /// `sessions` must be a current scan, because every session it holds still
    /// has a transcript and so can't be a leftover.
    public func scan(excluding sessions: [Session]) -> [Leftover] {
        let excluded = Set(sessions.map(\.id)).union(activity.snapshot().runningIDs)
        return (claudeRecords() + codexRecords()).flatMap {
            $0.leftovers(excluding: excluded, minimumAge: minimumAge)
        }
    }

    private func claudeRecords() -> [Records] {
        var records = Records(source: .claudeCode)

        records.addHistory(paths.promptHistory(for: .claudeCode))
        for directory in paths.claudeRecordDirectories {
            for entry in contents(of: directory) {
                records.addFile(entry, id: entry.lastPathComponent)
            }
        }
        return [records]
    }

    private func codexRecords() -> [Records] {
        var records = Records(source: .codex)

        records.addHistory(paths.promptHistory(for: .codex))
        for entry in contents(of: paths.codexShellSnapshots) {
            let id = entry.lastPathComponent.prefix { $0 != "." }
            records.addFile(entry, id: String(id))
        }
        for thread in CodexThreadStore.orphanedThreads(at: paths.codexStateDatabase) {
            records.addDatabaseRecord(id: thread.id, updatedAt: thread.updatedAt)
        }
        return [records]
    }

    private func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }
}

/// Collects everything found for each session id. Only UUIDs are accepted, so
/// unrelated files in the same folders can't be picked up.
private struct Records {
    private struct Entry {
        var promptCount = 0
        var files: [URL] = []
        var hasDatabaseRecord = false
        var size: Int64 = 0
        var lastUsed = Date.distantPast

        mutating func noteUse(at date: Date) {
            lastUsed = max(lastUsed, date)
        }
    }

    let source: SessionSource
    private var entries: [String: Entry] = [:]

    init(source: SessionSource) {
        self.source = source
    }

    mutating func addHistory(_ history: PromptHistory) {
        guard let data = try? Data(contentsOf: history.url) else { return }

        for line in data.split(separator: 0x0A) {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)),
                let record = object as? [String: Any],
                let id = history.sessionID(in: record),
                UUID(uuidString: id) != nil
            else { continue }

            entries[id, default: Entry()].promptCount += 1
            entries[id]?.size += Int64(line.count)
            if let date = history.date(of: record) {
                entries[id]?.noteUse(at: date)
            }
        }
    }

    mutating func addFile(_ url: URL, id: String) {
        guard UUID(uuidString: id) != nil else { return }

        let (size, modified) = Self.measure(url)
        entries[id, default: Entry()].files.append(url)
        entries[id]?.size += size
        entries[id]?.noteUse(at: modified)
    }

    mutating func addDatabaseRecord(id: String, updatedAt: Date) {
        guard UUID(uuidString: id) != nil else { return }

        entries[id, default: Entry()].hasDatabaseRecord = true
        entries[id]?.noteUse(at: updatedAt)
    }

    func leftovers(excluding known: Set<String>, minimumAge: TimeInterval) -> [Leftover] {
        let cutoff = Date(timeIntervalSinceNow: -minimumAge)

        return entries
            .filter { id, entry in !known.contains(id) && entry.lastUsed < cutoff }
            .map { id, entry in
                Leftover(
                    id: id,
                    source: source,
                    promptCount: entry.promptCount,
                    files: entry.files,
                    hasDatabaseRecord: entry.hasDatabaseRecord,
                    size: entry.size
                )
            }
            .sorted { $0.id < $1.id }
    }

    /// Returns the total size and newest modification date under `url`,
    /// which is either a single file or a directory.
    private static func measure(_ url: URL) -> (size: Int64, modified: Date) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        let children = enumerator?.compactMap { $0 as? URL } ?? []

        var size: Int64 = 0
        var modified = Date.distantPast
        for item in [url] + children {
            guard let values = try? item.resourceValues(forKeys: keys) else { continue }
            size += Int64(values.fileSize ?? 0)
            modified = max(modified, values.contentModificationDate ?? .distantPast)
        }
        return (size, modified)
    }
}
