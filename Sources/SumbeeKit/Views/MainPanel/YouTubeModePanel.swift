import SwiftUI

/// YouTube mode (FR-070..FR-073): paste a video or a playlist. A single video shows the existing
/// per-style buttons; a playlist fetches an inline checklist to trim (already-done excluded) and
/// summarize through a chosen YouTube style.
struct YouTubeModePanel: View {
    @EnvironmentObject private var state: AppState
    @State private var urlText = ""
    @State private var toolAvailable = false
    @State private var confirming = false
    @State private var selected: Set<String> = []
    @State private var chosenStyleID: UUID?
    /// The playlist URL whose default selection we've already populated, so a style/library change
    /// prunes finished videos rather than clobbering the user's manual checkbox edits.
    @State private var populatedURL: URL?

    private var videoURL: URL? { YouTubeService.validate(urlString: urlText) }
    private var playlistURL: URL? { YouTubeService.validatePlaylist(urlString: urlText) }
    private var youtubeStyles: [SummaryStyle] { state.youtubeStyles }
    private var chosenStyle: SummaryStyle? { youtubeStyles.first { $0.id == chosenStyleID } ?? youtubeStyles.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.sectionLabel("YouTube - Summarize a Video or Playlist").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                urlField
                content
            }
            .padding(16)
            .glassCard()
        }
        .onAppear { refreshTool(); if chosenStyleID == nil { chosenStyleID = youtubeStyles.first?.id } }
        .onChange(of: state.settings.ytDlpPath) { refreshTool() }
        .onChange(of: state.playlistFetch) { recomputeSelection() }
        .onChange(of: chosenStyleID) { recomputeSelection() }
        .onChange(of: state.library) { recomputeSelection() }
    }

    @ViewBuilder private var content: some View {
        if !toolAvailable {
            missingTool
        } else if youtubeStyles.isEmpty {
            Text("No YouTube styles yet. Add one in Settings ▸ Styles.").font(.uiBody).foregroundStyle(.secondary)
        } else if let playlistURL {
            playlistArea(playlistURL)
        } else if videoURL != nil {
            singleVideoButtons
        } else if !urlText.isEmpty && !confirming {
            Label("Paste a YouTube video or playlist URL.", systemImage: "exclamationmark.triangle")
                .font(.uiCaption).foregroundStyle(.orange)
        } else {
            Text("Paste a video URL to summarize one, or a playlist URL (youtube.com/playlist?list=…) to summarize many.")
                .font(.uiCaption).foregroundStyle(.secondary)
        }
    }

    private var urlField: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.uiBody).foregroundStyle(.secondary)
            TextField("Paste a YouTube video or playlist URL…", text: $urlText)
                .textFieldStyle(.plain).font(.uiBody)
            if !urlText.isEmpty {
                Button { clearAll() } label: {
                    Image(systemName: "xmark.circle.fill").font(.uiBody)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    // MARK: Single video (existing behavior)

    private var singleVideoButtons: some View {
        HStack(spacing: 8) {
            Spacer()
            ForEach(youtubeStyles) { style in
                Button { submitSingle(style) } label: {
                    Text(youtubeStyles.count == 1 ? "Summarize Video" : "Summarize: \(style.name)").padding(.horizontal, 14)
                }
                .buttonStyle(AccentButtonStyle(prominent: true))
                .disabled(videoURL == nil || !state.hasKey)
                .opacity((videoURL == nil || !state.hasKey) ? 0.5 : 1)
            }
        }
    }

    // MARK: Playlist

    @ViewBuilder private func playlistArea(_ url: URL) -> some View {
        switch state.playlistFetch {
        case .loaded(let u, let entries) where u == url:
            playlistPicker(entries)
        case .loading(let u) where u == url:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Fetching playlist…").font(.uiCaption).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 8) {
                Label(msg, systemImage: "exclamationmark.triangle").font(.uiCaption).foregroundStyle(.orange)
                Button("Try again") { state.fetchPlaylist(url) }.buttonStyle(GhostButtonStyle())
            }
        default:
            HStack {
                Text("Playlist detected.").font(.uiCaption).foregroundStyle(.secondary)
                Spacer()
                Button { state.fetchPlaylist(url) } label: { Text("Fetch playlist").padding(.horizontal, 12) }
                    .buttonStyle(AccentButtonStyle(prominent: true))
                    .disabled(!state.hasKey)
            }
        }
    }

    @ViewBuilder private func playlistPicker(_ entries: [PlaylistEntry]) -> some View {
        let doneCount = entries.filter { isDone($0) }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(entries.count) videos").font(.uiBody.weight(.semibold))
                Button("All") { selected = Set(entries.map(\.videoID)) }.buttonStyle(GhostButtonStyle())
                Button("None") { selected = [] }.buttonStyle(GhostButtonStyle())
                Spacer()
                if doneCount > 0 {
                    Text("\(doneCount) already summarized").font(.uiCaption).foregroundStyle(.secondary)
                }
            }
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in entryRow(entry) }
            }
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
            footer(entries)
        }
    }

    private func entryRow(_ entry: PlaylistEntry) -> some View {
        let on = selected.contains(entry.videoID)
        let done = isDone(entry)
        return Button {
            if on { selected.remove(entry.videoID) } else { selected.insert(entry.videoID) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Theme.accent : .secondary)
                Text(String(format: "%03d", entry.index))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Text(entry.title).lineLimit(1).foregroundStyle(done ? .secondary : .primary)
                Spacer(minLength: 8)
                if done { Text("done").font(.caption).foregroundStyle(.green) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footer(_ entries: [PlaylistEntry]) -> some View {
        HStack(spacing: 10) {
            if youtubeStyles.count > 1 {
                Picker("", selection: Binding(get: { chosenStyleID ?? youtubeStyles.first?.id },
                                              set: { chosenStyleID = $0 })) {
                    ForEach(youtubeStyles) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden().fixedSize()
            } else if let only = youtubeStyles.first {
                Text("Style: \(only.name)").font(.uiCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(selected.count) selected · ~\(max(selected.count, 1) * 5)k tok (rough)")
                .font(.uiCaption).foregroundStyle(.secondary).monospacedDigit()
            Button {
                guard let style = chosenStyle else { return }
                state.summarizePlaylist(entries.filter { selected.contains($0.videoID) }, style: style)
                clearAll()   // summarizePlaylist collapses the picker; also clear the field + local state
            } label: {
                Text("Summarize \(selected.count)").padding(.horizontal, 12)
            }
            .buttonStyle(AccentButtonStyle(prominent: true))
            .disabled(selected.isEmpty || !state.hasKey || chosenStyle == nil)
            .opacity((selected.isEmpty || !state.hasKey) ? 0.5 : 1)
        }
    }

    private var missingTool: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver").font(.uiBody).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("yt-dlp not found").font(.uiBody.weight(.semibold))
                Text("Install it to summarize YouTube videos.").font(.uiCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings") { state.showSettings = true }.buttonStyle(GhostButtonStyle())
        }
    }

    // MARK: Helpers

    private func refreshTool() { toolAvailable = YouTubeService().locate(customPath: state.settings.ytDlpPath) != nil }

    private func isDone(_ entry: PlaylistEntry) -> Bool {
        guard let style = chosenStyle else { return false }
        return state.isVideoSummarized(id: entry.videoID, inStyle: style)
    }

    /// Keep the selection sensible as the list, style, or library changes: populate the not-done
    /// default once per freshly-loaded playlist; afterward only prune now-finished videos, so manual
    /// checkbox edits survive a style switch or a job completing mid-session.
    private func recomputeSelection() {
        guard case .loaded(let url, let entries) = state.playlistFetch else { return }
        if populatedURL != url {
            populatedURL = url
            selected = Set(entries.filter { !isDone($0) }.map(\.videoID))
        } else {
            selected.subtract(Set(entries.filter { isDone($0) }.map(\.videoID)))
        }
    }

    /// Reset the field, local selection, and the shared fetch (cancels any in-flight enumeration).
    private func clearAll() {
        urlText = ""
        selected = []
        populatedURL = nil
        state.clearPlaylist()
    }

    private func submitSingle(_ style: SummaryStyle) {
        guard let u = videoURL else { return }
        state.enqueueYouTube(u, style: style)
        confirming = true; urlText = "Got it!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            confirming = false
            if urlText == "Got it!" { urlText = "" }
        }
    }
}
