import CoreGraphics
import Foundation

/// Virtual key codes. Values come from Carbon's <HIToolbox/Events.h>.
///
/// Nothing here is layout-specific by design: a binding is just a key code, and
/// `--sniff` reports the code for whatever you actually pressed. The named
/// constants exist so the built-in defaults can be readable, not to limit what
/// can be bound.
enum KeyCode {
    static let capsLock: Int64 = 0x39
    static let escape: Int64 = 0x35
    static let tab: Int64 = 0x30
    static let space: Int64 = 0x31
    static let returnKey: Int64 = 0x24
    static let rightCommand: Int64 = 0x36
    static let rightOption: Int64 = 0x3D

    /// Present only on JIS keyboards, either side of the space bar. On a Windows
    /// JIS keyboard macOS usually maps muhenkan -> eisu and henkan -> kana, but
    /// "usually" does a lot of work there, which is another reason `--sniff` exists.
    static let eisu: Int64 = 0x66
    static let kana: Int64 = 0x68

    /// Names for the sniffer. Deliberately partial - anything unlisted is reported
    /// by number, which is all the sniffer needs to be useful.
    static let names: [Int64: String] = [
        0x66: "Eisu (JIS)",
        0x68: "Kana (JIS)",
        0x5D: "Yen (JIS)",
        0x5E: "Underscore (JIS)",
        0x5F: "Keypad Comma (JIS)",
        0x39: "Caps Lock",
        0x35: "Escape",
        0x30: "Tab",
        0x31: "Space",
        0x24: "Return",
        0x33: "Delete",
        0x36: "Right Command",
        0x37: "Left Command",
        0x38: "Left Shift",
        0x3A: "Left Option",
        0x3B: "Left Control",
        0x3C: "Right Shift",
        0x3D: "Right Option",
        0x3E: "Right Control",
        0x3F: "Fn / Globe",
    ]

    static func describe(_ code: Int64) -> String {
        names[code] ?? "keycode \(code)"
    }

    /// Short forms for the settings list, where a truncated label is worse than a
    /// terse one. Modifier symbols carry more at a glance than the words do, and
    /// they are the same symbols the rest of macOS uses.
    ///
    /// Looked up rather than returned directly: these appear next to the menu that
    /// sets them, and a field reading "Eisu" beside a menu item reading 英数 looks
    /// like two different keys.
    static let shortNameKeys: [Int64: String] = [
        0x66: "key.eisu",
        0x68: "key.kana",
        0x5D: "key.yen",
        0x39: "key.capsLock",
        0x35: "key.escape",
        0x33: "key.delete",
        0x30: "key.tab",
        0x31: "key.space",
        0x24: "key.return",
        0x36: "key.rightCommand",
        0x37: "key.leftCommand",
        0x38: "key.leftShift",
        0x3A: "key.leftOption",
        0x3B: "key.leftControl",
        0x3C: "key.rightShift",
        0x3D: "key.rightOption",
        0x3E: "key.rightControl",
        0x3F: "key.function",
    ]

    static func shortName(_ code: Int64) -> String {
        if let key = shortNameKeys[code] { return L(key) }
        return names[code] ?? "Key \(code)"
    }

    /// Keys worth offering as a list rather than asking someone to press.
    ///
    /// Eisu and Kana are why this list exists at all: they live on JIS keyboards,
    /// and the point of binding them from an ANSI board is that you do not have
    /// them, so "press a key" cannot capture them. They come second because most
    /// people reaching for this menu want Escape, and a section they cannot read
    /// sitting at the top is a worse first impression than one they can.
    ///
    /// These two are the whole of it. macOS has no other input-source key codes;
    /// Korean uses the same pair, and the remaining JIS-only keys are ordinary
    /// characters rather than switches.
    static let presets: [(section: String, codes: [Int64])] = [
        ("preset.common", [escape, tab, space, returnKey, 0x33]),
        ("preset.inputSource", [eisu, kana]),
    ]

    /// What a binding's source key can be, offered as a list.
    ///
    /// Recording is the natural way to pick these, but it cannot be the only way.
    /// Escape stops a recording, so recording could never capture Escape itself,
    /// and Caps Lock is awkward to press on purpose. A list costs nothing and
    /// removes both problems.
    static let sourcePresets: [(section: String, codes: [Int64])] = [
        ("preset.modifiers", [0x39, 0x37, 0x36, 0x3A, 0x3D, 0x3B, 0x3E, 0x38, 0x3C]),
        ("preset.common", [escape, tab, space, returnKey, 0x33]),
        ("preset.inputSource", [eisu, kana]),
    ]

    /// Modifier keys arrive as `flagsChanged`, not `keyDown`/`keyUp`, so press and
    /// release have to be told apart by looking at the bit the key owns.
    ///
    /// Left and right modifiers share the public masks (both Shifts set
    /// `maskShift`), so these are the device-dependent bits from IOKit's
    /// `NX_DEVICE*KEYMASK` set - the only way to know *which* Shift moved.
    static let modifierBits: [Int64: UInt64] = [
        0x3B: 0x0000_0001,  // Left Control
        0x38: 0x0000_0002,  // Left Shift
        0x3C: 0x0000_0004,  // Right Shift
        0x37: 0x0000_0008,  // Left Command
        0x36: 0x0000_0010,  // Right Command
        0x3A: 0x0000_0020,  // Left Option
        0x3D: 0x0000_0040,  // Right Option
        0x3E: 0x0000_2000,  // Right Control
        0x39: 0x0001_0000,  // Caps Lock (maskAlphaShift)
        0x3F: 0x0080_0000,  // Fn / Globe (NX_SECONDARYFNMASK)
    ]

    static func isModifier(_ code: Int64) -> Bool { modifierBits[code] != nil }

    /// Keys that only ever arrive as `flagsChanged`. Binding one that is not in
    /// `modifierBits` would swallow it for ever, so these are worth naming.
    static func reportsAsFlagsOnly(_ code: Int64) -> Bool {
        (0x36...0x3F).contains(code)
    }

    /// True when this `flagsChanged` event is the key going down.
    static func isPress(code: Int64, flags: CGEventFlags) -> Bool {
        guard let bit = modifierBits[code] else { return false }
        return flags.rawValue & bit != 0
    }
}

extension CGEventFlags {
    /// Just the modifier bits, rendered the way a menu would show them.
    var modifierSymbols: String {
        var symbols = ""
        if contains(.maskControl) { symbols += "⌃" }
        if contains(.maskAlternate) { symbols += "⌥" }
        if contains(.maskShift) { symbols += "⇧" }
        if contains(.maskCommand) { symbols += "⌘" }
        return symbols.isEmpty ? "(none)" : symbols
    }
}

/// What the `hold` half of a key can turn into.
enum HoldBehavior: String, Codable, CaseIterable {
    /// Leave the key alone and only add the tap.
    ///
    /// This is what makes a Command key usable as a tap target. Swallowing a
    /// modifier and re-applying its flag to following events covers ordinary
    /// shortcuts, but not anything that watches the modifier itself: holding
    /// Command to keep the app switcher open, Command-dragging in Finder. Passing
    /// the real event through keeps all of that, and a bare modifier press does
    /// nothing on its own, so there is nothing to suppress.
    case unchanged

    case control
    case option
    case command
    case shift
    /// ⌃⌥⌘⇧ all at once - the "hyper" key everyone builds shortcuts on top of.
    case hyper

    var flags: CGEventFlags {
        switch self {
        case .unchanged: return []
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        case .shift: return .maskShift
        case .hyper: return [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        }
    }

    /// Shown in the settings picker, with the symbol people actually recognise.
    var title: String { L("hold.\(rawValue)") }
}
