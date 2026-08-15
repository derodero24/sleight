import SwiftUI

/// The whole interface: one list of keys, two things each key can do.
///
/// Laid out the way current macOS settings are - a raised, bordered container
/// holding the list, sitting on the plain window background, with the actions
/// along the bottom. The two tones are what give the window depth; a single flat
/// fill is what made the earlier version read as a black rectangle.
///
/// Every colour here is a system semantic colour, so light and dark are both
/// handled by the system rather than by values picked against one of them.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var onRevert: () -> Void = {}
    var onSave: () -> Void = {}

    fileprivate static let keyWidth: CGFloat = 112
    fileprivate static let tapWidth: CGFloat = 112
    fileprivate static let holdWidth: CGFloat = 152

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            list
            addButton
            Spacer(minLength: 0)
            Divider()
            actions
        }
        // Fixed rather than sized to content: a window that grows and shrinks as
        // keys are added moves its own buttons around under the pointer.
        .frame(width: 520, height: 380)
    }

    // MARK: - Sections

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Keys")
                .font(.system(size: 15, weight: .semibold))
            Text("Tap sends a key. Hold turns it into a modifier.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var list: some View {
        VStack(spacing: 0) {
            columnHeadings
            Divider()
            ScrollView {
                if store.bindings.isEmpty {
                    empty
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array($store.bindings.enumerated()), id: \.element.id) {
                            index, $binding in
                            if index > 0 { Divider().padding(.leading, 14) }
                            BindingRow(binding: $binding, store: store)
                        }
                    }
                }
            }
        }
        .frame(height: 214)
        // textBackgroundColor is the right semantic base for a list, but measured
        // in isolation it is the same value as windowBackgroundColor in both
        // appearances - the separation you see comes from the window's material,
        // which is not something to rely on. The tint puts a real difference
        // there, and the border guarantees the edge even if both were to match.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5))))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .padding(.horizontal, 24)
    }

    private var columnHeadings: some View {
        HStack(spacing: 10) {
            Text("KEY").frame(width: Self.keyWidth, alignment: .leading)
            Text("TAP").frame(width: Self.tapWidth, alignment: .leading)
            Text("HOLD").frame(width: Self.holdWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Text("No keys yet")
                .font(.system(size: 13, weight: .medium))
            Text("Add one, then click its key field and press a key.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 46)
    }

    private var addButton: some View {
        Button {
            store.add()
        } label: {
            Label("Add Key", systemImage: "plus.circle")
        }
        .buttonStyle(.link)
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if store.recording != nil {
                Label("Press a key, or Escape to cancel", systemImage: "record.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if store.hasChanges {
                Text("Not saved yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Neither closes the window. Undoing a mistake and then making a
            // different change is the common case, and having to reopen the
            // window in between made that tedious.
            Button("Revert", action: onRevert)
                .disabled(!store.hasChanges)
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(!store.hasChanges)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

/// One key and what it does.
private struct BindingRow: View {
    @Binding var binding: EditableBinding
    @ObservedObject var store: SettingsStore
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            KeyChooser(
                keyCode: $binding.keyCode,
                presets: KeyCode.sourcePresets,
                placeholder: L("field.setKey"),
                allowsNone: false,
                isRecording: store.recording == .key(binding.id),
                width: SettingsView.keyWidth
            ) {
                // Clicking the armed field again backs out, the same as Escape.
                store.recording = store.recording == .key(binding.id)
                    ? nil : .key(binding.id)
            }

            KeyChooser(
                keyCode: $binding.tapKeyCode,
                presets: KeyCode.presets,
                placeholder: L("None"),
                allowsNone: true,
                isRecording: store.recording == .tap(binding.id),
                width: SettingsView.tapWidth
            ) {
                store.recording = store.recording == .tap(binding.id)
                    ? nil : .tap(binding.id)
            }

            Picker("", selection: $binding.hold) {
                Text("None").tag(HoldBehavior?.none)
                ForEach(HoldBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.title).tag(HoldBehavior?.some(behavior))
                }
            }
            .labelsHidden()
            .frame(width: SettingsView.holdWidth)

            Spacer(minLength: 0)

            // Always visible, and red. Hiding it until hover made it something to
            // hunt for, and grey gave no clue what it did.
            Button {
                store.remove(binding.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
            .buttonStyle(.plain)
            .help("Remove this key")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
    }
}

/// Picks a key: a menu of useful ones, plus the option to press one.
///
/// A menu rather than recording alone because the keys people most want are often
/// ones they cannot press. Binding Command to Eisu on an ANSI keyboard is the
/// app's headline use and an ANSI keyboard has no Eisu key; Escape stops a
/// recording so recording could never capture it; Caps Lock is awkward to press
/// on purpose. The list costs nothing and removes all three problems.
private struct KeyChooser: View {
    @Binding var keyCode: Int64?
    let presets: [(section: String, codes: [Int64])]
    let placeholder: String
    let allowsNone: Bool
    let isRecording: Bool
    let width: CGFloat
    let onRecord: () -> Void

    var body: some View {
        Menu {
            Button(L(isRecording ? "field.stopWaiting" : "field.pressKey"), action: onRecord)
            Divider()
            ForEach(presets, id: \.section) { preset in
                Section(L(preset.section)) {
                    ForEach(preset.codes, id: \.self) { code in
                        Button(KeyCode.shortName(code)) { keyCode = code }
                    }
                }
            }
            if allowsNone {
                Divider()
                Button(L("None")) { keyCode = nil }
            }
        } label: {
            Text(label)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(keyCode == nil && !isRecording ? .tertiary : .primary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: width)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isRecording ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                  : AnyShapeStyle(.quaternary)))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: 1))
    }

    private var label: String {
        if isRecording { return L("field.pressAKey") }
        return keyCode.map(KeyCode.shortName) ?? placeholder
    }
}
