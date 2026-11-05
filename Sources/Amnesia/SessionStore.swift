import AmnesiaCore
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var groups: [SessionGroup] = []
    private(set) var isScanning = false

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        groups = await Task.detached(priority: .userInitiated) {
            SessionGroup.grouping(SessionScanner().scan())
        }.value
    }
}
