import Foundation

/// Sessions that ran in the same project directory.
public struct SessionGroup: Identifiable, Hashable, Sendable {
    public let projectPath: String?
    public let sessions: [Session]

    public var id: String { projectPath ?? "" }
    public var totalSize: Int64 { sessions.reduce(0) { $0 + $1.size } }

    /// Groups sessions by project, most recently used first.
    public static func grouping(_ sessions: [Session]) -> [SessionGroup] {
        Dictionary(grouping: sessions, by: \.projectPath)
            .map { path, sessions in
                SessionGroup(
                    projectPath: path,
                    sessions: sessions.sorted { $0.updatedAt > $1.updatedAt }
                )
            }
            .sorted { $0.sessions[0].updatedAt > $1.sessions[0].updatedAt }
    }
}
