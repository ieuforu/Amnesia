import AmnesiaCore
import SwiftUI

/// Connects the panel to live session data.
struct ContentView: View {
    let store: SessionStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SessionPanel(
            sessions: store.sessions,
            isBusy: store.isBusy,
            failureMessage: store.failureMessage,
            onRefresh: { Task { await store.refresh() } },
            onReveal: reveal,
            onDelete: { selected in Task { await store.delete(selected) } }
        )
        .task { await store.refresh() }
    }

    /// Clicking inside the panel doesn't dismiss it, so close it before Finder
    /// comes forward.
    private func reveal(_ session: Session) {
        dismiss()
        NSWorkspace.shared.activateFileViewerSelecting([session.fileURL])
    }
}
