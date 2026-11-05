import AmnesiaCore
import SwiftUI

/// Connects the panel to live session data.
struct ContentView: View {
    let store: SessionStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SessionPanel(
            sessions: store.sessions,
            leftovers: store.leftovers,
            isBusy: store.isBusy,
            failureMessage: store.failureMessage,
            onRefresh: { Task { await store.refresh() } },
            onReveal: reveal,
            onDelete: { selected in Task { await store.delete(selected) } },
            onCleanLeftovers: { selected in Task { await store.clean(selected) } }
        )
        .task { await store.refresh() }
        // The panel's view stays alive between openings, so `task` only covers
        // the first one. Opening the panel makes its window key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await store.refresh() }
        }
    }

    /// Clicking inside the panel doesn't dismiss it, so close it before Finder
    /// comes forward.
    private func reveal(_ session: Session) {
        dismiss()
        store.reveal(session)
    }
}
