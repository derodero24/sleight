import CoreGraphics
import Foundation

/// One physical key given two jobs.
struct KeyBinding: Codable {
    /// The key being reassigned, e.g. 0x39 for Caps Lock. Use `--sniff` to find it.
    var keyCode: Int64
    /// What a quick press emits. Omit to make the key hold-only.
    var tapKeyCode: Int64?
    /// What holding it turns the key into. Omit to make the key tap-only.
    var hold: HoldBehavior?

    /// A binding with neither half does nothing but swallow the key, which is the
    /// worst outcome this app has: the key stops working and nothing says why.
    /// The settings window cannot produce one, but a hand-edited file can.
    var isUsable: Bool { tapKeyCode != nil || hold != nil }

    /// Only the halves that are actually configured, so a hold-only key does not
    /// advertise a tap that does nothing.
    var label: String {
        var parts: [String] = []
        if let tapKeyCode { parts.append("tap -> \(KeyCode.describe(tapKeyCode))") }
        if let hold { parts.append("hold -> \(hold.rawValue)") }
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
    ///
    /// JSON decoding is all or nothing, so one bad value discards the whole file.
    /// The original is moved aside first, because the settings window then opens
    /// showing defaults and the next Save would otherwise overwrite hand-written
    /// bindings that were only one typo away from working.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return .default }
        do {
            return try JSONDecoder().decode(Config.self, from: data).validated()
        } catch {
            Log.warn("config at \(url.path) is unreadable: \(error)")
            let backup = url.appendingPathExtension("invalid")
            try? FileManager.default.removeItem(at: backup)
            do {
                try FileManager.default.moveItem(at: url, to: backup)
                Log.warn("kept a copy at \(backup.path); using defaults")
            } catch {
                Log.warn("could not preserve it (\(error)); using defaults")
            }
            return .default
        }
    }

    /// Drops bindings that would crash or silently break the keyboard.
    ///
    /// A key code out of `CGKeyCode` range is the sharp one: converting it traps,
    /// so a mistyped number used to kill the process the moment that key was
    /// tapped, leaving no menu bar item and no explanation.
    private func validated() -> Config {
        let range = Int64(CGKeyCode.min)...Int64(CGKeyCode.max)
        return Config(bindings: bindings.filter { binding in
            guard range.contains(binding.keyCode) else {
                Log.warn("ignoring binding: key code \(binding.keyCode) is out of range")
                return false
            }
            if let tap = binding.tapKeyCode, !range.contains(tap) {
                Log.warn("ignoring binding for \(KeyCode.describe(binding.keyCode)): "
                    + "tap key code \(tap) is out of range")
                return false
            }
            return true
        })
    }

    /// Atomic, so a crash or a full disk cannot leave a half-written file behind -
    /// which would decode as corrupt on the next launch and lose everything.
    func write() throws {
        let url = Config.url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
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

    private static let sizeLimit = 512 * 1024

    /// Opened with O_APPEND, and trimmed in place rather than replaced.
    ///
    /// `createFile` allocates a new inode, which leaves any other process that
    /// already has the log open writing into a file nobody can find. That is not
    /// hypothetical: a second launch logs "already running" before it exits, and
    /// doing so would have orphaned the log of the instance doing the work.
    /// O_APPEND also makes interleaved writes from two processes safe.
    private static let descriptor: Int32? = {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        return fd >= 0 ? fd : nil
    }()

    /// Keeps the file bounded during a session, not just at launch. Verbose mode
    /// writes several lines per keystroke, so a check that only ran once would let
    /// a long-lived menu bar process grow the log without limit.
    private static func trimIfHuge(_ fd: Int32) {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > sizeLimit else { return }
        ftruncate(fd, 0)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Silences the log. The self-test deliberately builds broken configs, and
    /// their warnings were landing in the file users are told to read for bug
    /// reports, where they look like real faults.
    static var isQuiet = false

    private static func emit(_ level: String, _ message: String) {
        guard !isQuiet else { return }
        let line = "[\(formatter.string(from: Date()))] \(level) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))

        guard let fd = descriptor else { return }
        trimIfHuge(fd)
        // write(2) rather than FileHandle.write, which raises an uncatchable
        // exception when the disk is full. Losing a log line is not worth a crash.
        _ = line.withCString { pointer in
            Darwin.write(fd, pointer, strlen(pointer))
        }
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
