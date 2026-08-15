import AppKit

/// Owns startup for the windowed (menu bar) mode.
///
/// Everything here has to happen after AppKit has finished launching. Exiting
/// before that point looks to Launch Services like an app that started and then
/// stopped responding, which it reports to the user as a failure to open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let args: Set<String>
    private var controller: EventTapController?
    private var statusItem: StatusItem?
    private var settings: SettingsStore?
    private var permissionPoll: Timer?

    init(args: Set<String>) {
        self.args = args
    }

    /// Opening an app that is already running should show something. Launch
    /// Services usually reactivates the existing process rather than starting a
    /// second one, so this, not the duplicate-instance path, is what normally runs.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        statusItem?.showSettings()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstance.claim() else {
            // Nothing to bring forward: an accessory app has no window, and its
            // menu bar item is already sitting there.
            NSApp.terminate(nil)
            return
        }

        if ensureAccessibilityPermission(prompt: true) {
            startTap()
        } else {
            // Polling rather than blocking. The main thread has to stay live or
            // the permission prompt itself cannot be drawn.
            Log.info("waiting for Accessibility permission")
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
                [weak self] timer in
                guard ensureAccessibilityPermission(prompt: false) else { return }
                timer.invalidate()
                Log.info("permission granted")
                self?.startTap()
            }
        }
    }

    private func startTap() {
        let config = Config.load()
        config.writeIfAbsent()

        let engine = TapHoldEngine(config: config, verbose: args.contains("--verbose"))
        let controller = EventTapController(engine: engine)

        guard controller.start() else {
            Log.warn("could not create the event tap despite holding permission")
            NSApp.terminate(nil)
            return
        }

        Log.info("keyboard layout: \(KeyboardLayout.detect().rawValue)")
        for line in engine.boundKeyDescriptions { Log.info("  \(line)") }

        let store = SettingsStore(config: config, controller: controller)
        self.controller = controller
        self.settings = store
        self.statusItem = StatusItem(controller: controller, store: store)

        if args.contains("--dump-menu") {
            statusItem?.dumpMenu()
            NSApp.terminate(nil)
        }
        if args.contains("--test-kill-tap") {
            Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                controller.debugDisableTap()
            }
        }
    }
}
