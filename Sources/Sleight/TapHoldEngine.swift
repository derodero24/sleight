import CoreGraphics
import Foundation

/// Marker stamped on the events we synthesize so the tap can recognise its own
/// output and pass it straight through. Without this the engine feeds itself.
private let syntheticMarker: Int64 = 0x5441_5048  // "TAPH"

/// Timeless tap/hold resolution.
///
/// There is no timer. A bound key resolves to *hold* the moment any other key is
/// pressed while it is down, and to *tap* otherwise - decided on release. That
/// removes the usual tradeoff where a short threshold misfires during fast typing
/// and a long one adds perceptible lag to every modifier press.
final class TapHoldEngine {
    private enum State {
        /// Key is down; we have not yet seen anything that forces a decision.
        case pending
        /// Another key arrived while it was down, so it is acting as a modifier.
        case held
    }

    private let bindings: [Int64: KeyBinding]
    private var states: [Int64: State] = [:]
    private let source = CGEventSource(stateID: .hidSystemState)
    private let verbose: Bool

    /// Fired whenever a tap resolves. Lets the self-test observe decisions without
    /// needing the Accessibility permission that actually posting an event does.
    var onSynthetic: ((Int64) -> Void)?

    /// Passes every event through untouched. Lives here rather than on the tap so
    /// that pausing cannot leave a half-resolved key behind, and so it is testable
    /// without installing a tap at all.
    var isPaused = false {
        didSet { if isPaused { reset() } }
    }

    /// Swallows every event instead, while the settings window is waiting for a
    /// key. Recording used to borrow `isPaused`, which passes events through - so
    /// the key you pressed to configure a field also reached whatever was in front:
    /// binding Return pressed the window's default button, and binding Caps Lock
    /// turned Caps Lock on.
    var isRecording = false {
        didSet { if isRecording { reset() } }
    }

    init(config: Config, verbose: Bool = false) {
        // Both of these can only come from a hand-edited file, and both used to
        // fail silently: a key that is swallowed and never emits anything looks
        // exactly like a broken keyboard, and the second of two bindings for the
        // same key quietly replaced the first.
        var map: [Int64: KeyBinding] = [:]
        for binding in config.bindings {
            guard binding.isUsable else {
                Log.warn("ignoring \(KeyCode.describe(binding.keyCode)): neither tap nor hold set")
                continue
            }
            guard map[binding.keyCode] == nil else {
                Log.warn("ignoring a second binding for \(KeyCode.describe(binding.keyCode))")
                continue
            }
            // A key that reports through flagsChanged but has no bit in the table
            // can never be told press from release, so it would be swallowed for
            // ever without emitting anything - a dead key with no explanation.
            if binding.hold != .unchanged, KeyCode.reportsAsFlagsOnly(binding.keyCode),
               !KeyCode.isModifier(binding.keyCode) {
                Log.warn("ignoring \(KeyCode.describe(binding.keyCode)): "
                    + "this key cannot be tracked reliably")
                continue
            }
            map[binding.keyCode] = binding
        }
        self.bindings = map
        self.verbose = verbose
    }

    private func trace(_ message: @autoclosure () -> String) {
        if verbose { Log.info("  \(message())") }
    }

    var boundKeyDescriptions: [String] {
        bindings.values.sorted { $0.keyCode < $1.keyCode }.map(\.label)
    }

    /// Modifiers contributed by every key currently in the held state.
    private var activeHoldFlags: CGEventFlags {
        var flags = CGEventFlags()
        for (code, state) in states where state == .held {
            if let hold = bindings[code]?.hold { flags.formUnion(hold.flags) }
        }
        return flags
    }

    /// Drops any in-flight state. Called on wake and whenever the tap is
    /// re-armed, so a key that was down across the event never sticks as a
    /// phantom modifier.
    func reset() {
        guard !states.isEmpty else { return }
        Log.info("engine reset (cleared \(states.count) in-flight key(s))")
        states.removeAll()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Order matters: recording wins, so that arming a field cannot also type.
        guard !isRecording else { return nil }
        guard !isPaused else { return Unmanaged.passUnretained(event) }

        // Our own synthetic taps must never re-enter the state machine.
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isBound = bindings[keyCode] != nil

        switch type {
        case .keyDown where isBound:
            return handleBoundKeyDown(keyCode: keyCode, event: event)
        case .keyUp where isBound:
            return handleBoundKeyUp(keyCode: keyCode, event: event)
        case .flagsChanged where isBound:
            // Caps Lock, Right Command and friends never produce keyDown/keyUp.
            // Swallowing these is also what stops Caps Lock from toggling.
            //
            // A release with nothing waiting cannot be a release, so it is treated
            // as a press. That keeps the key working even on hardware whose flags
            // do not report the physical state the way the table expects, rather
            // than swallowing it for ever.
            let looksLikePress = KeyCode.isPress(code: keyCode, flags: event.flags)
            return looksLikePress || states[keyCode] == nil
                ? handleBoundKeyDown(keyCode: keyCode, event: event)
                : handleBoundKeyUp(keyCode: keyCode, event: event)
        case .keyDown, .keyUp, .flagsChanged:
            return handleOtherKey(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// True when the key keeps doing its own job and we only add the tap.
    private func passesThrough(_ keyCode: Int64) -> Bool {
        bindings[keyCode]?.hold == .unchanged
    }

    /// Commits every waiting key to its hold role, because something else has
    /// arrived that it must be modifying.
    private func promotePending(except exempt: Int64?) {
        for (code, state) in states where state == .pending && code != exempt {
            // A key with no hold behaviour stays a tap no matter what follows.
            guard let hold = bindings[code]?.hold else { continue }
            states[code] = .held
            trace("HOLD \(KeyCode.describe(code)) -> \(hold.rawValue)")
        }
    }

    private func handleBoundKeyDown(keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        let through = passesThrough(keyCode)

        // Auto-repeat while held tells us nothing new, and forwarding it would
        // spam whatever the key is standing in for.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return through ? Unmanaged.passUnretained(event) : nil
        }
        // A bound key is still "another key" to anything already pending. Without
        // this, holding one bound key and tapping a second resolved both as taps:
        // hold Kana and tap Eisu and you got 英数 and かな at once, instead of the
        // chord you meant.
        promotePending(except: keyCode)

        if states[keyCode] == nil {
            states[keyCode] = .pending
            trace("armed \(KeyCode.describe(keyCode))\(through ? "" : " - withholding until release")")
        }
        // Otherwise withhold, since only the release says what the press meant.
        return through ? Unmanaged.passUnretained(event) : nil
    }

    private func handleBoundKeyUp(keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        let state = states.removeValue(forKey: keyCode)
        // Nothing else was pressed in the meantime, so this was a tap.
        if state == .pending, let tapKey = bindings[keyCode]?.tapKeyCode {
            trace("TAP  \(KeyCode.describe(keyCode)) -> emitting \(KeyCode.describe(tapKey))")
            postSynthetic(keyCode: tapKey)
        } else if state == .held {
            trace("HOLD released: \(KeyCode.describe(keyCode))")
        }
        return passesThrough(keyCode) ? Unmanaged.passUnretained(event) : nil
    }

    /// Any key that is not itself bound. Its arrival is what commits pending keys
    /// to their hold role, and it carries the resulting modifiers.
    private func handleOtherKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Only a key going *down* means the pending key is being used as a
        // modifier. Promoting on flagsChanged regardless counted a modifier being
        // released as well, so lifting Shift a moment late while reaching for a
        // tap key turned that tap into a hold and swallowed it.
        let otherKeyWentDown: Bool
        switch type {
        case .keyDown:
            otherKeyWentDown = true
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            otherKeyWentDown = KeyCode.isPress(code: code, flags: event.flags)
        default:
            otherKeyWentDown = false
        }

        if otherKeyWentDown { promotePending(except: nil) }

        let flags = activeHoldFlags
        if !flags.isEmpty {
            event.flags.formUnion(flags)
            let target = KeyCode.describe(event.getIntegerValueField(.keyboardEventKeycode))
            trace("     applied \(flags.modifierSymbols) to \(target)")
        }
        return Unmanaged.passUnretained(event)
    }

    private func postSynthetic(keyCode: Int64) {
        onSynthetic?(keyCode)
        // Whatever else is being held still applies. Without this, holding a hyper
        // key and tapping a bound key sent the tap key bare, so hyper-plus-tap was
        // not expressible at all.
        let flags = activeHoldFlags

        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: isDown
            ) else { continue }
            if !flags.isEmpty { event.flags.formUnion(flags) }
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
