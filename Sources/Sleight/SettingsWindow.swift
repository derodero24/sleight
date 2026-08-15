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
                self?.window?.close()
            },
            onSave: { [weak self] in
                self?.store.commit()
                self?.window?.close()
            })

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Sleight"
        window.styleMask = [.titled, .closable]
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
            // Closing without saving discards, matching every other window that
            // has an explicit Save. Nothing has been applied yet either way.
            self.store.cancel()
        }
    }
}
