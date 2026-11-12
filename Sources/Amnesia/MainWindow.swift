import AppKit
import SwiftUI

/// Owns the main window. It's created by hand rather than as a SwiftUI scene,
/// so background and menu bar launches can opt out of activating the window.
/// The Dock icon appears only while the library is open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private let libraryUndo = UndoManager()
    private let opening = LibraryOpening()

    func show(store: SessionStore, activate: Bool = true) {
        if activate { opening.presentFirstTime() }
        let window = window ?? makeWindow(store: store)
        self.window = window

        NSApp.setActivationPolicy(.regular)
        if activate {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    private func makeWindow(store: SessionStore) -> NSWindow {
        let content = NSHostingController(rootView: LibraryWindowView(store: store, undoManager: libraryUndo, opening: opening))
        // Keep the window's own size.
        content.sizingOptions = []

        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Amnesia"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 930, height: 520)
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        window.setContentSize(NSSize(width: min(1180, screen.width - 32), height: min(760, screen.height - 32)))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        opening.presentFirstTime()
    }
}
