# Implementation Plan: playlist summarize (YouTube mode)

**Spec**: `spec.md` · **Decisions**: `research.md` · **Tasks**: `tasks.md`

## Touch points
```
Sources/SumbeeKit/
  Models/
    InputMode.swift           # NEW  enum transcripts/youtube (displayName, icon)
    PlaylistEntry.swift       # NEW  struct {index,id,title,url}
  Services/
    YouTubeService.swift      # EDIT + validatePlaylist(_:) ; + fetchPlaylist(...) ; + parseFlatPlaylist(_:)
  State/
    AppState.swift            # EDIT + @Published inputMode ; + @Published playlistFetch ;
                              #       + isVideoSummarized(id:inStyle:)
    AppState+Jobs.swift       # EDIT + fetchPlaylist(_:) ; + summarizePlaylist(_:style:) (batch enqueue)
  App/
    ContentView.swift         # EDIT wrap split in HStack { ModeRailView; HSplitView{...} }
  Views/MainPanel/
    ModeRailView.swift        # NEW  thin left rail (Transcripts / YouTube)
    MainPanelView.swift       # EDIT body switches on inputMode; YouTube section moves into YouTube mode
    YouTubeModePanel.swift    # NEW  URL input + single-video buttons + playlist fetch/picker
Tests/SumbeeKitTests/
    PlaylistTests.swift       # NEW  parseFlatPlaylist, validatePlaylist, dedup, InputMode default
```

## Contracts
```swift
// Models
enum InputMode: String, CaseIterable, Identifiable, Sendable { case transcripts, youtube ; var displayName; var icon }
struct PlaylistEntry: Identifiable, Equatable, Sendable { let index:Int; let id:String; let title:String; let url:URL }

// YouTubeService
static func validatePlaylist(urlString:) -> URL?            // /playlist?list=… on a known host
static func parseFlatPlaylist(_ stdout: String) -> [PlaylistEntry]   // "idx|||id|||title|||url" lines
func fetchPlaylist(_ url: URL, authMode: YouTubeAuthMode, ytDlp: URL) async throws -> [PlaylistEntry]

// AppState
@Published var inputMode: InputMode = .transcripts
enum PlaylistFetch: Equatable { case idle, loading(URL), loaded(URL,[PlaylistEntry]), failed(String) }
@Published var playlistFetch: PlaylistFetch = .idle
func fetchPlaylist(_ url: URL)                              // sets .loading → .loaded/.failed
func summarizePlaylist(_ entries: [PlaylistEntry], style: SummaryStyle)   // batch-enqueue YouTube jobs
func isVideoSummarized(id: String, inStyle style: SummaryStyle) -> Bool   // dedup over library
```

- `fetchPlaylist`: locate yt-dlp (`youtube.locate`), guard missing tool, set `.loading`, run off-actor,
  set `.loaded`/`.failed` (reuse `YouTubeError.userMessage`).
- `summarizePlaylist`: `requireKey()`; for each entry append `Job(input:.youtube(entry.url), …, styleID/styleName)`;
  `startProcessing()`. Bypasses geek-mode preview (batch), like multi-file drops. Toast "Queued N videos."
- `isVideoSummarized`: any `library` asset under `style.name` whose `sourceRef` contains the id.

## UI
- `ModeRailView`: vertical, fixed ~74pt, two items (📄 Transcripts / 🎬 YouTube), active highlighted in
  accent; sets `state.inputMode`.
- `MainPanelView`: `if inputMode == .transcripts { fileStylesSection } else { YouTubeModePanel() }`.
- `YouTubeModePanel`: URL field; if `validatePlaylist` → show Fetch + (on `.loaded`) the checklist with
  Select all/None, dedup-dimmed "done" rows, count + estimate, a YouTube-style picker, and Summarize;
  else if `validate` (single video) → the existing per-style buttons; else hint. Reuses Theme/glass.

## Testing
- `PlaylistTests`: `parseFlatPlaylist` (well-formed, ragged lines, NA fields); `validatePlaylist`
  (playlist URL yes; bare video no; junk no); `isVideoSummarized` (seed `library` with a matching
  asset); `InputMode` default + raw values.
- `swift build` 0 warnings, `swift test` green (existing 82 + new). No new dependency. `bundle.sh` builds.
- Adversarial review (workflow) of enqueue/dedup/mode wiring; fix findings. No app launch (Keychain).

## Rollback
Additive: new files + an `inputMode` switch. Removing the rail + reverting `ContentView`/`MainPanelView`
restores today's single-panel layout; no persistence/format change.

## Docs on completion
`CHANGELOG.md` (Unreleased), README (YouTube → playlists), keep `specs/007-*` current.
