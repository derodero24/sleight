import AppKit

/// Owns startup for the menu bar mode.
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
    /// Services reactivates the existing process rather than starting a second
    /// one, so this, not the duplicate-instance path, is what normally runs.
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

        let config = Config.load()
        config.writeIfAbsent()

        let engine = TapHoldEngine(config: config, verbose: args.contains("--verbose"))
        let controller = EventTapController(engine: engine)
        let store = SettingsStore(config: config, controller: controller)

        self.controller = controller
        self.settings = store

        // Built before the tap, and unconditionally. This is the only interface
        // the app has, so waiting for permission left it completely invisible in
        // exactly the situation that most needs explaining. Reinstalling an
        // ad-hoc signed build revokes Accessibility, which makes that situation
        // routine rather than rare.
        self.statusItem = StatusItem(controller: controller, store: store)

        Log.info("keyboard layout: \(KeyboardLayout.detect().rawValue)")
        for line in engine.boundKeyDescriptions { Log.info("  \(line)") }

        startTapWhenPermitted()

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

    private func startTapWhenPermitted() {
        guard let controller else { return }

        if ensureAccessibilityPermission(prompt: true) {
            start(controller)
            return
        }

        Log.warn("Accessibility permission missing; remapping is off until granted")
        statusItem?.refresh()

        // Polling rather than blocking: the main thread has to stay live or the
        // permission prompt cannot be drawn and the menu cannot be opened.
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] timer in
            guard ensureAccessibilityPermission(prompt: false) else { return }
            timer.invalidate()
            Log.info("permission granted")
            guard let self, let controller = self.controller else { return }
            self.start(controller)
        }
    }

    private func start(_ controller: EventTapController) {
        if controller.start() {
            Log.info("remapping active")
        } else {
            Log.warn("could not create the event tap despite holding permission")
        }
        statusItem?.refresh()
    }
}
