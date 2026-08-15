import AppKit
import SwiftUI

/// Hosts the settings view. Sized to its content, so the window is exactly as
/// large as the list needs and no larger.
final class SettingsWindow {
    private var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: SettingsView(store: store))
        // Without this the window keeps whatever height it had when it opened, so
        // adding a key appends a row that is cropped off the bottom and looks like
        // the button did nothing.
        controller.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: controller)
        window.title = "Sleight"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        // Leaving a field armed after the window closes would swallow the next
        // key pressed anywhere on the system.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.store.recording = nil
        }
    }
}
