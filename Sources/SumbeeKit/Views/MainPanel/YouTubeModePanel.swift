import SwiftUI

/// YouTube mode (FR-070..FR-077): paste a video or a playlist, or reopen a kept playlist. A single
/// video shows the per-style buttons; a playlist shows an inline checklist - already-summarized and
/// in-flight videos are excluded - that summarizes the selection through a chosen YouTube style.
/// Fetched playlists are kept (no re-fetch) and listed under "Your playlists" with Refresh / Remove.
struct YouTubeModePanel: View {
    @EnvironmentObject private var state: AppState
    @State private var urlText = ""
    @State private var toolAvailable = false
    @State private var confirming = false
    @State private var selected: Set<String> = []
    @State private var chosenStyleID: UUID?
    /// The loaded playlist URL whose default selection we've populated, so style/library changes
    /// prune rather than clobber the user's manual edits.
    @State private var populatedURL: URL?
    @State private var hoveredVideoID: String?
    @Environment(\.openURL) private var openURL

    private var videoURL: URL? { YouTubeService.validate(urlString: urlText) }
    private var playlistURL: URL? { YouTubeService.validatePlaylist(urlString: urlText) }
    private var youtubeStyles: [SummaryStyle] { state.youtubeStyles }
    private var chosenStyle: SummaryStyle? { youtubeStyles.first { $0.id == chosenStyleID } ?? youtubeStyles.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            // Input card: paste a video or playlist URL + its result (single buttons / picker).
            VStack(alignment: .leading, spacing: 10) {
                Theme.sectionLabel("YouTube - Summarize a Video or Playlist").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    urlField
                    content
                }
                .padding(16)
                .glassCard()
            }
            // Kept playlists: a separate section, not crammed into the input box.
            if showSavedList {
                VStack(alignment: .leading, spacing: 10) {
                    Theme.sectionLabel("Your Playlists").foregroundStyle(.secondary)
                    savedPlaylistsCard
                }
            }
        }
        .onAppear { refreshTool(); if chosenStyleID == nil { chosenStyleID = youtubeStyles.first?.id } }
        .onChange(of: state.settings.ytDlpPath) { refreshTool() }
        .onChange(of: state.playlistFetch) { recomputeSelection() }
        .onChange(of: chosenStyleID) { recomputeSelection() }
        .onChange(of: state.library) { recomputeSelection() }
    }

    // MARK: Content router

    @ViewBuilder private var content: some View {
        if !toolAvailable {
            missingTool
        } else if youtubeStyles.isEmpty {
            Text("No YouTube styles yet. Add one in Settings ▸ Styles.").font(.uiBody).foregroundStyle(.secondary)
        } else {
            switch state.playlistFetch {
            case .loaded(let url, let entries): playlistPicker(url: url, entries: entries)
            case .loading: loadingRow
            case .failed(let msg): failedRow(msg)
            case .idle: idleContent
            }
        }
    }

    @ViewBuilder private var idleContent: some View {
        if let playlistURL {
            fetchPrompt(playlistURL)
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
                Button { clearAll() } label: { Image(systemName: "xmark.circle.fill").font(.uiBody) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    // MARK: Saved playlists (FR-076/077) - a separate section below the input card

    /// Show the kept-playlists section only when idle (not fetching, and not inside a picker).
    private var showSavedList: Bool {
        if case .idle = state.playlistFetch { return !state.savedPlaylists.isEmpty }
        return false
    }

    private var savedPlaylistsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(state.savedPlaylists) { saved in savedRow(saved) }
        }
        .padding(16)
        .glassCard()
    }

    private func savedRow(_ saved: SavedPlaylist) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "list.and.film").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(saved.title).font(.uiBody).lineLimit(1)
                Text("\(saved.entries.count) videos · fetched \(saved.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open") { state.openSavedPlaylist(saved) }.buttonStyle(GhostButtonStyle())
            Button("Refresh") { state.refreshSavedPlaylist(saved) }.buttonStyle(GhostButtonStyle())
            Button { state.removeSavedPlaylist(saved) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove playlist")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { state.openSavedPlaylist(saved) }
    }

    // MARK: Transient states

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Fetching playlist…").font(.uiCaption).foregroundStyle(.secondary)
        }
    }

    private func failedRow(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(msg, systemImage: "exclamationmark.triangle").font(.uiCaption).foregroundStyle(.orange)
            Button("Back") { clearAll() }.buttonStyle(GhostButtonStyle())
        }
    }

    private func fetchPrompt(_ url: URL) -> some View {
        HStack {
            Text("Playlist detected.").font(.uiCaption).foregroundStyle(.secondary)
            Spacer()
            Button { state.fetchPlaylist(url) } label: { Text("Fetch playlist").padding(.horizontal, 12) }
                .buttonStyle(AccentButtonStyle(prominent: true)).disabled(!state.hasKey)
        }
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

    // MARK: Playlist picker

    @ViewBuilder private func playlistPicker(url: URL, entries: [PlaylistEntry]) -> some View {
        // Precompute done/queued ids once so each of the (potentially 100s of) rows is an O(1) lookup.
        let title = state.savedPlaylists.first { $0.id == SavedPlaylist.listID(for: url) }?.title
        let doneIDs = chosenStyle.map { state.summarizedVideoIDs(inStyle: $0) } ?? []
        let queuedIDs = chosenStyle.map { state.queuedVideoIDs(inStyle: $0) } ?? []
        let doneCount = entries.reduce(0) { doneIDs.contains($1.videoID) ? $0 + 1 : $0 }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { clearAll() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Back to playlists")
                Text(title ?? "Playlist").font(.uiBody.weight(.semibold)).lineLimit(1)
                Spacer()
                Button("Refresh") { refresh(url) }.buttonStyle(GhostButtonStyle())
            }
            HStack(spacing: 10) {
                Text("\(entries.count) videos").font(.uiCaption).foregroundStyle(.secondary)
                Button("All") { selected = Set(entries.map(\.videoID)).subtracting(doneIDs).subtracting(queuedIDs) }
                    .buttonStyle(GhostButtonStyle())
                Button("None") { selected = [] }.buttonStyle(GhostButtonStyle())
                Spacer()
                if doneCount > 0 { Text("\(doneCount) summarized").font(.uiCaption).foregroundStyle(.secondary) }
            }
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    entryRow(entry, done: doneIDs.contains(entry.videoID), queued: queuedIDs.contains(entry.videoID))
                }
            }
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
            footer(entries, doneIDs: doneIDs, queuedIDs: queuedIDs)
        }
    }

    private func entryRow(_ entry: PlaylistEntry, done: Bool, queued: Bool) -> some View {
        let on = selected.contains(entry.videoID)
        return HStack(spacing: 10) {
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if queued {
                Image(systemName: "clock").foregroundStyle(Theme.accent)
            } else {
                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Theme.accent : .secondary)
            }
            Text(String(format: "%03d", entry.index))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Text(entry.title).lineLimit(1).foregroundStyle((done || queued) ? .secondary : .primary)
            Spacer(minLength: 8)
            // Hover-revealed link to watch the video on YouTube.
            Button { openURL(entry.url) } label: { Image(systemName: "play.rectangle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Watch on YouTube")
                .opacity(hoveredVideoID == entry.videoID ? 1 : 0)
                .allowsHitTesting(hoveredVideoID == entry.videoID)
            if done { Text("done").font(.caption).foregroundStyle(.green) }
            else if queued { Text("queued").font(.caption).foregroundStyle(Theme.accent) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredVideoID = hovering ? entry.videoID : (hoveredVideoID == entry.videoID ? nil : hoveredVideoID)
        }
        .onTapGesture {
            guard !done, !queued else { return }
            if on { selected.remove(entry.videoID) } else { selected.insert(entry.videoID) }
        }
    }

    private func footer(_ entries: [PlaylistEntry], doneIDs: Set<String>, queuedIDs: Set<String>) -> some View {
        let pickable = entries.filter {
            selected.contains($0.videoID) && !doneIDs.contains($0.videoID) && !queuedIDs.contains($0.videoID)
        }
        let count = pickable.count
        return HStack(spacing: 10) {
            if youtubeStyles.count > 1 {
                Picker("", selection: Binding(get: { chosenStyleID ?? youtubeStyles.first?.id },
                                              set: { chosenStyleID = $0 })) {
                    ForEach(youtubeStyles) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden().fixedSize()
            } else if let only = youtubeStyles.first {
                Text("Style: \(only.name)").font(.uiCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count) selected · ~\(max(count, 1) * 5)k tok (rough)")
                .font(.uiCaption).foregroundStyle(.secondary).monospacedDigit()
            Button {
                guard let style = chosenStyle else { return }
                state.summarizePlaylist(pickable, style: style)
                clearAll()
            } label: { Text("Summarize \(count)").padding(.horizontal, 12) }
            .buttonStyle(AccentButtonStyle(prominent: true))
            .disabled(count == 0 || !state.hasKey || chosenStyle == nil)
            .opacity((count == 0 || !state.hasKey) ? 0.5 : 1)
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

    private func refresh(_ url: URL) {
        populatedURL = nil   // a deliberate refresh re-defaults the selection (includes new videos)
        if let saved = state.savedPlaylists.first(where: { $0.id == SavedPlaylist.listID(for: url) }) {
            state.refreshSavedPlaylist(saved)
        } else {
            state.fetchPlaylist(url)
        }
    }

    /// Populate the not-done/not-queued default once per loaded playlist; afterward only prune
    /// now-finished/queued videos so manual edits survive a style switch or jobs completing.
    private func recomputeSelection() {
        guard case .loaded(let url, let entries) = state.playlistFetch else { return }
        let blocked: Set<String> = chosenStyle.map {
            state.summarizedVideoIDs(inStyle: $0).union(state.queuedVideoIDs(inStyle: $0))
        } ?? []
        let selectable = Set(entries.map(\.videoID)).subtracting(blocked)
        if populatedURL != url {
            populatedURL = url
            selected = selectable
        } else {
            selected.formIntersection(selectable)   // prune now-finished/queued; keep manual edits
        }
    }

    /// Return to the saved-playlists list: clear the field, local selection, and the shared fetch.
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
