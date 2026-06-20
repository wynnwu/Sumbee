import SwiftUI

struct StylesCRUDSection: View {
    @EnvironmentObject private var state: AppState
    @State private var editing: SummaryStyle?
    @State private var creating = false
    @State private var deleteTarget: SummaryStyle?

    private var sortedStyles: [SummaryStyle] {
        state.library.styles.sorted {
            if $0.channel != $1.channel { return $0.channel == .file && $1.channel == .youtube }
            return $0.order < $1.order
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Each style is an editable prompt that also names a folder in your library.")
                    .font(.uiCaption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset defaults") { state.resetStylesToDefaults() }
                    .buttonStyle(GhostButtonStyle())
                Button { creating = true } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(AccentButtonStyle())
            }

            if sortedStyles.isEmpty {
                Text("No styles yet. Add one, or reset to defaults.")
                    .font(.uiBody).foregroundStyle(.secondary)
            } else {
                ForEach(sortedStyles) { style in
                    row(style)
                }
            }
        }
        .sheet(item: $editing) { style in
            StyleEditor(mode: .edit(style))
        }
        .sheet(isPresented: $creating) {
            StyleEditor(mode: .create)
        }
        .alert("Remove this style?", isPresented: Binding(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Remove style", role: .destructive) {
                if let s = deleteTarget { state.deleteStyle(s) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Its folder and any summaries inside it are kept. Only the style definition is removed.")
        }
    }

    private func row(_ style: SummaryStyle) -> some View {
        HStack(spacing: 10) {
            Image(systemName: style.channel == .file ? "arrow.down.doc.fill" : "play.rectangle.fill")
                .foregroundStyle(Theme.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name).font(.uiBody.weight(.semibold))
                StatusChip(text: style.channel == .file ? "File" : "YouTube", tint: .secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { style.enabled },
                set: { state.setStyleEnabled(style, $0) }
            ))
            .labelsHidden().toggleStyle(.switch).help("Enabled")

            Button { state.moveStyle(style, up: true) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Move up").accessibilityLabel("Move \(style.name) up")
            Button { state.moveStyle(style, up: false) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Move down").accessibilityLabel("Move \(style.name) down")
            Button { editing = style } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Edit")
                .accessibilityLabel("Edit \(style.name)")
            Button { deleteTarget = style } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
                .accessibilityLabel("Remove \(style.name)")
        }
        .padding(12)
        .glassCard()
    }
}

enum StyleEditorMode {
    case create
    case edit(SummaryStyle)
}

private struct StyleEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let mode: StyleEditorMode

    @State private var name: String
    @State private var channel: StyleChannel
    @State private var prompt: String

    private let original: SummaryStyle?

    init(mode: StyleEditorMode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _channel = State(initialValue: .file)
            _prompt = State(initialValue: "")
            original = nil
        case .edit(let s):
            _name = State(initialValue: s.name)
            _channel = State(initialValue: s.channel)
            _prompt = State(initialValue: s.prompt)
            original = s
        }
    }

    private var isCreate: Bool { original == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isCreate ? "New Style" : "Edit Style")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.uiCaption).foregroundStyle(.secondary)
                    TextField("Meetings — General", text: $name).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channel").font(.uiCaption).foregroundStyle(.secondary)
                    Picker("", selection: $channel) {
                        ForEach(StyleChannel.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().frame(width: 180)
                }
            }

            Text("Prompt").font(.uiCaption).foregroundStyle(.secondary)
            TextEditor(text: $prompt)
                .font(.system(size: 15, design: .monospaced))
                .frame(minHeight: 220)
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))

            Text("The app appends a shared output convention (begin with a title heading, chosen format) automatically.")
                .font(.uiCaption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(GhostButtonStyle())
                Button(isCreate ? "Create" : "Save") { save() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }

    private func save() {
        if let original {
            var edited = original
            edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.channel = channel
            edited.prompt = prompt
            state.saveStyle(original: original, edited: edited)
        } else {
            state.createStyle(name: name, channel: channel, prompt: prompt)
        }
        dismiss()
    }
}
