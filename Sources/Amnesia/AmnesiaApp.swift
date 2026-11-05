import SwiftUI

@main
struct AmnesiaApp: App {
    /// `--demo` shows made-up sessions, for screenshots.
    @State private var store = SessionStore(
        backend: CommandLine.arguments.contains("--demo") ? DemoBackend() : LiveBackend()
    )

    var body: some Scene {
        MenuBarExtra("Amnesia", systemImage: "brain") {
            ContentView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
