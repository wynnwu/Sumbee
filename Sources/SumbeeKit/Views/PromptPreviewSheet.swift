import SwiftUI

/// Geek mode (FR-039): a modal that appears immediately with a spinner while the prompt is
/// assembled, then reveals the exact prompt to be sent + an estimated token count, with Send / Cancel.
struct PromptPreviewSheet: View {
    @EnvironmentObject private var state: AppState
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Group {
            switch state.previewPhase {
            case .ready(let preview):
                ready(preview).transition(.opacity)
            case .preparing, .none:
                preparing.transition(.opacity)
            }
        }
        .animation(Theme.quick, value: isReady)
        .frame(width: 700, height: 580)
    }

    private var isReady: Bool {
        if case .ready = state.previewPhase { return true }
        return false
    }

    // MARK: Preparing (immediate spinner)

    private var preparing: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large).tint(Theme.accent)
            Text("Preparing prompt stats and preview…")
                .font(.uiBody).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Ready (full prompt)

    private func ready(_ preview: PendingPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Prompt preview").font(.uiHeadline)
                Spacer()
                Text("~\(preview.estimatedTokens) input tokens · \(preview.modelName)")
                    .font(.uiCaption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text("This is exactly what will be sent. Estimate is approximate.")
                .font(.uiCaption).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("System prompt", preview.system)
                    section("User message", preview.user)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Send") { onSend() }
                    .buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.uiBody.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
