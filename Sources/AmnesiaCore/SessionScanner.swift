import Foundation

/// Lists sessions from every supported agent. Scanning never modifies anything.
public struct SessionScanner: Sendable {
    private let paths: AgentPaths
    private let activity: SessionActivity

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let paths = AgentPaths(home: homeDirectory)
        self.init(paths: paths, activity: SessionActivity(paths: paths))
    }

    init(paths: AgentPaths, activity: SessionActivity) {
        self.paths = paths
        self.activity = activity
    }

    public func scan() -> [Session] {
        let snapshot = activity.snapshot()
        return ClaudeSessionScanner(paths: paths, activity: snapshot).scan()
            + CodexSessionScanner(paths: paths, activity: snapshot).scan()
    }
}
