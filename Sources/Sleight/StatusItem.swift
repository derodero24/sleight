import AppKit
import ServiceManagement

/// The menu bar presence: a short menu, with everything else behind Settings.
final class StatusItem: NSObject, NSMenuDelegate {
    private let controller: EventTapController
    private let item: NSStatusItem
    private let store: SettingsStore
    private lazy var settingsWindow = SettingsWindow(store: store)

    init(controller: EventTapController, store: SettingsStore) {
        self.controller = controller
        self.store = store
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        updateIcon()

        controller.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }

        // The recorder reads from the tap rather than from the view, because
        // Caps Lock and the modifiers never produce a key press a view can see.
        controller.keyObserver = { [weak self] code, _ in
            guard let self, self.store.recording != nil else { return }
            DispatchQueue.main.async { self.store.record(code) }
        }

        if let button = item.button {
            let icon = button.image != nil ? "hand.tap symbol" : "text '\(button.title)'"
            Log.info("menu bar item ready, showing \(icon), width \(Int(button.frame.width))")
        } else {
            Log.warn("menu bar item has no button; the item will not be visible")
        }
        // Opening the app while it is already running should show its settings,
        // the way opening any running app brings up its window.
        DistributedNotificationCenter.default().addObserver(
            forName: SingleInstance.showSettings, object: nil, queue: .main
        ) { [weak self] _ in
            // Through showSettings, not straight to the window: without a tap
            // every field would arm and wait for a key that can never arrive.
            self?.showSettings()
        }

        reportPlacement()
    }

    /// Reports where the item actually landed once the menu bar has laid out.
    ///
    /// A crowded menu bar is the usual reason an item cannot be found: macOS drops
    /// whatever does not fit without saying so, and on a notched display it can be
    /// hidden behind the notch. Both cases look identical to "the app did not
    /// start", so it is worth being able to tell them apart.
    private func reportPlacement() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let window = self.item.button?.window else {
                Log.warn("placement: the item has no window, so it is not on screen")
                return
            }
            let frame = window.frame
            guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            else {
                Log.warn("placement: item at \(frame) is off screen, the menu bar is full")
                return
            }
            let fromRight = Int(screen.frame.maxX - frame.maxX)
            Log.info("placement: \(fromRight)pt from the right edge of the menu bar")
        }
    }

    /// Builds the menu and prints it. The menu is rebuilt on every open, so this
    /// exercises the same path a click does without needing UI automation.
    func dumpMenu() {
        guard let menu = item.menu else {
            print("no menu attached")
            return
        }
        for paused in [false, true] {
            controller.isPaused = paused
            menuNeedsUpdate(menu)
            print("--- \(paused ? "paused" : "active") ---")
            for entry in menu.items {
                let mark = entry.state == .on ? "[x]" : (entry.isEnabled ? "   " : "(-)")
                print(entry.isSeparatorItem ? "    ---" : "\(mark) \(entry.title)")
            }
        }
        controller.isPaused = false
    }

    // MARK: - Appearance

    /// Redraws the icon after something outside the menu changed the state.
    func refresh() {
        updateIcon()
    }

    /// The app's own mark, so the menu bar and the Dock agree. The two exception
    /// states borrow system symbols instead, because looking unlike the normal
    /// state is the entire job there.
    private func updateIcon() {
        guard let button = item.button else { return }
        guard controller.isRunning else {
            // Not merely paused: nothing works at all until permission is granted,
            // and that deserves to look different rather than quietly identical.
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: L("menu.noPermission"))
            button.image?.isTemplate = true
            button.title = ""
            button.appearsDisabled = false
            return
        }
        // Recording swallows every key on the machine, so it cannot look the same
        // as running normally: the window can be behind something, and then this
        // icon is the only thing on screen that can explain a dead keyboard.
        if controller.isRecording {
            button.image = NSImage(
                systemSymbolName: "record.circle",
                accessibilityDescription: L("menu.recording"))
            button.image?.isTemplate = true
            button.title = ""
            button.appearsDisabled = false
            return
        }
        button.image = MenuBarIcon.mark
        button.image?.accessibilityDescription = L(
            controller.isPaused ? "menu.paused" : "menu.active")
        button.title = ""
        button.appearsDisabled = controller.isPaused
    }

    // MARK: - Menu

    /// Rebuilt on every open so the binding list and pause state cannot go stale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard controller.isRunning else {
            menu.addItem(header(L("menu.noPermission")))
            menu.addItem(header("   " + L("menu.noPermissionDetail")))
            menu.addItem(.separator())
            add(to: menu, L("menu.openPrivacySettings"), #selector(openPrivacySettings), key: "")
            menu.addItem(.separator())
            add(to: menu, L("menu.quit"), #selector(quit), key: "q")
            return
        }

        if controller.isRecording {
            menu.addItem(header(L("menu.recording")))
            menu.addItem(header("   " + L("menu.recordingDetail")))
            menu.addItem(.separator())
            add(to: menu, L("menu.stopRecording"), #selector(stopRecording), key: "")
            menu.addItem(.separator())
            add(to: menu, L("menu.quit"), #selector(quit), key: "q")
            return
        }

        // No heading in the ordinary case. It restated what the icon and the
        // Pause item already say, and a disabled menu item is drawn grey enough
        // to be hard to read while still taking up the top of the menu. The two
        // exception states keep theirs, since nothing else explains them.
        add(to: menu, L("menu.settings"), #selector(showSettings), key: ",")
        add(to: menu, L(controller.isPaused ? "menu.resume" : "menu.pause"), #selector(togglePause), key: "p")

        menu.addItem(.separator())
        let launch = add(to: menu, L("menu.openAtLogin"), #selector(toggleLaunchAtLogin), key: "")
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        add(to: menu, L("menu.quit"), #selector(quit), key: "q")
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @discardableResult
    private func add(
        to menu: NSMenu, _ title: String, _ action: Selector, key: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func togglePause() {
        // Goes through the store so that a recording in progress cannot resume
        // the engine behind the user's back.
        store.pausedByUser.toggle()
        updateIcon()
    }

    @objc private func stopRecording() {
        store.recording = nil
    }

    @objc func showSettings() {
        // Recording reads from the tap, so without one every field would arm and
        // then wait forever - Escape included, since that is handled by the
        // recorder too. Send the user where they can fix it instead.
        guard controller.isRunning else {
            openPrivacySettings()
            return
        }
        settingsWindow.show()
    }

    @objc func openPrivacySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: pane) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // Usually because the app is not in /Applications. The menu closes on
            // click, so without this the item just appears not to work.
            Log.warn("could not change the login item: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = L("login.failed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
