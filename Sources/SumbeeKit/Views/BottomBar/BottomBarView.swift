import SwiftUI

struct BottomBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var activelyRunningJob: Job? {
        state.jobs.first {
            switch $0.phase {
            case .extracting, .fetching, .summarizing, .saving: return true
            default: return false
            }
        }
    }
    private var isRunning: Bool { activelyRunningJob != nil }
    private var doneCount: Int {
        state.jobs.filter { if case .done = $0.phase { return true } else { return false } }.count
    }
    private var finishedCount: Int { state.jobs.filter { $0.phase.isTerminal }.count }

    var body: some View {
        HStack(spacing: 14) {
            settingsButton
            barDivider
            modelMenu
            barDivider
            outputToggle
            barDivider
            geekToggle

            if !state.hasKey {
                barDivider
                StatusChip(systemImage: "key", text: "No API key", tint: .orange)
            }

            Spacer()

            if state.hasPendingRetry {
                Button("Run queue") { state.runQueueNow() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Retry waiting and failed jobs now")
            }

            if let line = state.statusLine {
                if isRunning {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                } else {
                    Image(systemName: "clock.arrow.circlepath").font(.uiBody).foregroundStyle(.secondary)
                }
                Text(line)
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if state.streamingJobID != nil && !state.watchingStream {
                    Button("Watch") { state.watchStream() }
                        .buttonStyle(GhostButtonStyle())
                        .help("Return to the live generation in the preview")
                }
                if let running = activelyRunningJob {
                    Button("Cancel") { state.cancel(running.id) }
                        .buttonStyle(GhostButtonStyle())
                }
            } else if finishedCount > 0 {
                Text("\(doneCount) summarized")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                Button("Clear") { state.clearFinishedJobs() }
                    .buttonStyle(GhostButtonStyle())
            } else {
                Text("Ready")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(barBackground)
        .overlay(alignment: .top) { topEdge }
    }

    private var settingsButton: some View {
        Button { state.showSettings = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill").font(.system(size: 16))
                Text("Settings").font(.uiCallout)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
    }

    /// Thin vertical separator between bottom-bar controls.
    private var barDivider: some View {
        Divider().frame(height: 18).overlay(Theme.hairline)
    }

    // MARK: Model menu (FR-024)

    private var modelMenu: some View {
        HStack(spacing: 7) {
            Text("Model").font(.uiCallout).foregroundStyle(.secondary)
            Menu {
                ForEach(state.modelsForPicker) { model in
                    Button {
                        state.selectModel(model.id)
                    } label: {
                        if model.id == state.settings.model {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
                Divider()
                Button("Refresh models") { state.fetchModels() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu").font(.uiCallout)
                    Text(shortModel).font(.uiCallout.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Rectangle().fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch model")
        }
    }

    // MARK: Output format toggle

    private var outputToggle: some View {
        HStack(spacing: 7) {
            Text("Output").font(.uiCallout).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                segment(.markdown, "Markdown")
                segment(.html, "HTML Webpage")
            }
            .padding(2)
            .background(Rectangle().fill(Color.primary.opacity(0.06)))
            .accessibilityLabel("Output format")
        }
        .help("Output format for new summaries")
    }

    @ViewBuilder
    private func segment(_ fmt: OutputFormat, _ label: String) -> some View {
        let active = state.settings.outputFormat == fmt
        Button {
            if state.settings.outputFormat != fmt {
                state.settings.outputFormat = fmt
                state.persistSettings()
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(active ? Color.white : Color.secondary)
                .background { if active { Rectangle().fill(Theme.accentGradient) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Save new summaries as \(fmt.displayName)")
    }

    // MARK: Geek mode toggle (FR-039)

    private var geekToggle: some View {
        Button {
            state.settings.geekMode.toggle()
            state.persistSettings()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text("Geek").font(.uiCallout.weight(.semibold))
            }
            .font(.uiCallout.weight(.semibold))
            .foregroundStyle(state.settings.geekMode ? Color.white : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background {
                if state.settings.geekMode { Rectangle().fill(Theme.accentGradient) }
                else { Rectangle().fill(Color.primary.opacity(0.06)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Geek mode: preview the exact prompt and an estimated token count before sending")
        .accessibilityLabel("Geek mode")
    }

    // MARK: Lively background (FR-028)

    @ViewBuilder
    private var barBackground: some View {
        ZStack {
            Rectangle().fill(.bar)
            if isRunning {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let shift = CGFloat((sin(t * 1.4) + 1) / 2)   // 0…1 sweep
                    LinearGradient(
                        colors: [Theme.accent, .pink, .purple, .blue, Theme.accentWarm, Theme.accent],
                        startPoint: UnitPoint(x: shift - 0.4, y: 0.5),
                        endPoint: UnitPoint(x: shift + 0.6, y: 0.5)
                    )
                    .hueRotation(.degrees(t.truncatingRemainder(dividingBy: 12) * 30))
                    // `.plusLighter` glows over dark, but washes out on light → use a solid wash there.
                    .opacity(colorScheme == .dark ? 0.45 : 0.7)
                    .blendMode(colorScheme == .dark ? .plusLighter : .normal)
                }
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var topEdge: some View {
        if isRunning {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let shift = CGFloat((sin(t * 1.4) + 1) / 2)
                LinearGradient(
                    colors: [Theme.accentWarm, .pink, .purple, .blue, Theme.accent],
                    startPoint: UnitPoint(x: shift - 0.4, y: 0.5),
                    endPoint: UnitPoint(x: shift + 0.6, y: 0.5)
                )
                .hueRotation(.degrees(t.truncatingRemainder(dividingBy: 12) * 30))
                .frame(height: 2)
            }
            .allowsHitTesting(false)
        } else {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var shortModel: String {
        if let preset = ModelCatalog.presets.first(where: { $0.id == state.settings.model }) {
            return preset.displayName.replacingOccurrences(of: "Claude ", with: "")
                .replacingOccurrences(of: " (latest)", with: "")
        }
        if let live = state.availableModels.first(where: { $0.id == state.settings.model }) {
            return live.displayName.replacingOccurrences(of: "Claude ", with: "")
        }
        return state.settings.model.isEmpty ? "Custom" : state.settings.model
    }
}
