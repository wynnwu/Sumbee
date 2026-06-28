# Tasks: playlist summarize (YouTube mode)

**Input**: `spec.md`, `research.md`, `plan.md`
**Tests**: parse / validate / dedup are unit-tested; the rail + picker wiring is reviewed (adversarial)
and validated by the user from the build (live YouTube is IP-specific; no app launch - Keychain).

## Phase 1: Models
- [x] T001 [P] `Models/InputMode.swift`: enum `transcripts`/`youtube` (`displayName`, `icon`, raw values).
- [x] T002 [P] `Models/PlaylistEntry.swift`: `struct {index,id,title,url}` (Identifiable, Equatable, Sendable).

## Phase 2: Service (enumeration)
- [x] T003 `Services/YouTubeService.swift`: `static validatePlaylist(urlString:) -> URL?`;
      `static parseFlatPlaylist(_:) -> [PlaylistEntry]` (split on `|||`, drop bad/`NA` lines);
      `fetchPlaylist(_:authMode:ytDlp:)` running `--flat-playlist --print "…|||…|||…|||…"` off-actor.

## Phase 3: State + enqueue
- [x] T004 `State/AppState.swift`: `@Published var inputMode`; `PlaylistFetch` enum +
      `@Published var playlistFetch`; `isVideoSummarized(id:inStyle:)`.
- [x] T005 `State/AppState+Jobs.swift`: `fetchPlaylist(_:)` (locate yt-dlp, loading→loaded/failed);
      `summarizePlaylist(_:style:)` (requireKey, batch-append YouTube jobs, startProcessing, toast).

## Phase 4: UI
- [x] T006 [P] `Views/MainPanel/ModeRailView.swift`: thin left rail, two items, accent-highlight active.
- [x] T007 `App/ContentView.swift`: wrap the split in `HStack { ModeRailView; HSplitView{...} }`.
- [x] T008 `Views/MainPanel/MainPanelView.swift`: body switches on `inputMode` (Transcripts =
      file styles; YouTube = `YouTubeModePanel`); remove the always-on youtube section.
- [x] T009 `Views/MainPanel/YouTubeModePanel.swift`: URL field; single-video buttons (as today) OR
      playlist Fetch → checklist (Select all/None, dedup-dimmed done rows, count + estimate) → style
      pick → Summarize.

## Phase 5: Verify & document
- [x] T010 [P] `Tests/SumbeeKitTests/PlaylistTests.swift`: parseFlatPlaylist, validatePlaylist,
      isVideoSummarized, InputMode default/raw values.
- [x] T011 `swift build` clean (0 warnings) + `swift test` green (82 existing + new); no new dependency.
- [x] T012 Adversarial review (workflow) of enqueue/dedup/mode/library wiring; fix findings.
- [x] T013 `./scripts/bundle.sh` builds the `.app`; update `CHANGELOG.md` + README.
- [x] T014 Commit, push, open PR for user validation.

---
**Checkpoint**: thin rail switches Transcripts/YouTube; a playlist fetches, trims (done excluded), and
summarizes the selection through a YouTube style via the existing queue; Transcripts + single-video
unchanged; build + tests green; bundle builds; PR open.
