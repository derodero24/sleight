import Foundation

/// One physical key given two jobs.
struct Binding: Codable {
    /// The key being reassigned, e.g. 0x39 for Caps Lock. Use `--sniff` to find it.
    var keyCode: Int64
    /// What a quick press emits. Omit to make the key hold-only.
    var tapKeyCode: Int64?
    /// What holding it turns the key into. Omit to make the key tap-only.
    var hold: HoldBehavior?

    var label: String {
        let tap = tapKeyCode.map(KeyCode.describe) ?? "-"
        let hold = self.hold?.rawValue ?? "-"
        return "\(KeyCode.describe(keyCode)): tap -> \(tap) / hold -> \(hold)"
    }
}

struct Config: Codable {
    var bindings: [Binding]

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

    func writeIfAbsent() {
        let url = Config.url
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: url)
            Log.info("wrote starter config to \(url.path)")
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
