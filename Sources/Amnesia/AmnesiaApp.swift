import SwiftUI

@main
struct AmnesiaApp: App {
    @State private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra("Amnesia", systemImage: "brain") {
            ContentView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
