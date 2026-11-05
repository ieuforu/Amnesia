import AmnesiaCore
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var leftovers: [Leftover] = []
    private(set) var isBusy = false
    private(set) var failureMessage: String?

    private let backend: any SessionBackend

    init(backend: any SessionBackend) {
        self.backend = backend
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        await reload()
    }

    func delete(_ selected: [Session]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        failureMessage = Self.failureMessage(for: await backend.delete(selected))
        await reload()
    }

    func clean(_ selected: [Leftover]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let failures = await backend.clean(selected)
        failureMessage = failures > 0 ? "\(failures) leftovers not removed." : nil
        await reload()
    }

    func reveal(_ session: Session) {
        Task { await backend.reveal(session) }
    }

    private func reload() async {
        (sessions, leftovers) = await backend.load()
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
