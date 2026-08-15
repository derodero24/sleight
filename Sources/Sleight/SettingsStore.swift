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
    /// Published even though it is private: `hasChanges` is derived from it, and
    /// saving changes only this. Without the announcement the buttons stayed
    /// enabled and the window went on claiming the settings were unsaved.
    @Published private var snapshot: [EditableBinding] = []

    /// While recording, the engine is paused so the key being captured does not
    /// trigger whatever it is currently bound to. This is also why capture reads
    /// from the event tap rather than from a text field: Caps Lock and the
    /// modifiers never produce a key press a view could receive.
    @Published var recording: RecordTarget? {
        didSet { controller?.isPaused = recording != nil || pausedByUser }
    }

    /// Kept apart from the recording pause so that finishing a recording does not
    /// silently resume an app the user had deliberately paused.
    var pausedByUser = false {
        didSet { controller?.isPaused = recording != nil || pausedByUser }
    }

    private weak var controller: EventTapController?

    init(config: Config, controller: EventTapController?) {
        self.bindings = config.bindings.map(EditableBinding.init)
        self.controller = controller
    }

    /// True once the list differs from what the window opened with. Drives whether
    /// Done is worth pressing.
    var hasChanges: Bool { bindings != snapshot }

    var config: Config {
        Config(bindings: bindings.compactMap(\.saved))
    }

    func add() {
        bindings.append(EditableBinding())
    }

    func remove(_ id: UUID) {
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
            Log.warn("could not save settings: \(error.localizedDescription)")
        }
        controller?.reload(with: TapHoldEngine(config: config))
        snapshot = bindings
        Log.info("settings saved (\(config.bindings.count) key(s))")
    }

    /// Throws the edits away. The engine never saw them, so there is nothing to
    /// undo beyond the list itself.
    func cancel() {
        guard hasChanges else { return }
        bindings = snapshot
        Log.info("settings discarded")
    }
}
