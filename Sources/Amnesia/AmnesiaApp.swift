import SwiftUI

@main
struct AmnesiaApp: App {
    var body: some Scene {
        MenuBarExtra("Amnesia", systemImage: "brain") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
