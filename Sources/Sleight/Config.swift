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

enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func emit(_ level: String, _ message: String) {
        FileHandle.standardError.write(
            Data("[\(formatter.string(from: Date()))] \(level) \(message)\n".utf8))
    }

    static func info(_ message: String) { emit("INFO ", message) }
    static func warn(_ message: String) { emit("WARN ", message) }
}
