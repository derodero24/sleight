import AppKit
import Foundation

let args = Set(CommandLine.arguments.dropFirst())

if args.contains("--help") || args.contains("-h") {
    print("""
    sleight - tap/hold key remapper for macOS (no driver, no system extension)

      sleight            run with a menu bar item
      sleight --sniff    print the key code of every key you press, then quit
                         with ⌃C. Use this to find the code for any key.
      sleight --selftest run the state-machine checks (no permissions needed)
      sleight --verbose  log every tap/hold decision (use this in bug reports)
      sleight --no-menu  run headless, without the menu bar item
      sleight --help     this text
    """)
    exit(0)
}

if args.contains("--selftest") {
    exit(SelfTest.run())
}

let sniffMode = args.contains("--sniff")

// Headless modes stay on a bare run loop so they work over SSH and under a
// process supervisor. The menu bar mode hands off to AppKit, which also has to
// own startup: exiting before AppKit finishes launching looks to Launch Services
// like an app that stopped responding.
guard sniffMode || args.contains("--no-menu") else {
    let app = NSApplication.shared
    let delegate = AppDelegate(args: args)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    exit(0)
}

if !sniffMode && !SingleInstance.claim() {
    exit(1)
}

// Sniffing only reads events, which needs Input Monitoring rather than
// Accessibility; remapping needs Accessibility because it rewrites them.
if !ensureAccessibilityPermission(prompt: true) {
    Log.warn("""
        Accessibility permission not granted yet.
        System Settings -> Privacy & Security -> Accessibility, then enable this app.
        Waiting for it to be granted...
        """)
    while !ensureAccessibilityPermission(prompt: false) {
        Thread.sleep(forTimeInterval: 1)
    }
    Log.info("permission granted")
}

let config = Config.load()
config.writeIfAbsent()

let engine = TapHoldEngine(config: config, verbose: args.contains("--verbose"))
let controller = EventTapController(engine: engine, sniffMode: sniffMode)

guard controller.start() else {
    Log.warn("could not create the event tap - is Accessibility permission enabled?")
    exit(1)
}

if sniffMode {
    print("Press keys to see their codes. ⌃C to quit.\n")
} else {
    Log.info("keyboard layout: \(KeyboardLayout.detect().rawValue)")
    Log.info("running with \(config.bindings.count) binding(s):")
    for line in engine.boundKeyDescriptions { Log.info("  \(line)") }
}

CFRunLoopRun()
