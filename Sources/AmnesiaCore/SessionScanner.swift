import Foundation

/// Lists sessions from every supported agent. Scanning never modifies anything.
public struct SessionScanner: Sendable {
    private let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func scan() -> [Session] {
        let claude = ClaudeSessionScanner(claudeHome: homeDirectory.appendingPathComponent(".claude"))
        let codex = CodexSessionScanner(codexHome: homeDirectory.appendingPathComponent(".codex"))
        return claude.scan() + codex.scan()
    }
}
