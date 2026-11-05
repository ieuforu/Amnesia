import SwiftUI

/// Connects the panel to live session data.
struct ContentView: View {
    let store: SessionStore

    var body: some View {
        SessionPanel(
            groups: store.groups,
            isScanning: store.isScanning,
            onRefresh: { Task { await store.refresh() } }
        )
        .task { await store.refresh() }
    }
}
