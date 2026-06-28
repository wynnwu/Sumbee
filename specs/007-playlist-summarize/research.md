# Research & Decisions: playlist summarize (YouTube mode)

## D-A. Enumeration via `yt-dlp --flat-playlist` (proven)
`yt-dlp --flat-playlist --print "%(playlist_index)s|||%(id)s|||%(title)s|||%(url)s" <url>` lists a
playlist in one request, no download, no extra dependency. Verified live on a 102-video unlisted
playlist (clean `index|id|title|url`, `url` is the canonical watch URL the existing jobs accept).
Private playlists reuse the YouTube **auth mode** (005): `authMode.ytDlpArgs` already appends
`--cookies-from-browser …`. Unlisted needs nothing.

- New `YouTubeService.fetchPlaylist(url:authMode:ytDlp:) -> [PlaylistEntry]` runs flat-playlist off
  the main actor (like `fetchTranscript`), then `parseFlatPlaylist(_:) -> [PlaylistEntry]` (pure,
  unit-tested) splits each line on `|||` (same delimiter as `parseMeta`).
- New `YouTubeService.validatePlaylist(urlString:) -> URL?` (pure static): accepts the known YouTube
  hosts with path `/playlist` and a `list` query item. `watch?v=…&list=…` is treated as a single
  video (existing `validate`), not a playlist, in v1.

## D-B. Mode rail = surface the existing `StyleChannel` split
Styles are already `.file` vs `.youtube` (`state.fileStyles` / `state.youtubeStyles`). A thin left
rail just chooses which to show. Add `AppState.inputMode: InputMode` (`.transcripts` / `.youtube`,
session state, default `.transcripts`).

- `ContentView`: wrap the existing split in an `HStack { ModeRailView(); HSplitView { MainPanelView;
  AssetBrowserView } }`. The rail is fixed-width (~74pt), global nav.
- `MainPanelView`: keep the header + key-gate; switch the body on `inputMode` - Transcripts shows the
  current `fileStylesSection`; YouTube shows the new `YouTubeModePanel` (which absorbs the old
  always-on `youtubeSection`). The standalone `youtubeSection` no longer shows in Transcripts mode.

## D-C. Playlist UI + enqueue
- `AppState` holds the fetch result so the view reacts: `@Published var playlistFetch: PlaylistFetch`
  (`.idle` / `.loading(URL)` / `.loaded(url, [PlaylistEntry])` / `.failed(String)`), plus
  `fetchPlaylist(_ url:)` and `summarizePlaylist(_ entries:style:)`.
- **Selection** lives in `YouTubeModePanel` as `@State Set<String>` of video ids; default = all
  entries that are NOT already summarized for the chosen style (dedup, D-D). Select all / None mutate
  it.
- **Enqueue** appends one YouTube `Job` per selected entry directly (a batch bypasses geek-mode
  preview, exactly like multi-file drops), then `startProcessing()`. Individual failures are isolated
  by the existing queue. No `processQueue` changes; existing `--sleep-requests`/retry/backoff pace it.

## D-D. Dedup against existing summaries
A YouTube summary records its source URL (`Asset.sourceRef` = the video URL; from
`prepareYouTube`). `AppState.isVideoSummarized(id:inStyle:) -> Bool` scans `library` for an asset in
that style's folder whose `sourceRef` contains the video id. Pure-ish over `library`, unit-testable
by setting `state.library`.

## D-E. Library stays global
The rail switches input only; the library shows all summaries (matches Sumbee's "one library you
own" ethos). An optional `All / Files / YouTube` origin filter is noted as a future enhancement, not
built here.

## D-F. Estimate (honest, cheap)
We do not fetch transcripts up front. The picker shows the **selected count** and a rough,
clearly-labeled token estimate via a per-video heuristic constant (no fake dollar figure). The exact
per-job token count still appears in geek mode for single videos.

## Risks
- Live YouTube is IP-specific and can't be exercised in CI; the parse/validate/dedup logic is
  unit-tested, the wiring is reviewed (adversarial) and validated by the user from the build.
- Big batches can hit the bot gate; mitigated by existing throttling + (once 006 merges) the
  auto-escalation. Not this feature's job to change the queue.
