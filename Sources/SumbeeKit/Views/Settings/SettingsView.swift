import SwiftUI
import AppKit

/// Full-window settings overlay opened from the gear. Sidebar + section detail on a glass panel.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var section: Section =
        ProcessInfo.processInfo.environment["SUMBEE_SETTINGS_SECTION"]
            .flatMap(Section.init(rawValue:)) ?? .apiKey

    enum Section: String, CaseIterable, Identifiable {
        case apiKey = "API Key"
        case generation = "Generation"
        case library = "Library"
        case styles = "Styles"
        case systemPrompt = "System Prompt"
        case youtube = "YouTube"
        case output = "Output"
        case about = "Privacy & About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .apiKey: return "key.fill"
            case .generation: return "slider.horizontal.3"
            case .library: return "folder.fill"
            case .styles: return "square.stack.3d.up.fill"
            case .systemPrompt: return "text.alignleft"
            case .youtube: return "play.rectangle.fill"
            case .output: return "doc.fill"
            case .about: return "lock.shield.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { close() }

            HStack(spacing: 0) {
                sidebar
                Divider().overlay(Theme.hairline)
                detail
            }
            .frame(width: 900, height: 680)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 34, y: 12)
        }
        .onChange(of: state.settings) { state.scheduleSave() }
        .onChange(of: state.pendingNewStyle) { if state.pendingNewStyle { section = .styles } }
        .onAppear { if state.pendingNewStyle { section = .styles } }
        .onExitCommand { close() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 8)

            ForEach(Section.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon).frame(width: 18)
                        Text(item.rawValue).font(.uiBody)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(section == item ? Theme.accent.opacity(0.18) : .clear)
                    )
                    .foregroundStyle(section == item ? Theme.accent : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 196)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            HStack {
                Text(section.rawValue).font(.uiHeadline)
                Spacer()
                Button("Done") { close() }.buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider().overlay(Theme.hairline)
            detailBody
        }
    }

    /// Prompt-editing sections (Styles, System Prompt) fill the full height for a roomy, non-modal
    /// editor (FR-035); everything else stays in a scrollable card layout.
    @ViewBuilder private var detailBody: some View {
        switch section {
        case .apiKey: scroll { APIKeySection() }
        case .generation: scroll { GenerationSection() }
        case .library: scroll { LibrarySection() }
        case .styles:
            StylesCRUDSection()
                .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .systemPrompt:
            SystemPromptSection()
                .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .youtube: scroll { YouTubeSettingsSection() }
        case .output: scroll { OutputSection() }
        case .about: scroll { AboutSection() }
        }
    }

    private func scroll<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView {
            content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func close() {
        state.persistSettings()   // flush any debounced save immediately
        withAnimation(Theme.spring) { state.showSettings = false }
    }
}

// MARK: - API Key

private struct APIKeySection: View {
    @EnvironmentObject private var state: AppState
    @State private var keyInput = ""
    @State private var validating = false
    @State private var statusText: String?
    @State private var statusOK = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Anthropic API key", systemImage: "key.fill") {
                HStack(spacing: 6) {
                    Image(systemName: state.hasKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.hasKey ? .green : .orange)
                    Text(state.hasKey ? "A key is stored in your Keychain." : "No key stored yet.")
                        .font(.uiBody).foregroundStyle(.secondary)
                }

                SecureField("sk-ant-…", text: $keyInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        Task { await validate() }
                    } label: {
                        if validating { ProgressView().controlSize(.small) } else { Text("Save & Validate") }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(keyInput.isEmpty || validating)

                    if state.hasKey {
                        Button("Remove key", role: .destructive) {
                            state.removeKey(); keyInput = ""; statusText = nil
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    Spacer()
                }

                if let statusText {
                    Label(statusText, systemImage: statusOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.uiCaption)
                        .foregroundStyle(statusOK ? .green : .red)
                }

                Text("Stored securely in the macOS Keychain and read only when summarizing. It is never written to files or logs.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }
        }
    }

    private func validate() async {
        validating = true
        statusText = nil
        let error = await state.saveAndValidateKey(keyInput)
        validating = false
        if let error {
            statusOK = false
            statusText = error
        } else {
            statusOK = true
            statusText = "Key validated and saved."
            keyInput = ""
        }
    }
}

// MARK: - Generation (model + params, capability-aware)

private struct GenerationSection: View {
    @EnvironmentObject private var state: AppState

    private var caps: ModelCapabilities { ModelCatalog.capabilities(for: state.settings.model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Model", systemImage: "cpu") {
                HStack {
                    Picker("Model", selection: modelBinding) {
                        ForEach(state.modelsForPicker) { preset in
                            Text(preset.displayName).tag(preset.id)
                        }
                        Text("Custom…").tag("__custom__")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Button { state.fetchModels() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Refresh the model list from your Anthropic account")
                        .accessibilityLabel("Refresh models")
                }

                if !modelIsKnown(state.settings.model) {
                    TextField("model-id", text: Binding(
                        get: { state.settings.model },
                        set: { state.settings.model = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                Text("Populated from your Anthropic account when online. Defaults to the latest model; only parameters the model supports are sent.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }

            SettingsCard("Output length", systemImage: "text.alignleft") {
                Stepper(value: $state.settings.maxOutputTokens, in: 512...caps.maxOutputCeiling, step: 512) {
                    Text("Max output tokens: \(state.settings.maxOutputTokens)")
                }
            }

            if caps.supportsTemperature {
                SettingsCard("Temperature", systemImage: "thermometer.medium") {
                    HStack {
                        Slider(value: $state.settings.temperature, in: 0...1)
                        Text(String(format: "%.2f", state.settings.temperature))
                            .font(.system(size: 15, design: .monospaced)).frame(width: 44)
                    }
                    Text("Lower = more faithful. 0.3 is a good default for summaries.")
                        .font(.uiCaption).foregroundStyle(.secondary)
                }
            }

            if caps.supportsEffort {
                SettingsCard("Reasoning effort", systemImage: "brain") {
                    Picker("Effort", selection: effortBinding) {
                        Text("Default").tag("")
                        ForEach(caps.effortLevels, id: \.self) { lvl in
                            Text(lvl.capitalized).tag(lvl)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if caps.supportsAdaptiveThinking {
                SettingsCard("Extended thinking", systemImage: "sparkle") {
                    Toggle("Let the model think before summarizing", isOn: $state.settings.extendedThinking)
                    Text("Off by default for faster, faithful summaries.")
                        .font(.uiCaption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { state.fetchModels() }
        .onChange(of: state.settings.model) {
            // Shared normalization (effort clamp + token ceiling) — same path the bottom-bar
            // model menu uses, so Settings and the bar stay in sync.
            state.normalizeGenerationForModel()
        }
    }

    private func modelIsKnown(_ id: String) -> Bool {
        state.availableModels.contains { $0.id == id }
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { modelIsKnown(state.settings.model) ? state.settings.model : "__custom__" },
            set: { newValue in
                if newValue == "__custom__" {
                    if modelIsKnown(state.settings.model) { state.settings.model = "" }
                } else {
                    state.settings.model = newValue
                }
            }
        )
    }

    private var effortBinding: Binding<String> {
        Binding(
            get: {
                let e = state.settings.effort ?? ""
                // Show "Default" rather than an empty/blank segment if the stored level
                // isn't valid for the current model.
                return caps.effortLevels.contains(e) ? e : ""
            },
            set: { state.settings.effort = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Library

private struct LibrarySection: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        SettingsCard("Library folder", systemImage: "folder.fill") {
            Text(state.settings.libraryRootURL.path)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
            HStack {
                Button("Change…") { chooseFolder() }.buttonStyle(AccentButtonStyle())
                Button("Reveal in Finder") {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.open(state.settings.libraryRootURL, configuration: config,
                                            completionHandler: nil)
                }.buttonStyle(GhostButtonStyle())
                Spacer()
            }
            Text("Summaries and archived sources live here as plain files. Changing this does not move existing files.")
                .font(.uiCaption).foregroundStyle(.secondary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = state.settings.libraryRootURL
        if panel.runModal() == .OK, let url = panel.url {
            state.changeLibraryRoot(to: url)
        }
    }
}

// MARK: - Output format

private struct OutputSection: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Output format", systemImage: "doc.fill") {
                Picker("Format", selection: $state.settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Markdown is the default. HTML produces a self-contained styled document.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }

            if state.settings.outputFormat == .html {
                SettingsCard("HTML styling prompt (optional)", systemImage: "paintbrush.fill") {
                    BigPromptEditor(text: $state.settings.htmlStylingPrompt, minHeight: 220)
                    Text("Applied to every HTML summary for consistent colors, fonts, and layout. Leave empty for clean semantic HTML.")
                        .font(.uiCaption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - YouTube settings

private struct YouTubeSettingsSection: View {
    @EnvironmentObject private var state: AppState
    @State private var updating = false
    @State private var status: String?

    private var located: URL? { YouTubeService().locate(customPath: state.settings.ytDlpPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Captions", systemImage: "captions.bubble") {
                HStack {
                    Text("Language")
                    TextField("en", text: $state.settings.captionLanguage).frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                }
                Text("Human-authored captions are preferred over auto-generated.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }

            SettingsCard("yt-dlp", systemImage: "play.rectangle.fill") {
                HStack(spacing: 6) {
                    Image(systemName: located != nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(located != nil ? .green : .orange)
                    Text(located?.path ?? "Not found")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button {
                        Task { await update() }
                    } label: {
                        if updating { ProgressView().controlSize(.small) } else { Text("Download / Update yt-dlp") }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(updating)
                    Spacer()
                }
                if let status {
                    Text(status).font(.uiCaption).foregroundStyle(.secondary)
                }
                Text("Used only for fetching YouTube captions. Required only for the YouTube feature.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }
        }
    }

    private func update() async {
        updating = true; status = "Downloading the latest yt-dlp…"
        do {
            let url = try await YouTubeService().update(into: AppSettings.appSupportDirectory)
            state.settings.ytDlpPath = url.path
            state.persistSettings()
            status = "Installed at \(url.path)"
        } catch {
            status = "Update failed: \(error.localizedDescription)"
        }
        updating = false
    }
}

// MARK: - About / Privacy

private struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Privacy", systemImage: "lock.shield.fill") {
                Text("Everything stays on your Mac except two actions you start:")
                    .font(.uiBody)
                Label("Transcript text and your prompt are sent to the Anthropic API for summarization.",
                      systemImage: "arrow.up.circle").font(.uiBody)
                Label("YouTube caption fetching contacts YouTube via yt-dlp.",
                      systemImage: "arrow.up.circle").font(.uiBody)
                Text("No analytics or telemetry. Browsing and opening existing summaries works offline.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }
            SettingsCard("About", systemImage: "info.circle.fill") {
                Text("Summarizer — a local-first macOS app. Your summaries are plain files you own.")
                    .font(.uiBody).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - System prompt (shared prefix for all styles)

private struct SystemPromptSection: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prepended to every style", systemImage: "text.alignleft")
                .font(.uiBody.weight(.semibold)).foregroundStyle(Theme.accent)
            Text("This text is added in front of every style's prompt, so shared instructions live in one place instead of being repeated in each style. The app still appends its output convention. Leave empty for none.")
                .font(.uiCaption).foregroundStyle(.secondary)
            BigPromptEditor(text: $state.settings.systemPrompt, fill: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Shared prompt editor (used by System Prompt, Styles, HTML styling — FR-035)

struct BigPromptEditor: View {
    @Binding var text: String
    var fill: Bool = false
    var minHeight: CGFloat = 220

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: fill ? .infinity : nil)
    }
}

// MARK: - Shared card

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.uiBody.weight(.semibold))
                .foregroundStyle(Theme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }
}
