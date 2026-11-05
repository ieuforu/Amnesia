import AppKit
import SwiftUI

/// Owns the main window. It's created by hand rather than as a SwiftUI scene,
/// because a scene would open at launch on macOS 14 and this app starts in the
/// menu bar. The Dock icon appears only while the window is open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show(store: SessionStore) {
        let window = window ?? makeWindow(store: store)
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if !window.isVisible {
            expand(window)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Fills the screen at once, because resizing a window every frame would
    /// compete with the map's own opening animation.
    private func expand(_ window: NSWindow) {
        guard let visible = (NSScreen.main ?? window.screen)?.visibleFrame else { return }
        window.setFrame(visible, display: false)
    }

    private func makeWindow(store: SessionStore) -> NSWindow {
        let content = NSHostingController(rootView: MainView(store: store))
        // Keep the window's own size.
        content.sizingOptions = []

        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Amnesia"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 930, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
