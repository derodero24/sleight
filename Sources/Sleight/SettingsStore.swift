import Foundation

/// A binding while it is being edited, which is a looser thing than a saved one:
/// a half-filled row is a normal state to be in partway through adding a key.
struct EditableBinding: Identifiable, Equatable {
    let id = UUID()
    var keyCode: Int64?
    var tapKeyCode: Int64?
    var hold: HoldBehavior?

    /// Rows without a key, or with neither half configured, would do nothing.
    var isUsable: Bool {
        keyCode != nil && (tapKeyCode != nil || hold != nil)
    }

    init(keyCode: Int64? = nil, tapKeyCode: Int64? = nil, hold: HoldBehavior? = nil) {
        self.keyCode = keyCode
        self.tapKeyCode = tapKeyCode
        self.hold = hold
    }

    init(_ binding: KeyBinding) {
        self.init(keyCode: binding.keyCode, tapKeyCode: binding.tapKeyCode, hold: binding.hold)
    }

    var saved: KeyBinding? {
        guard let keyCode, isUsable else { return nil }
        return KeyBinding(keyCode: keyCode, tapKeyCode: tapKeyCode, hold: hold)
    }
}

/// Which field is waiting for a key press.
enum RecordTarget: Equatable {
    case key(UUID)
    case tap(UUID)
}

/// Owns the editable copy of the config and pushes changes to the live engine.
///
/// Nothing takes effect until Done. Applying edits as they were made read nicely
/// but meant a misclick on a picker silently changed how the keyboard behaved,
/// which is a bad trade for a window whose whole subject is what your keys do.
final class SettingsStore: ObservableObject {
    @Published var bindings: [EditableBinding]

    /// What Cancel goes back to. Taken when the window opens rather than at init,
    /// so each visit to the window is its own undoable unit.
    /// Published so that saving, which changes only this, redraws the buttons.
    @Published private var snapshot: [EditableBinding] = []

    /// While recording, the engine is paused so the key being captured does not
    /// trigger whatever it is currently bound to. This is also why capture reads
    /// from the event tap rather than from a text field: Caps Lock and the
    /// modifiers never produce a key press a view could receive.
    @Published var recording: RecordTarget? {
        didSet { controller?.isRecording = recording != nil }
    }

    /// Separate from recording, and mapped to a separate engine mode. Folding both
    /// into `isPaused` made the menu bar read "Paused" while a field was armed, so
    /// its Resume item toggled the *other* bit and left the app genuinely paused
    /// once the recording finished.
    var pausedByUser = false {
        didSet { controller?.isPaused = pausedByUser }
    }

    private weak var controller: EventTapController?
    /// Carried so that saving does not quietly turn --verbose back off.
    private let verbose: Bool

    init(config: Config, controller: EventTapController?, verbose: Bool = false) {
        self.bindings = config.bindings.map(EditableBinding.init)
        self.controller = controller
        self.verbose = verbose
    }

    /// True once the list differs from what the window opened with.
    var hasChanges: Bool { bindings != snapshot }

    var config: Config {
        Config(bindings: bindings.compactMap(\.saved))
    }

    /// Rows whose key is already claimed by an earlier row. Only the first one
    /// takes effect, so the later ones need to say so rather than sit there
    /// looking configured.
    /// Set when a save fails, so the window can say so instead of pretending.
    @Published var saveError: String?

    /// Rows that are started but not finished. Saving used to drop these silently
    /// while clearing the unsaved marker, so the row sat there looking configured
    /// and was gone at the next launch.
    var incompleteRows: Set<UUID> {
        Set(bindings.filter { !$0.isUsable }.map(\.id))
    }

    /// Every row that will not take effect, for whatever reason.
    var problemRows: Set<UUID> { incompleteRows.union(duplicateRows) }

    var duplicateRows: Set<UUID> {
        var seen: Set<Int64> = []
        var duplicates: Set<UUID> = []
        for binding in bindings {
            guard let code = binding.keyCode else { continue }
            if !seen.insert(code).inserted { duplicates.insert(binding.id) }
        }
        return duplicates
    }

    func add() {
        bindings.append(EditableBinding())
    }

    func remove(_ id: UUID) {
        if recording == .key(id) || recording == .tap(id) { recording = nil }
        bindings.removeAll { $0.id == id }
    }

    /// Called from the event tap for every key press while recording.
    func record(_ keyCode: Int64) {
        guard let target = recording else { return }

        // Escape backs out. Being armed and unable to stop is uncomfortable even
        // when nothing is saved yet, because there is no way to know that from
        // looking at it. The cost is that Escape cannot be recorded by pressing
        // it, which is why it is in the tap menu instead.
        if keyCode == KeyCode.escape {
            recording = nil
            Log.info("recording cancelled")
            return
        }

        switch target {
        case .key(let id):
            update(id) { $0.keyCode = keyCode }
        case .tap(let id):
            update(id) { $0.tapKeyCode = keyCode }
        }
        recording = nil
    }

    private func update(_ id: UUID, _ change: (inout EditableBinding) -> Void) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        change(&bindings[index])
    }

    // MARK: - Editing session

    func beginEditing() {
        snapshot = bindings
        // A stale error is worse than none: it sits first in the footer and hides
        // the recording prompt for the rest of the session.
        saveError = nil
    }

    /// The only path that changes anything: writes to disk and swaps the engine.
    /// Failing to write is worth saying out loud, since the alternative is
    /// settings that quietly vanish on restart.
    func commit() {
        guard hasChanges else { return }
        let config = self.config
        do {
            try config.write()
        } catch {
            // A log line is not "out loud" for an app with no console. Saying
            // nothing here meant the window cleared its unsaved marker and the
            // settings then vanished at the next launch.
            saveError = error.localizedDescription
            Log.warn("could not save settings: \(error.localizedDescription)")
            return
        }
        saveError = nil
        controller?.reload(with: TapHoldEngine(config: config, verbose: verbose))
        snapshot = bindings
        Log.info("settings saved (\(config.bindings.count) key(s))")  // after dedupe
    }

    /// Throws the edits away. The engine never saw them, so there is nothing to
    /// undo beyond the list itself.
    func cancel() {
        recording = nil
        saveError = nil
        guard hasChanges else { return }
        bindings = snapshot
        Log.info("settings discarded")
    }
}
