import Carbon
import Foundation

/// Which physical keyboard is attached. This only decides what the *starter*
/// config looks like - bindings themselves are plain key codes and work on any
/// layout once written.
enum KeyboardLayout: String {
    case ansi
    case iso
    case jis

    static func detect() -> KeyboardLayout {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardJIS: return .jis
        case kKeyboardISO: return .iso
        default: return .ansi
        }
    }

    /// Sensible bindings for a keyboard nobody has configured yet.
    ///
    /// ANSI and ISO get Caps Lock, which is the most-remapped key on any keyboard
    /// and does nothing useful as shipped. JIS additionally gets the two keys
    /// either side of the space bar, which sit under your thumbs doing nothing at
    /// all unless you use a Japanese input method.
    var defaultBindings: [KeyBinding] {
        let capsLock = KeyBinding(
            keyCode: KeyCode.capsLock, tapKeyCode: KeyCode.escape, hold: .control)

        switch self {
        case .ansi:
            return [
                capsLock,
                KeyBinding(keyCode: KeyCode.rightOption, tapKeyCode: nil, hold: .hyper),
            ]
        case .iso:
            // No Right Option here. macOS has no separate AltGr, so on European
            // layouts the right Option key is how you type @ \ { } [ ] | ~ EUR,
            // and taking it for a hyper key would break that on first run.
            return [capsLock]
        case .jis:
            return [
                capsLock,
                KeyBinding(keyCode: KeyCode.kana, tapKeyCode: KeyCode.kana, hold: .hyper),
                KeyBinding(keyCode: KeyCode.eisu, tapKeyCode: KeyCode.eisu, hold: .control),
            ]
        }
    }
}
