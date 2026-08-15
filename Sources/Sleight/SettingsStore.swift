import Combine
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
/// Edits apply as you make them. There is no Save button because there is nothing
/// a Save button would protect you from: the effect of a binding is immediate and
/// obvious, and getting it wrong is undone by changing it back.
final class SettingsStore: ObservableObject {
    @Published var bindings: [EditableBinding]

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
    private var cancellable: AnyCancellable?

    init(config: Config, controller: EventTapController?) {
        self.bindings = config.bindings.map(EditableBinding.init)
        self.controller = controller

        // Coalesced so that holding down a stepper or retyping does not rebuild
        // the engine on every keystroke.
        cancellable = $bindings
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
    }

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

    /// Writes to disk and swaps the engine. Failing to write is worth saying out
    /// loud, since the alternative is settings that quietly vanish on restart.
    private func apply() {
        let config = self.config
        do {
            try config.write()
        } catch {
            Log.warn("could not save settings: \(error.localizedDescription)")
        }
        controller?.reload(with: TapHoldEngine(config: config))
    }
}
