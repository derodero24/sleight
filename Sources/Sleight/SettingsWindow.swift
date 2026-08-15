import AppKit
import SwiftUI

/// Hosts the settings view at a fixed size.
final class SettingsWindow {
    private var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        if let window {
            // Only start a new undoable session if this is not already open;
            // re-showing a visible window must not discard what Cancel goes back to.
            if !window.isVisible { store.beginEditing() }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        store.beginEditing()

        let view = SettingsView(
            store: store,
            onCancel: { [weak self] in
                self?.store.cancel()
                self?.close()
            },
            onDone: { [weak self] in
                self?.store.commit()
                self?.close()
            })

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Sleight"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Leaving a field armed would swallow the next key pressed anywhere.
            self.store.recording = nil
            // Closing the window keeps the edits, since they are already in effect
            // and have been all along. Discarding them is what Cancel is for.
            self.store.commit()
        }
    }

    private func close() {
        window?.close()
    }
}
