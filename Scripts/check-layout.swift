#!/usr/bin/env swift
// Measures every translated string against the control it has to fit in.
//
//     swift Scripts/check-layout.swift
//
// Translations are not the same length as the English they came from, and a
// string that overflows is silently truncated rather than reported. Japanese
// found this the hard way: "Press a key" fits a 112pt field, and the same
// sentence in Japanese is half as wide again.
//
// Run this after touching either the strings or the column widths.
import AppKit

/// Must match the constants in SettingsView.
let keyWidth: CGFloat = 112
let holdWidth: CGFloat = 152

/// A bordered menu spends its width on padding and a chevron before any text.
let menuChrome: CGFloat = 28
let pickerChrome: CGFloat = 34

let body = NSFont.systemFont(ofSize: 12)

/// Only strings drawn inside a fixed-width control are checked. Menu items and
/// section headers are not: a menu is as wide as its contents, so a long
/// translation there costs nothing.
func constraint(for key: String) -> CGFloat? {
    switch key {
    // Drawn in the key and tap fields.
    case "field.pressAKey", "field.setKey", "None":
        return keyWidth - menuChrome
    // Drawn in the hold picker.
    case _ where key.hasPrefix("hold."):
        return holdWidth - pickerChrome
    // Key names appear both in the fields and in menus; the field is the tighter.
    case _ where key.hasPrefix("key."):
        return keyWidth - menuChrome
    default:
        return nil
    }
}

// Derived from the script's own path, not the working directory. Resolving the
// repo by cwd meant running it from anywhere else measured nothing at all and
// still printed "everything fits" with exit 0 - a checker that cannot fail.
let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent().path
var failures = 0
var measured = 0

for lproj in (try? FileManager.default.contentsOfDirectory(atPath: "\(root)/Resources"))?
    .filter({ $0.hasSuffix(".lproj") }).sorted() ?? []
{
    let path = "\(root)/Resources/\(lproj)/Localizable.strings"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
    print("=== \(lproj) ===")

    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: ["\""])
        let value = parts[1].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: [";"]).trimmingCharacters(in: ["\""])
        guard let available = constraint(for: key) else { continue }
        measured += 1

        let width = (value as NSString).size(withAttributes: [.font: body]).width
        if width > available {
            print(String(format: "  OVERFLOW %@ = \"%@\"  %.0fpt > %.0fpt",
                         key, value, width, available))
            failures += 1
        }
    }
}

if measured == 0 {
    print("\nno strings were measured - is \(root)/Resources missing?")
    exit(1)
}
if failures == 0 {
    print("\n\(measured) string(s) measured, everything fits")
    exit(0)
}
print("\n\(failures) string(s) will be truncated")
exit(1)
