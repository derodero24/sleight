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

    init(config: Config, verbose: Bool = false) {
        var map: [Int64: KeyBinding] = [:]
        for binding in config.bindings { map[binding.keyCode] = binding }
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
            return handleBoundKeyUp(keyCode: keyCode)
        case .flagsChanged where isBound:
            // Caps Lock, Right Command and friends never produce keyDown/keyUp.
            // Swallowing these is also what stops Caps Lock from toggling.
            return KeyCode.isPress(code: keyCode, flags: event.flags)
                ? handleBoundKeyDown(keyCode: keyCode, event: event)
                : handleBoundKeyUp(keyCode: keyCode)
        case .keyDown, .keyUp, .flagsChanged:
            return handleOtherKey(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleBoundKeyDown(keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Auto-repeat while held tells us nothing new, and forwarding it would
        // spam whatever the key is standing in for.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 { return nil }
        if states[keyCode] == nil {
            states[keyCode] = .pending
            trace("armed \(KeyCode.describe(keyCode)) - withholding until release")
        }
        return nil  // Withhold until release decides what this press meant.
    }

    private func handleBoundKeyUp(keyCode: Int64) -> Unmanaged<CGEvent>? {
        let state = states.removeValue(forKey: keyCode)
        // Nothing else was pressed in the meantime, so this was a tap.
        if state == .pending, let tapKey = bindings[keyCode]?.tapKeyCode {
            trace("TAP  \(KeyCode.describe(keyCode)) -> emitting \(KeyCode.describe(tapKey))")
            postSynthetic(keyCode: tapKey)
        } else if state == .held {
            trace("HOLD released: \(KeyCode.describe(keyCode))")
        }
        return nil
    }

    /// Any key that is not itself bound. Its arrival is what commits pending keys
    /// to their hold role, and it carries the resulting modifiers.
    private func handleOtherKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown || type == .flagsChanged {
            for (code, state) in states where state == .pending {
                // A key with no hold behaviour stays a tap no matter what follows.
                guard let hold = bindings[code]?.hold else { continue }
                states[code] = .held
                trace("HOLD \(KeyCode.describe(code)) -> \(hold.rawValue)")
            }
        }

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
        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: isDown
            ) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
