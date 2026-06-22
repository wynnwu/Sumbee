import SwiftUI

/// Styles list + an inline, full-height prompt editor (no stacked modal — FR-035).
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
        if creating {
            StyleEditorInline(mode: .create) { creating = false }
        } else if let style = editing {
            StyleEditorInline(mode: .edit(style)) { editing = nil }
        } else {
            listView
        }
    }

    private var listView: some View {
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
                List {
                    ForEach(sortedStyles) { style in
                        row(style)
                            .listRowSeparator(.visible)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        state.reorderStyles(from: from, to: to, current: sortedStyles)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { autoEditFirstStyleIfRequested(); startNewStyleIfRequested() }
        .onChange(of: state.library.styles.count) { autoEditFirstStyleIfRequested() }
        .onChange(of: state.pendingNewStyle) { startNewStyleIfRequested() }
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

    /// ⌘N (FR-044): start a new style when requested from the app menu.
    private func startNewStyleIfRequested() {
        guard state.pendingNewStyle, editing == nil else { return }
        creating = true
        state.pendingNewStyle = false
    }

    /// Verification hook: jump straight into editing the first style for a headless shot.
    private func autoEditFirstStyleIfRequested() {
        guard editing == nil, !creating,
              ProcessInfo.processInfo.environment["SUMBEE_EDIT_FIRST_STYLE"] == "1",
              let first = sortedStyles.first else { return }
        editing = first
    }

    private func row(_ style: SummaryStyle) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
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

            Button { editing = style } label: { Image(systemName: "square.and.pencil").font(.system(size: 18)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Edit")
                .accessibilityLabel("Edit \(style.name)")
            Button { deleteTarget = style } label: { Image(systemName: "trash").font(.system(size: 15)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
                .accessibilityLabel("Remove \(style.name)")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

enum StyleEditorMode {
    case create
    case edit(SummaryStyle)
}

/// Inline, full-height style editor — replaces the old floating sheet (FR-035).
private struct StyleEditorInline: View {
    @EnvironmentObject private var state: AppState
    let mode: StyleEditorMode
    let onClose: () -> Void

    @State private var name: String
    @State private var channel: StyleChannel
    @State private var prompt: String

    // Per-style model/format override (FR-038)
    @State private var advancedOpen: Bool
    @State private var overrideOn: Bool
    @State private var ovModel: String
    @State private var ovFormat: OutputFormat
    @State private var ovMaxTokens: Int

    private let original: SummaryStyle?

    init(mode: StyleEditorMode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        let source: SummaryStyle?
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _channel = State(initialValue: .file)
            _prompt = State(initialValue: "")
            source = nil
        case .edit(let s):
            _name = State(initialValue: s.name)
            _channel = State(initialValue: s.channel)
            _prompt = State(initialValue: s.prompt)
            source = s
        }
        original = source
        let mo = source?.modelOverride
        let hasOverride = mo != nil && !(mo?.isEmpty ?? true)
        _advancedOpen = State(initialValue: hasOverride)
        _overrideOn = State(initialValue: hasOverride)
        _ovModel = State(initialValue: mo?.model ?? ModelCatalog.defaultModelID)
        _ovFormat = State(initialValue: mo?.outputFormat ?? .markdown)
        _ovMaxTokens = State(initialValue: mo?.maxOutputTokens ?? 8192)
    }

    private var isCreate: Bool { original == nil }

    private var builtOverride: ModelOverride? {
        guard overrideOn else { return nil }
        return ModelOverride(model: ovModel.isEmpty ? nil : ovModel,
                             maxOutputTokens: ovMaxTokens,
                             outputFormat: ovFormat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { onClose() } label: { Label("Styles", systemImage: "chevron.left") }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Text(isCreate ? "New Style" : "Edit Style").font(.uiHeadline)
                Spacer()
                Button(isCreate ? "Create" : "Save") { save() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

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

            DisclosureGroup(isExpanded: $advancedOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Override the global model & output format for this style", isOn: $overrideOn)
                    if overrideOn {
                        HStack(spacing: 12) {
                            Picker("Model", selection: $ovModel) {
                                ForEach(state.modelsForPicker) { Text($0.displayName).tag($0.id) }
                            }.frame(maxWidth: 300)
                            FlatSegmented(selection: $ovFormat,
                                          options: OutputFormat.allCases.map { ($0, $0.displayName) })
                                .frame(width: 210)
                        }
                        Stepper("Max output tokens: \(ovMaxTokens)", value: $ovMaxTokens, in: 512...64000, step: 512)
                    }
                }
                .font(.uiCaption)
                .padding(.top, 4)
            } label: {
                Text("Advanced — per-style model & format").font(.uiCaption).foregroundStyle(.secondary)
            }

            Text("Prompt").font(.uiCaption).foregroundStyle(.secondary)
            BigPromptEditor(text: $prompt, fill: true)

            Text("The shared System Prompt (if set) is prepended automatically, and the app appends a format-aware output convention (begin with a title heading) — so this prompt stays focused on style.")
                .font(.uiCaption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func save() {
        if let original {
            var edited = original
            edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.channel = channel
            edited.prompt = prompt
            edited.modelOverride = builtOverride
            state.saveStyle(original: original, edited: edited)
        } else {
            state.createStyle(name: name, channel: channel, prompt: prompt, modelOverride: builtOverride)
        }
        onClose()
    }
}
