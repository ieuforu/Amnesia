import Foundation

/// The one definition of where each agent keeps its data and how that data is
/// named. Nothing else in the app spells out these paths.
struct AgentPaths: Sendable {
    let home: URL

    private var claudeHome: URL { home.appendingPathComponent(".claude") }
    private var codexHome: URL { home.appendingPathComponent(".codex") }

    var codexHomeDirectory: URL { codexHome }

    // MARK: Claude Code

    var claudeProjects: URL { claudeHome.appendingPathComponent("projects") }
    var claudeRegistrations: URL { claudeHome.appendingPathComponent("sessions") }

    /// Folders that hold one subfolder per session, named after its id.
    var claudeRecordDirectories: [URL] {
        ["file-history", "session-env"].map { claudeHome.appendingPathComponent($0) }
    }

    // MARK: Codex

    var codexSessionRoots: [URL] {
        ["sessions", "archived_sessions"].map { codexHome.appendingPathComponent($0) }
    }

    var codexShellSnapshots: URL { codexHome.appendingPathComponent("shell_snapshots") }
    var codexSessionIndex: URL { codexHome.appendingPathComponent("session_index.jsonl") }
    var codexStateDatabase: URL { codexHome.appendingPathComponent("state_5.sqlite") }

    func codexRollouts() -> [URL] {
        codexSessionRoots.flatMap { root -> [URL] in
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            )
            return (enumerator?.compactMap { $0 as? URL } ?? []).filter {
                $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
            }
        }
    }

    func codexWriterLocks() -> [URL] {
        let directory = codexHome.appendingPathComponent("thread-writer-locks")
        let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return (files ?? []).filter { $0.pathExtension == "lock" }
    }

    /// Reads the session id from `<uuid>.lock` or `rollout-<time>-<uuid>.jsonl`.
    static func codexSessionID(inFileName name: String) -> String? {
        let stem = (name as NSString).deletingPathExtension
        let candidate = String(stem.suffix(36))
        return UUID(uuidString: candidate) == nil ? nil : candidate
    }

    // MARK: Prompt history

    func promptHistory(for source: SessionSource) -> PromptHistory {
        switch source {
        case .claudeCode:
            PromptHistory(
                url: claudeHome.appendingPathComponent("history.jsonl"),
                idKey: "sessionId",
                timestampKey: "timestamp",
                timestampUnitsPerSecond: 1000
            )
        case .codex:
            PromptHistory(
                url: codexHome.appendingPathComponent("history.jsonl"),
                idKey: "session_id",
                timestampKey: "ts",
                timestampUnitsPerSecond: 1
            )
        }
    }
}

/// An agent's record of typed prompts, one JSON entry per line.
struct PromptHistory: Sendable {
    let url: URL
    let idKey: String
    let timestampKey: String
    let timestampUnitsPerSecond: Double

    func sessionID(in entry: [String: Any]) -> String? {
        entry[idKey] as? String
    }

    func date(of entry: [String: Any]) -> Date? {
        (entry[timestampKey] as? Double).map {
            Date(timeIntervalSince1970: $0 / timestampUnitsPerSecond)
        }
    }

    func removeEntries(forSessions ids: Set<String>) throws {
        try HistoryFile.removeEntries(at: url, forKey: idKey, values: ids)
    }
}
