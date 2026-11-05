import Foundation

/// Sessions that ran in the same project directory.
public struct SessionGroup: Identifiable, Hashable, Sendable {
    public let projectPath: String?
    public let sessions: [Session]

    public var id: String { projectPath ?? "" }
    public var totalSize: Int64 { sessions.reduce(0) { $0 + $1.size } }
    /// The project's location, shortened for display.
    public var displayPath: String {
        guard let projectPath else { return "Unknown Project" }
        return (projectPath as NSString).abbreviatingWithTildeInPath
    }

    /// The project's folder name, or "Home" for the home folder.
    public var displayName: String {
        displayPath == "~" ? "Home" : (displayPath as NSString).lastPathComponent
    }

    public var deletableIDs: Set<String> { Set(sessions.filter(\.isDeletable).map(\.id)) }

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
