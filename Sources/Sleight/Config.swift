import Foundation

/// One physical key given two jobs.
struct KeyBinding: Codable {
    /// The key being reassigned, e.g. 0x39 for Caps Lock. Use `--sniff` to find it.
    var keyCode: Int64
    /// What a quick press emits. Omit to make the key hold-only.
    var tapKeyCode: Int64?
    /// What holding it turns the key into. Omit to make the key tap-only.
    var hold: HoldBehavior?

    /// Only the halves that are actually configured, so a hold-only key does not
    /// advertise a tap that does nothing.
    var label: String {
        var parts: [String] = []
        if let tapKeyCode { parts.append("tap -> \(KeyCode.describe(tapKeyCode))") }
        if let hold { parts.append("hold -> \(hold.rawValue)") }
        if parts.isEmpty { parts.append("nothing bound") }
        return "\(KeyCode.describe(keyCode)): \(parts.joined(separator: ", "))"
    }
}

struct Config: Codable {
    var bindings: [KeyBinding]

    /// Chosen from the attached keyboard so that a first run does something
    /// useful rather than nothing.
    static var `default`: Config {
        Config(bindings: KeyboardLayout.detect().defaultBindings)
    }

    static var url: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sleight", isDirectory: true)
        return base.appendingPathComponent("config.json")
    }

    /// Falls back to the default rather than failing: a config typo should not
    /// leave the user with a keyboard that does nothing.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return .default }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.warn("config at \(url.path) is unreadable (\(error)); using defaults")
            return .default
        }
    }

    func write() throws {
        let url = Config.url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    func writeIfAbsent() {
        guard !FileManager.default.fileExists(atPath: Config.url.path) else { return }
        do {
            try write()
            Log.info("wrote starter config to \(Config.url.path)")
        } catch {
            Log.warn("could not write config: \(error)")
        }
    }
}

/// Writes to stderr and to a file.
///
/// An app with no window, no Dock icon and no console has nowhere to say what
/// went wrong, and stderr goes nowhere when Launch Services starts it. The file
/// is the only account of a session that anyone can actually read afterwards.
enum Log {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Sleight.log")

    private static let handle: FileHandle? = {
        let url = fileURL
        let manager = FileManager.default
        try? manager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Appending, not truncating. A launch that finds the app already running
        // is still a process that writes here, and truncating on open meant that
        // second process wiped the log of the instance actually doing the work.
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if !manager.fileExists(atPath: url.path) || (size ?? 0) > 512 * 1024 {
            manager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        try? handle?.seekToEnd()
        return handle
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func emit(_ level: String, _ message: String) {
        let line = Data("[\(formatter.string(from: Date()))] \(level) \(message)\n".utf8)
        FileHandle.standardError.write(line)
        handle?.write(line)
    }

    static func info(_ message: String) { emit("INFO ", message) }
    static func warn(_ message: String) { emit("WARN ", message) }

    /// Marks where one run ends and the next begins, since the file is shared.
    static func session() {
        emit("---- ", "pid \(ProcessInfo.processInfo.processIdentifier) started")
    }
}

/// Shorthand for a localized string. AppKit has no equivalent of SwiftUI's
/// automatic lookup, so menu titles have to ask for it explicitly.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
