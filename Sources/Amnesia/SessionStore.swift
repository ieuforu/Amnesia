import AmnesiaCore
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var leftovers: [Leftover] = []
    private(set) var isBusy = false
    private(set) var failureMessage: String?

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        await rescan()
    }

    func delete(_ selected: [Session]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let results = await Task.detached(priority: .userInitiated) {
            SessionDeleter().delete(selected)
        }.value

        failureMessage = Self.failureMessage(for: results)
        await rescan()
    }

    func clean(_ selected: [Leftover]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let failures = await Task.detached(priority: .userInitiated) {
            LeftoverCleaner().clean(selected)
        }.value

        failureMessage = failures > 0 ? "\(failures) leftovers not removed." : nil
        await rescan()
    }

    private func rescan() async {
        (sessions, leftovers) = await Task.detached(priority: .userInitiated) {
            let sessions = SessionScanner().scan()
            return (sessions, LeftoverScanner().scan(excluding: sessions))
        }.value
    }

    private static func failureMessage(for results: [DeletionResult]) -> String? {
        let skipped = results.filter { $0.outcome == .skippedInUse }.count
        let reasons = results.compactMap { result -> String? in
            if case .failed(let reason) = result.outcome { reason } else { nil }
        }

        var parts: [String] = []
        if skipped > 0 {
            parts.append("Skipped \(skipped) in use.")
        }
        if let reason = reasons.first {
            parts.append("\(reasons.count) not deleted: \(reason)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
