import SwiftUI

/// The whole interface. One list of keys, two things each key can do.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    /// What Cancel and Done report back to.
    var onCancel: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeadings
            Divider()
            rows
            Divider()
            footer
        }
        // Fixed rather than sized to content: a window that grows and shrinks as
        // keys are added moves its own buttons around under the pointer.
        .frame(width: 470, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var columnHeadings: some View {
        HStack(spacing: 10) {
            Text("KEY").frame(width: 150, alignment: .leading)
            Text("TAP").frame(width: 140, alignment: .leading)
            Text("HOLD").frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: 20)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var rows: some View {
        ScrollView {
            if store.bindings.isEmpty {
                Text("No keys yet. Add one below.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                VStack(spacing: 0) {
                    ForEach($store.bindings) { $binding in
                        BindingRow(binding: $binding, store: store)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                store.add()
            } label: {
                Label("Add Key", systemImage: "plus")
            }
            .buttonStyle(.link)

            if store.recording != nil {
                Text("Press any key")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// One key and what it does.
private struct BindingRow: View {
    @Binding var binding: EditableBinding
    @ObservedObject var store: SettingsStore

    var body: some View {
        HStack(spacing: 10) {
            KeyField(
                label: binding.keyCode.map(KeyCode.describe) ?? "Set key",
                isEmpty: binding.keyCode == nil,
                isRecording: store.recording == .key(binding.id),
                width: 150
            ) {
                store.recording = .key(binding.id)
            }

            KeyField(
                label: binding.tapKeyCode.map(KeyCode.describe) ?? "None",
                isEmpty: binding.tapKeyCode == nil,
                isRecording: store.recording == .tap(binding.id),
                width: 140
            ) {
                store.recording = .tap(binding.id)
            }
            .contextMenu {
                Button("Clear") { binding.tapKeyCode = nil }
            }

            Picker("", selection: $binding.hold) {
                Text("None").tag(HoldBehavior?.none)
                ForEach(HoldBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.title).tag(HoldBehavior?.some(behavior))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button {
                store.remove(binding.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .frame(width: 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// A button that becomes a key recorder when clicked.
private struct KeyField: View {
    let label: String
    let isEmpty: Bool
    let isRecording: Bool
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isRecording ? "Press a key" : label)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(foreground)
                .frame(width: width, height: 22, alignment: .leading)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isRecording
                            ? Color.accentColor.opacity(0.15)
                            : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var foreground: HierarchicalShapeStyle {
        if isRecording { return .primary }
        return isEmpty ? .tertiary : .primary
    }
}
