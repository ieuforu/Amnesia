import AmnesiaCore
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var isScanning = false

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        sessions = await Task.detached(priority: .userInitiated) {
            SessionScanner().scan()
        }.value
    }
}
