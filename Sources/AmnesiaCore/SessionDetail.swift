import Foundation

/// One turn of a conversation, for previewing a transcript.
public struct TranscriptMessage: Identifiable, Hashable, Sendable {
    public enum Role: Sendable {
        case user, agent
    }

    public let id: Int
    public let role: Role
    public let text: String

    public init(id: Int, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// A file or folder on disk that belongs to a session.
public struct StoredFile: Identifiable, Hashable, Sendable {
    public let label: String
    public let path: String
    public let size: Int64

    public var id: String { path }

    public init(label: String, path: String, size: Int64) {
        self.label = label
        self.path = path
        self.size = size
    }
}

/// What the main window shows about one session.
public struct SessionDetail: Hashable, Sendable {
    public let messages: [TranscriptMessage]
    /// How many messages come before a gap, when the middle isn't shown.
    public let omittedAfter: Int?
    public let files: [StoredFile]

    public init(messages: [TranscriptMessage], omittedAfter: Int? = nil, files: [StoredFile]) {
        self.messages = messages
        self.omittedAfter = omittedAfter
        self.files = files
    }
}
