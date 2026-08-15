import AppKit
import CoreGraphics
import Foundation

/// Owns the event tap and keeps it alive.
///
/// This is the part that matters. Every CGEventTap-based remapper on macOS shares
/// one bug: the system silently disables the tap - on a slow callback
/// (`tapDisabledByTimeout`), on certain user input, and across sleep - and the app
/// never re-arms it. The key just quietly stops working until you relaunch. It is
/// the single most common complaint filed against tools in this category, so the
/// recovery paths here are load-bearing, not defensive padding.
final class EventTapController {
    private var engine: TapHoldEngine
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?

    private(set) var reArmCount = 0

    /// Events pass through untouched while paused. The tap stays installed so
    /// that resuming is instant and does not re-prompt for permission.
    var isPaused: Bool {
        get { engine.isPaused }
        set { engine.isPaused = newValue }
    }

    /// Every key event, reported before the engine sees it. Drives the key code
    /// window, which is how anyone finds the code for a key worth binding.
    var keyObserver: ((Int64, CGEventType) -> Void)?

    /// The sniffer runs the same tap machinery in listen-only mode so that what it
    /// reports is exactly what the engine would see.
    private let sniffMode: Bool

    init(engine: TapHoldEngine, sniffMode: Bool = false) {
        self.engine = engine
        self.sniffMode = sniffMode
    }

    /// Swaps in a rebuilt engine after the config changes on disk. Pause state is
    /// a property of the session, not of the config, so it survives the swap.
    func reload(with engine: TapHoldEngine) {
        engine.isPaused = self.engine.isPaused
        self.engine.reset()
        self.engine = engine
    }

    // MARK: - Lifecycle

    func start() -> Bool {
        guard install() else { return false }
        observeSleepWake()
        startWatchdog()
        return true
    }

    @discardableResult
    private func install() -> Bool {
        teardown()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(context).takeUnretainedValue()
            return controller.dispatch(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: sniffMode ? .listenOnly : .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    private func teardown() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap { CFMachPortInvalidate(tap) }
        runLoopSource = nil
        tap = nil
    }

    // MARK: - Event dispatch

    private func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // These two arrive regardless of the event mask and mean the tap is dead.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
            Log.warn("tap disabled by \(reason) - re-arming")
            reArm()
            return nil
        }

        if type == .keyDown || type == .flagsChanged {
            keyObserver?(event.getIntegerValueField(.keyboardEventKeycode), type)
        }

        if sniffMode {
            report(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        return engine.handle(type: type, event: event)
    }

    private func report(type: CGEventType, event: CGEvent) {
        guard type == .keyDown || type == .flagsChanged else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard event.getIntegerValueField(.keyboardEventAutorepeat) != 1 else { return }
        let hex = String(format: "0x%02X", code)
        print("keyCode \(code)  (\(hex))   \(KeyCode.describe(code))")
    }

    // MARK: - Staying alive

    /// Re-enable in place if the port is still valid, otherwise rebuild from scratch.
    private func reArm() {
        reArmCount += 1
        engine.reset()

        if let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                Log.info("tap re-enabled (re-arm #\(reArmCount))")
                return
            }
        }

        Log.warn("tap port unusable - reinstalling")
        if install() {
            Log.info("tap reinstalled (re-arm #\(reArmCount))")
        } else {
            Log.warn("reinstall failed; check Accessibility permission")
        }
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in events {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Log.info("woke (\(name.rawValue)) - verifying tap")
                self?.verify()
            }
        }
        // Clear state *before* sleeping too: a key held as the lid closes would
        // otherwise come back as a modifier that is stuck on.
        center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.engine.reset()
        }
    }

    /// Belt and braces. Notifications can be missed and the tap can be disabled
    /// without any event reaching us, so poll cheaply as a backstop.
    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.verify()
        }
    }

    /// Simulates what macOS does to us unprompted, so the recovery paths can be
    /// proven rather than asserted. This is the failure every tool in this
    /// category ships with, so it deserves a test that actually triggers it.
    func debugDisableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        Log.warn("TEST: forcibly disabled the tap - watchdog should recover it")
    }

    private func verify() {
        guard let tap else {
            reArm()
            return
        }
        if !CFMachPortIsValid(tap) || !CGEvent.tapIsEnabled(tap: tap) {
            Log.warn("watchdog found the tap disabled")
            reArm()
        }
    }
}

/// Accessibility is required for `.defaultTap` (the mode that can modify events).
/// Note that macOS 26.1 has an Apple-side bug where a bare executable never
/// appears in the permission list - running from a signed .app bundle avoids it.
func ensureAccessibilityPermission(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
}
