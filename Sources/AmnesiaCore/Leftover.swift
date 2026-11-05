import Foundation

/// Records of a session whose transcript no longer exists.
public struct Leftover: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: SessionSource
    /// Typed prompts still in the agent's history file.
    public let promptCount: Int
    public let files: [URL]
    /// True when Codex still has a database record for the session.
    public let hasDatabaseRecord: Bool
    public let size: Int64
}
