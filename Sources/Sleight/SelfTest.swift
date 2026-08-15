import Combine
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
        cancellingSettingsRestoresThePreviousKeys()
        savingAnnouncesThatNothingIsPending()
        malformedBindingsAreIgnoredRatherThanObeyed()
        releasingAnotherModifierDoesNotEatTheTap()
        oneBoundKeyHeldWhileAnotherIsTapped()
        recordingSwallowsInsteadOfPassingThrough()
        capsLockIsTrackedByTheKeyNotTheLock()
        aResetMidChordDoesNotStrandAModifier()
        recordingAKeyDoesNotStrandItsModifier()
        holdFlagsStayOffModifierEvents()
        autorepeatOfAnotherKeyDoesNotForceAHold()
        aPassedThroughKeyThatRepeatedIsAHold()
        clickingWhileAKeyIsHeldIsNotATap()

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

    /// Cancel has to put back everything the window opened with, including keys
    /// that were removed. Getting a binding wrong can make the keyboard awkward to
    /// use, which is exactly when retyping the old values by hand is hardest.
    private static func cancellingSettingsRestoresThePreviousKeys() {
        let store = SettingsStore(
            config: Config(bindings: [
                KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
            ]),
            controller: nil)
        store.beginEditing()

        let original = store.bindings
        store.add()
        store.remove(original[0].id)
        expect(store.bindings.count == 1, "editing changed the list")
        expect(store.config.bindings.isEmpty, "and left nothing usable configured")

        store.cancel()
        expect(store.bindings == original, "cancel puts the original keys back")
        expect(
            store.config.bindings.first?.keyCode == KeyCode.capsLock,
            "including the one that was removed")
    }

    /// Saving moves the snapshot and nothing else, so unless that is announced the
    /// window keeps its buttons enabled and goes on saying the settings are
    /// unsaved - which is exactly what it did.
    private static func savingAnnouncesThatNothingIsPending() {
        let store = SettingsStore(
            config: Config(bindings: [
                KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
            ]),
            controller: nil)
        store.beginEditing()
        store.add()
        expect(store.hasChanges, "adding a key counts as a change")

        var announced = false
        let subscription = store.objectWillChange.sink { _ in announced = true }
        // The same state move that saving makes, without touching the disk.
        store.beginEditing()

        expect(!store.hasChanges, "once the snapshot catches up, nothing is pending")
        expect(announced, "and the window is told, so its buttons can update")
        subscription.cancel()
    }

    /// A hand-edited file can say things the settings window cannot, and the two
    /// worst were silent: a binding with neither half swallowed its key and
    /// emitted nothing, and a repeated key code let the later binding replace the
    /// earlier one without a word.
    private static func malformedBindingsAreIgnoredRatherThanObeyed() {
        let dead = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: nil, hold: nil)
        ]))
        expect(dead.modifierDown(KeyCode.capsLock) == .passed,
               "a binding with neither half leaves its key alone")
        expect(dead.modifierUp(KeyCode.capsLock) == .passed, "including on release")
        expect(dead.synthesized.isEmpty, "and emits nothing")

        let duplicate = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: nil),
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.tab, hold: nil),
        ]))
        _ = duplicate.modifierDown(KeyCode.capsLock)
        _ = duplicate.modifierUp(KeyCode.capsLock)
        expect(duplicate.synthesized == [KeyCode.escape],
               "a repeated key keeps the first binding, not the last")
    }

    /// Lifting Shift a moment late while reaching for a tap key used to promote
    /// that key to a hold, so the tap was silently swallowed. Lazy modifier
    /// release during fast typing is the norm, not an edge case.
    private static func releasingAnotherModifierDoesNotEatTheTap() {
        let leftShift: Int64 = 0x38
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        _ = h.modifierDown(leftShift)
        _ = h.modifierDown(KeyCode.capsLock)
        _ = h.modifierUp(leftShift)   // released late, while Caps is still down
        _ = h.modifierUp(KeyCode.capsLock)
        expect(h.synthesized == [KeyCode.escape],
               "releasing an unrelated modifier still leaves the tap a tap")

        // A modifier going *down* must still promote, or every shortcut would
        // also fire the tap key.
        let chord = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        _ = chord.modifierDown(KeyCode.capsLock)
        _ = chord.modifierDown(leftShift)
        _ = chord.modifierUp(leftShift)
        _ = chord.modifierUp(KeyCode.capsLock)
        expect(chord.synthesized.isEmpty, "a modifier pressed afterwards still means hold")
    }

    /// Bound keys never reached the promotion path, so holding one and tapping
    /// another resolved both as taps: on the JIS default that produced 英数 and
    /// かな together from a single intended chord.
    private static func oneBoundKeyHeldWhileAnotherIsTapped() {
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.kana, tapKeyCode: KeyCode.kana, hold: .hyper),
            KeyBinding(keyCode: KeyCode.eisu, tapKeyCode: KeyCode.eisu, hold: .control),
        ]))
        _ = h.keyDown(KeyCode.kana)
        _ = h.keyDown(KeyCode.eisu)
        _ = h.keyUp(KeyCode.eisu)
        _ = h.keyUp(KeyCode.kana)
        expect(h.synthesized == [KeyCode.eisu], "the held key does not also fire its tap")
    }

    /// Recording used to borrow the pause mode, which passes events through, so
    /// the key pressed to configure a field also reached the app behind: binding
    /// Return pressed the window's default button.
    private static func recordingSwallowsInsteadOfPassingThrough(_ unused: Void = ()) {
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        h.engine.isRecording = true
        expect(h.keyDown(KeyCode.returnKey) == .swallowed,
               "while recording, an unbound key does not reach the app")
        expect(h.modifierDown(KeyCode.capsLock) == .swallowed, "nor does a bound one")
        expect(h.synthesized.isEmpty, "and nothing is emitted")

        h.engine.isRecording = false
        _ = h.keyDown(KeyCode.returnKey)
        expect(h.lastFlags.isEmpty, "afterwards keys flow normally again")
    }

    /// Caps Lock reports two bits and only one of them follows the key: the lock
    /// bit is still set on the way up, so reading that as "still down" left the
    /// hold modifier applied to everything typed afterwards.
    private static func capsLockIsTrackedByTheKeyNotTheLock() {
        let lock: UInt64 = 0x0001_0000
        let down: UInt64 = 0x0000_0080
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        _ = h.flagsEvent(KeyCode.capsLock, raw: down | lock)
        _ = h.flagsEvent(KeyCode.capsLock, raw: lock)  // up, lock still on
        expect(h.synthesized == [KeyCode.escape], "the tap resolves while the lock bit lingers")

        _ = h.flagsEvent(KeyCode.capsLock, raw: down | lock)
        _ = h.keyDown(0x00)
        expect(h.lastFlags == .maskControl, "holding it adds its modifier")
        _ = h.flagsEvent(KeyCode.capsLock, raw: lock)
        _ = h.keyDown(0x01)
        expect(h.lastFlags.isEmpty, "and releasing it takes the modifier away")
    }

    /// Anything that clears state mid-chord - sleep, a re-arm, a config reload,
    /// arming a recording - used to leave the key's own release looking like a
    /// fresh press, which armed it again and stuck its modifier on every
    /// keystroke that followed.
    private static func aResetMidChordDoesNotStrandAModifier() {
        let down: UInt64 = 0x0000_0080
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        _ = h.flagsEvent(KeyCode.capsLock, raw: down)
        h.engine.reset()                               // as sleep or a reload does
        _ = h.flagsEvent(KeyCode.capsLock, raw: 0)     // the release still arrives

        _ = h.keyDown(0x00)
        expect(h.lastFlags.isEmpty, "no modifier is left applied after a reset")
        expect(h.synthesized.isEmpty, "and no phantom tap is emitted")
    }

    /// Recording clears state too, and disarms before the release arrives.
    private static func recordingAKeyDoesNotStrandItsModifier() {
        let down: UInt64 = 0x0000_0080
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        h.engine.isRecording = true
        _ = h.flagsEvent(KeyCode.capsLock, raw: down)  // swallowed by recording
        h.engine.isRecording = false                   // record() disarms here
        _ = h.flagsEvent(KeyCode.capsLock, raw: 0)     // release arrives after

        _ = h.keyDown(0x00)
        expect(h.lastFlags.isEmpty, "recording a bound key leaves no stuck modifier")
    }

    /// A modifier's own flagsChanged must not carry someone else's hold, because
    /// the bound key's release is swallowed and never retracts it.
    private static func holdFlagsStayOffModifierEvents() {
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: nil, hold: .control)
        ]))
        let leftShift: Int64 = 0x38
        _ = h.flagsEvent(KeyCode.capsLock, raw: 0x0000_0080)
        _ = h.modifierDown(leftShift)
        expect(h.lastFlags.isEmpty, "a real modifier's event is left alone")
        _ = h.keyDown(0x00)
        expect(h.lastFlags == .maskControl, "while key events still get the hold")
    }

    /// A key already held down repeats; that is not a new press, so it must not
    /// turn a waiting key into a hold.
    private static func autorepeatOfAnotherKeyDoesNotForceAHold() {
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)
        ]))
        _ = h.keyDown(0x33)                       // Delete, held down
        _ = h.flagsEvent(KeyCode.capsLock, raw: 0x0000_0080)
        _ = h.keyDown(0x33, autorepeat: true)     // still the same press
        _ = h.flagsEvent(KeyCode.capsLock, raw: 0)
        expect(h.synthesized == [KeyCode.escape], "a repeat elsewhere leaves the tap a tap")
    }

    /// A passed-through key delivers its own repeats, so firing the tap as well
    /// on release gave you both the characters and the tap key.
    private static func aPassedThroughKeyThatRepeatedIsAHold() {
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: KeyCode.space, tapKeyCode: KeyCode.eisu, hold: .unchanged)
        ]))
        _ = h.keyDown(KeyCode.space)
        _ = h.keyDown(KeyCode.space, autorepeat: true)
        _ = h.keyUp(KeyCode.space)
        expect(h.synthesized.isEmpty, "a key that repeated does not also emit its tap")
    }

    /// Command-click is the case this exists for: with Command bound to tap Eisu,
    /// a click that the engine could not see left the key looking untouched, so
    /// releasing it switched the input source.
    private static func clickingWhileAKeyIsHeldIsNotATap() {
        let leftCommand: Int64 = 0x37
        let h = Harness(Config(bindings: [
            KeyBinding(keyCode: leftCommand, tapKeyCode: KeyCode.eisu, hold: .unchanged)
        ]))
        _ = h.modifierDown(leftCommand)
        expect(h.mouseDown() == .passed, "the click itself is untouched")
        _ = h.modifierUp(leftCommand)
        expect(h.synthesized.isEmpty, "and Command-click does not switch input source")
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

        /// A left click, which the engine watches but never alters.
        func mouseDown() -> Outcome {
            let event = CGEvent(
                mouseEventSource: nil, mouseType: .leftMouseDown,
                mouseCursorPosition: .zero, mouseButton: .left)!
            lastFlags = CGEventFlags()
            guard engine.handle(type: .leftMouseDown, event: event) != nil else {
                return .swallowed
            }
            return .passed
        }

        /// A `flagsChanged` with exactly the bits given, for keys whose reporting
        /// is the thing under test.
        func flagsEvent(_ code: Int64, raw: UInt64) -> Outcome {
            send(code, type: .flagsChanged, autorepeat: false,
                 flags: CGEventFlags(rawValue: raw))
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
