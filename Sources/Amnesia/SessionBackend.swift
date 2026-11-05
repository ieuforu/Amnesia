import AmnesiaCore
import AppKit

/// Where the panel's data comes from and where its actions go.
protocol SessionBackend: Sendable {
    func load() async -> (sessions: [Session], leftovers: [Leftover])
    func delete(_ sessions: [Session]) async -> [DeletionResult]
    /// Returns how many leftovers couldn't be removed.
    func clean(_ leftovers: [Leftover]) async -> Int
    func reveal(_ session: Session) async
    func detail(for session: Session) async -> SessionDetail
}

/// Reads and changes the agents' real data.
struct LiveBackend: SessionBackend {
    func load() async -> (sessions: [Session], leftovers: [Leftover]) {
        await Task.detached(priority: .userInitiated) {
            let sessions = SessionScanner().scan()
            return (sessions, LeftoverScanner().scan(excluding: sessions))
        }.value
    }

    func delete(_ sessions: [Session]) async -> [DeletionResult] {
        await Task.detached(priority: .userInitiated) {
            SessionDeleter().delete(sessions)
        }.value
    }

    func clean(_ leftovers: [Leftover]) async -> Int {
        await Task.detached(priority: .userInitiated) {
            LeftoverCleaner().clean(leftovers)
        }.value
    }

    @MainActor
    func reveal(_ session: Session) {
        NSWorkspace.shared.activateFileViewerSelecting([session.fileURL])
    }

    func detail(for session: Session) async -> SessionDetail {
        await Task.detached(priority: .userInitiated) {
            SessionReader().detail(for: session)
        }.value
    }
}

/// Shows made-up data for screenshots. Actions only change this in-memory copy,
/// and it has no way to reach real sessions.
actor DemoBackend: SessionBackend {
    private var sessions = DemoData.sessions()
    private var leftovers = DemoData.leftovers()

    func load() -> (sessions: [Session], leftovers: [Leftover]) {
        (sessions, leftovers)
    }

    func delete(_ selected: [Session]) -> [DeletionResult] {
        let ids = Set(selected.map(\.id))
        sessions.removeAll { ids.contains($0.id) }
        return selected.map { DeletionResult(session: $0, outcome: .deleted) }
    }

    func clean(_ selected: [Leftover]) -> Int {
        let ids = Set(selected.map(\.id))
        leftovers.removeAll { ids.contains($0.id) }
        return 0
    }

    func reveal(_ session: Session) {}

    func detail(for session: Session) -> SessionDetail {
        DemoData.detail(for: session)
    }
}
