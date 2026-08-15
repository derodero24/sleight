import AppKit

/// Refuses to start when a copy is already running.
///
/// Two instances means two event taps competing over the same keys, which shows
/// up as duplicated characters and modifiers that will not release. It is also
/// easy to do by accident, since the app has no window to tell you it is there.
enum SingleInstance {
    /// Sent by a duplicate launch so the copy already running can show itself.
    static let showSettings = Notification.Name("dev.sleight.Sleight.showSettings")

    static func claim() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else {
            // Running as a loose binary rather than a bundle, so there is nothing
            // reliable to match on. Let it through.
            return true
        }

        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != mine }

        guard others.isEmpty else {
            // Opening an app that is already running should show it, not do
            // nothing. Silence here reads as a failed launch, or worse as the old
            // version having stayed put.
            Log.warn("already running (pid \(others[0].processIdentifier)); showing its settings")
            DistributedNotificationCenter.default().postNotificationName(
                showSettings, object: nil, userInfo: nil, deliverImmediately: true)
            return false
        }
        return true
    }
}
