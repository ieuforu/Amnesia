import AmnesiaCore
import Foundation

struct LibraryLaunchGroup: Identifiable {
    let id: String
    let title: String
    let path: String?
    let sessions: [Session]

    /// The library store supplies sessions in newest-first order.
    static func make(from sessions: [Session]) -> [Self] {
        Dictionary(grouping: sessions, by: \.projectPath).map { path, sessions in
            LibraryLaunchGroup(
                id: path.map { "path:" + $0 } ?? "unknown",
                title: title(for: path),
                path: path,
                sessions: sessions
            )
        }.sorted {
            let first = $0.sessions.first?.updatedAt ?? .distantPast
            let second = $1.sessions.first?.updatedAt ?? .distantPast
            return first == second ? $0.id < $1.id : first > second
        }
    }

    private static func title(for path: String?) -> String {
        guard let path else { return "Unknown directory" }
        let displayPath = (path as NSString).abbreviatingWithTildeInPath
        if displayPath == "~" { return "Home" }
        let name = (displayPath as NSString).lastPathComponent
        return name.isEmpty ? displayPath : name
    }
}
