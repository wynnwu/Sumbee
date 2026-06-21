import SwiftUI

/// Geek mode (FR-039): shows the exact prompt to be sent + an estimated token count, with
/// Send / Cancel, before a single summary is queued.
struct PromptPreviewSheet: View {
    let preview: PendingPreview
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
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
        .frame(width: 700, height: 580)
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
