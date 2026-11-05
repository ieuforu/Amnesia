import Foundation

/// One stored conversation from a coding agent.
public struct Session: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: SessionSource
    /// The directory the session ran in, when the transcript records one.
    public let projectPath: String?
    public let firstMessage: String?
    public let updatedAt: Date
    public let size: Int64
    public let fileURL: URL
    /// True while a running agent owns this session.
    public let isActive: Bool

    public init(
        id: String,
        source: SessionSource,
        projectPath: String?,
        firstMessage: String?,
        updatedAt: Date,
        size: Int64,
        fileURL: URL,
        isActive: Bool
    ) {
        self.id = id
        self.source = source
        self.projectPath = projectPath
        self.firstMessage = firstMessage
        self.updatedAt = updatedAt
        self.size = size
        self.fileURL = fileURL
        self.isActive = isActive
    }
}
