import Darwin
import Foundation

/// The one answer to "is this session in use?". Everything that lists, deletes
/// or cleans up asks here, so a session in use is protected everywhere at once.
///
/// When in doubt it answers yes, because a wrong yes only delays a delete.
struct SessionActivity: Sendable {
    /// A write this recent counts as use, which covers an agent the other
    /// signals can't see, such as one whose pid belongs to another environment.
    static let defaultRecentWriteWindow: TimeInterval = 120

    let paths: AgentPaths
    var namesOfOpenFiles: @Sendable ([URL]) -> Set<String> = OpenFiles.names
    var recentWriteWindow: TimeInterval = defaultRecentWriteWindow

    /// What's running right now. Take a new one for each decision, because a
    /// session can start at any moment.
    func snapshot() -> Snapshot {
        Snapshot(
            runningIDs: runningClaudeSessions().union(runningCodexSessions()),
            recentWriteWindow: recentWriteWindow
        )
    }

    struct Snapshot {
        let runningIDs: Set<String>
        let recentWriteWindow: TimeInterval

        func isInUse(id: String, lastWrite: Date?) -> Bool {
            if runningIDs.contains(id) { return true }
            guard let lastWrite else { return false }
            return Date().timeIntervalSince(lastWrite) < recentWriteWindow
        }
    }

    /// Running sessions register `sessions/<pid>.json`, which outlives a crash,
    /// so the pid has to be checked too.
    private func runningClaudeSessions() -> Set<String> {
        let files = try? FileManager.default.contentsOfDirectory(
            at: paths.claudeRegistrations,
            includingPropertiesForKeys: nil
        )

        return Set(
            (files ?? []).filter { $0.pathExtension == "json" }.compactMap { url -> String? in
                guard
                    let data = try? Data(contentsOf: url),
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let registration = object as? [String: Any],
                    let id = registration["sessionId"] as? String,
                    let pid = registration["pid"] as? Int32,
                    Self.isRunning(pid)
                else { return nil }
                return id
            })
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        // EPERM means the process exists but belongs to another user.
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// A running Codex session keeps its lock file or transcript open. The
    /// files themselves prove nothing, because locks stay behind after exit.
    private func runningCodexSessions() -> Set<String> {
        let openFiles = namesOfOpenFiles(paths.codexWriterLocks() + paths.codexRollouts())
        return Set(openFiles.compactMap(AgentPaths.codexSessionID(inFileName:)))
    }
}
