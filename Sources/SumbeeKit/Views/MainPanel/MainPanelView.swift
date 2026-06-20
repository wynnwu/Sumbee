import SwiftUI

/// The left column: a brand header, file-style drop zones, and the YouTube section.
struct MainPanelView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header

                if !state.hasKey {
                    keyGateBanner
                }

                fileStylesSection
                youtubeSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle()
                    .fill(Theme.accentGradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: Theme.accentGlow(0.5), radius: 8, y: 2)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Sumbee")
                    .font(.uiTitle)
                Text("Transcripts & videos → clean notes")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var keyGateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill").font(.uiBody).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set your API key to begin").font(.uiBody.weight(.semibold))
                Text("Summarizing is disabled until a key is saved.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { state.showSettings = true }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(14)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: File styles

    private var fileStylesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.sectionLabel("File styles — drop transcripts")
                .foregroundStyle(.secondary)

            if state.fileStyles.isEmpty {
                emptyStylesHint(channel: "file")
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(state.fileStyles) { style in
                        DropZoneView(style: style)
                    }
                }
            }
        }
    }

    // MARK: YouTube

    private var youtubeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.sectionLabel("YouTube — summarize from captions")
                .foregroundStyle(.secondary)
            YouTubeSection()
        }
    }

    private func emptyStylesHint(channel: String) -> some View {
        Text("No \(channel) styles yet. Add one in Settings ▸ Styles.")
            .font(.uiBody)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard()
    }
}
