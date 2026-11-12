import AppKit
import SwiftUI

@main
struct AmnesiaApp: App {
    @NSApplicationDelegateAdaptor private var launch: AmnesiaLaunchDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: launch.store)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Amnesia")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AmnesiaLaunchDelegate: NSObject, NSApplicationDelegate {
    /// `--demo` shows made-up sessions, for screenshots.
    let store = SessionStore(
        backend: CommandLine.arguments.contains("--demo") ? DemoBackend() : LiveBackend()
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--menu-bar-only") { return }
        if CommandLine.arguments.contains("--open-library-in-background") {
            MainWindowController.shared.show(store: store, activate: false)
        } else {
            MainWindowController.shared.show(store: store)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show(store: store)
        return false
    }
}
