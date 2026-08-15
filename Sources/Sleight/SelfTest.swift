import CoreGraphics
import Foundation

/// Exercises the state machine directly, with no event tap and no permissions.
///
/// Worth having from day one: every reported failure in this class of app is a
/// state-machine edge case (a stuck modifier, a doubled character, a tap that
/// fired during a shortcut), and those are all reproducible right here.
enum SelfTest {
    private static var failures = 0

    /// The bits we actually reason about. Real events also carry housekeeping
    /// flags such as `maskNonCoalesced`, which say nothing about modifiers.
    fileprivate static let modifierMask: CGEventFlags =
        [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    static func run() -> Int32 {
        let config = Config(bindings: [
            KeyBinding(keyCode: KeyCode.kana, tapKeyCode: KeyCode.kana, hold: .hyper),
            KeyBinding(keyCode: KeyCode.eisu, tapKeyCode: KeyCode.eisu, hold: .control),
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: nil, hold: .control),
        ])

        tapEmitsTheTapKey(config)
        holdSuppressesTheTapKey(config)
        holdAppliesModifiersToTheOtherKey(config)
        autorepeatDoesNotDoubleFire(config)
        holdOnlyKeyEmitsNothingOnTap(config)
        unboundKeysAreUntouched(config)
        resetClearsStuckModifiers(config)
        modifierKeyTapEmitsItsTapKey()
        modifierKeyHoldActsAsModifier()
        pausingPassesEverythingThrough(config)
        unchangedHoldKeepsTheKeyWorking()

        if failures == 0 {
            print("\nall checks passed")
            return 0
        }
        print("\n\(failures) check(s) FAILED")
        return 1
    }

    // MARK: - Cases

    private static func tapEmitsTheTapKey(_ config: Config) {
        let h = Harness(config)
        expect(h.keyDown(KeyCode.kana) == .swallowed, "press of a bound key is withheld")
        expect(h.keyUp(KeyCode.kana) == .swallowed, "release of a bound key is withheld")
        expect(h.synthesized == [KeyCode.kana], "a lone press emits the tap key")
    }

    private static func holdSuppressesTheTapKey(_ config: Config) {
        let h = Harness(config)
        _ = h.keyDown(KeyCode.kana)
        _ = h.keyDown(0x00)  // 'a'
        _ = h.keyUp(0x00)
        _ = h.keyUp(KeyCode.kana)
        expect(h.synthesized.isEmpty, "a key used as a modifier emits no tap key")
    }

    private static func holdAppliesModifiersToTheOtherKey(_ config: Config) {
        let h = Harness(config)
        _ = h.keyDown(KeyCode.kana)
        let result = h.keyDown(0x00)
        expect(result == .passed, "the other key still reaches the app")
        expect(h.lastFlags.contains(.maskCommand), "hyper adds ⌘")
        expect(h.lastFlags.contains(.maskControl), "hyper adds ⌃")
        expect(h.lastFlags.contains(.maskAlternate), "hyper adds ⌥")
        expect(h.lastFlags.contains(.maskShift), "hyper adds ⇧")
    }

    private static func autorepeatDoesNotDoubleFire(_ config: Config) {
        let h = Harness(config)
        _ = h.keyDown(KeyCode.kana)
        _ = h.keyDown(KeyCode.kana, autorepeat: true)
        _ = h.keyDown(KeyCode.kana, autorepeat: true)
        _ = h.keyUp(KeyCode.kana)
        expect(h.synthesized == [KeyCode.kana], "autorepeat while held emits the tap key once")
    }

    private static func holdOnlyKeyEmitsNothingOnTap(_ config: Config) {
        let h = Harness(config)
        _ = h.keyDown(KeyCode.capsLock)
        _ = h.keyUp(KeyCode.capsLock)
        expect(h.synthesized.isEmpty, "a hold-only key emits nothing when tapped")
    }

    private static func unboundKeysAreUntouched(_ config: Config) {
        let h = Harness(config)
        expect(h.keyDown(0x00) == .passed, "unbound keys pass through")
        expect(h.lastFlags.isEmpty, "unbound keys gain no modifiers")
    }

    private static func resetClearsStuckModifiers(_ config: Config) {
        let h = Harness(config)
        _ = h.keyDown(KeyCode.kana)
        _ = h.keyDown(0x00)  // now in the held state
        h.engine.reset()  // as happens on sleep
        _ = h.keyDown(0x01)
        expect(h.lastFlags.isEmpty, "reset drops modifiers instead of sticking them on")
    }

    /// Caps Lock and the right-hand modifiers are the only spare keys an ANSI
    /// keyboard has, and they arrive as `flagsChanged` rather than key events, so
    /// they get their own coverage.
    private static func modifierKeyTapEmitsItsTapKey() {
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        expect(h.modifierDown(KeyCode.capsLock) == .swallowed, "Caps Lock press is withheld")
        expect(h.modifierUp(KeyCode.capsLock) == .swallowed, "Caps Lock release is withheld")
        expect(h.synthesized == [KeyCode.escape], "tapping Caps Lock emits Escape")
    }

    private static func modifierKeyHoldActsAsModifier() {
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        _ = h.modifierDown(KeyCode.capsLock)
        _ = h.keyDown(0x00)  // 'a'
        expect(h.lastFlags == .maskControl, "holding Caps Lock adds ⌃ and nothing else")
        _ = h.keyUp(0x00)
        _ = h.modifierUp(KeyCode.capsLock)
        expect(h.synthesized.isEmpty, "Caps Lock used as a modifier emits no Escape")
    }

    /// What the Pause menu item does. Also covers the case that would be worst to
    /// get wrong: pausing mid-press must not strand the key as a held modifier.
    private static func pausingPassesEverythingThrough(_ config: Config) {
        let h = Harness(config)
        _ = h.keyDown(KeyCode.kana)  // armed, awaiting a decision
        h.engine.isPaused = true

        expect(h.keyDown(KeyCode.kana) == .passed, "paused, a bound key reaches the app")
        expect(h.keyUp(KeyCode.kana) == .passed, "paused, its release reaches the app too")
        expect(h.synthesized.isEmpty, "paused, no tap key is emitted")
        expect(h.lastFlags.isEmpty, "pausing mid-press does not strand a modifier")

        h.engine.isPaused = false
        _ = h.keyDown(KeyCode.kana)
        _ = h.keyUp(KeyCode.kana)
        expect(h.synthesized == [KeyCode.kana], "resuming restores remapping")
    }

    /// The Command-key-to-input-source arrangement, which is why `.unchanged`
    /// exists. Command has to keep reaching the system or holding it to page
    /// through the app switcher stops working.
    private static func unchangedHoldKeepsTheKeyWorking() {
        let leftCommand: Int64 = 0x37
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: leftCommand, tapKeyCode: KeyCode.eisu, hold: .unchanged)
        ]))

        expect(h.modifierDown(leftCommand) == .passed, "Command still reaches the system")
        expect(h.modifierUp(leftCommand) == .passed, "so does its release")
        expect(h.synthesized == [KeyCode.eisu], "tapping Command emits Eisu")

        // Used as a modifier it must stay silent, or every shortcut would also
        // switch input source.
        let combo = Harness(Config(bindings: [
            KeyBinding(keyCode: leftCommand, tapKeyCode: KeyCode.eisu, hold: .unchanged)
        ]))
        _ = combo.modifierDown(leftCommand)
        expect(combo.keyDown(0x08) == .passed, "the other key of a shortcut passes")
        _ = combo.keyUp(0x08)
        _ = combo.modifierUp(leftCommand)
        expect(combo.synthesized.isEmpty, "Command-C does not emit Eisu")
    }

    // MARK: - Harness

    private enum Outcome { case passed, swallowed }

    private final class Harness {
        let engine: TapHoldEngine
        var synthesized: [Int64] = []
        var lastFlags = CGEventFlags()

        init(_ config: Config) {
            engine = TapHoldEngine(config: config)
            engine.onSynthetic = { [weak self] code in self?.synthesized.append(code) }
        }

        func keyDown(_ code: Int64, autorepeat: Bool = false) -> Outcome {
            send(code, type: .keyDown, autorepeat: autorepeat)
        }

        func keyUp(_ code: Int64) -> Outcome {
            send(code, type: .keyUp, autorepeat: false)
        }

        /// A modifier going down: `flagsChanged` carrying that key's own bit.
        func modifierDown(_ code: Int64) -> Outcome {
            send(code, type: .flagsChanged, autorepeat: false,
                 flags: CGEventFlags(rawValue: KeyCode.modifierBits[code] ?? 0))
        }

        /// The same key going up: `flagsChanged` with the bit cleared.
        func modifierUp(_ code: Int64) -> Outcome {
            send(code, type: .flagsChanged, autorepeat: false, flags: CGEventFlags())
        }

        private func send(
            _ code: Int64, type: CGEventType, autorepeat: Bool, flags: CGEventFlags? = nil
        ) -> Outcome {
            let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(code),
                keyDown: type == .keyDown)!
            event.type = type
            if let flags { event.flags = flags }
            if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
            lastFlags = CGEventFlags()
            guard engine.handle(type: type, event: event) != nil else { return .swallowed }
            lastFlags = event.flags.intersection(SelfTest.modifierMask)
            return .passed
        }
    }

    private static func expect(_ condition: Bool, _ what: String) {
        if condition {
            print("  ok    \(what)")
        } else {
            print("  FAIL  \(what)")
            failures += 1
        }
    }
}
