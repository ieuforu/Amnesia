import Foundation

/// Permanently removes leftovers.
///
/// Everything is scanned again first and only what still qualifies is touched,
/// so a session that came back since the list was shown stays safe.
public struct LeftoverCleaner: Sendable {
    private let paths: AgentPaths
    private let activity: SessionActivity
    private let minimumAge: TimeInterval
    private let deleteCodexSession: @Sendable (String, AgentPaths) throws -> Void

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let paths = AgentPaths(home: homeDirectory)
        self.init(
            paths: paths,
            activity: SessionActivity(paths: paths),
            minimumAge: LeftoverScanner.defaultMinimumAge,
            deleteCodexSession: CodexCLI.deleteSession
        )
    }

    init(
        paths: AgentPaths,
        activity: SessionActivity,
        minimumAge: TimeInterval,
        deleteCodexSession: @escaping @Sendable (String, AgentPaths) throws -> Void
    ) {
        self.paths = paths
        self.activity = activity
        self.minimumAge = minimumAge
        self.deleteCodexSession = deleteCodexSession
    }

    /// Returns how many leftovers couldn't be removed.
    public func clean(_ selected: [Leftover]) -> Int {
        let selectedIDs = Set(selected.map(\.id))
        let sessions = SessionScanner(paths: paths, activity: activity).scan()
        let current = LeftoverScanner(paths: paths, activity: activity, minimumAge: minimumAge)
            .scan(excluding: sessions)
            .filter { selectedIDs.contains($0.id) }

        var cleanedHistory: [SessionSource: Set<String>] = [:]
        var failures = 0

        for leftover in current {
            do {
                if leftover.hasDatabaseRecord {
                    try deleteCodexSession(leftover.id, paths)
                }
                for file in leftover.files where FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
                cleanedHistory[leftover.source, default: []].insert(leftover.id)
            } catch {
                failures += 1
            }
        }

        do {
            try removeHistory(cleanedHistory)
        } catch {
            failures += cleanedHistory.values.reduce(0) { $0 + $1.count }
        }
        return failures
    }

    private func removeHistory(_ ids: [SessionSource: Set<String>]) throws {
        for (source, sessions) in ids {
            try paths.promptHistory(for: source).removeEntries(forSessions: sessions)
        }
    }
}
