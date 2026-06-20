import SwiftUI

struct YouTubeSection: View {
    @EnvironmentObject private var state: AppState
    @State private var urlText = ""
    @State private var toolAvailable = false
    @State private var confirming = false

    private var validURL: URL? { YouTubeService.validate(urlString: urlText) }

    private func refreshToolAvailability() {
        toolAvailable = YouTubeService().locate(customPath: state.settings.ytDlpPath) != nil
    }

    /// "Summarize YouTube Video" for the single default style; disambiguate when there are several.
    private func youtubeLabel(_ style: SummaryStyle) -> String {
        state.youtubeStyles.count == 1 ? "Summarize YouTube Video" : "Summarize: \(style.name)"
    }

    /// Enqueue the job, briefly flash "Got it!" in the field, then clear it.
    private func submit(_ style: SummaryStyle) {
        guard let u = validURL else { return }
        state.enqueueYouTube(u, style: style)
        confirming = true
        urlText = "Got it!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            confirming = false
            if urlText == "Got it!" { urlText = "" }   // don't clobber anything the user retyped
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link").font(.uiBody).foregroundStyle(.secondary)
                TextField("Paste a YouTube URL…", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.uiBody)
                if !urlText.isEmpty {
                    Button { urlText = "" } label: { Image(systemName: "xmark.circle.fill").font(.uiBody) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            if !toolAvailable {
                missingTool
            } else if state.youtubeStyles.isEmpty {
                Text("No YouTube styles yet. Add one in Settings ▸ Styles.")
                    .font(.uiBody).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(state.youtubeStyles) { style in
                        Button {
                            submit(style)
                        } label: {
                            Text(youtubeLabel(style)).padding(.horizontal, 14)
                        }
                        .buttonStyle(AccentButtonStyle(prominent: true))
                        .disabled(validURL == nil || !state.hasKey)
                        .opacity((validURL == nil || !state.hasKey) ? 0.5 : 1)
                    }
                }
            }

            if !confirming && !urlText.isEmpty && validURL == nil {
                Label("That doesn’t look like a YouTube URL.", systemImage: "exclamationmark.triangle")
                    .font(.uiCaption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .glassCard()
        .onAppear { refreshToolAvailability() }
        .onChange(of: state.settings.ytDlpPath) { refreshToolAvailability() }
    }

    private var missingTool: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver").font(.uiBody).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("yt-dlp not found").font(.uiBody.weight(.semibold))
                Text("Install it to summarize YouTube videos.").font(.uiCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings") { state.showSettings = true }
                .buttonStyle(GhostButtonStyle())
        }
    }
}
