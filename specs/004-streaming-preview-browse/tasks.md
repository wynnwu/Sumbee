# Tasks: Browse the library while a summary streams

**Input**: `spec.md`, `research.md`, `plan.md`
**Tests**: Light. State transitions unit-tested if `AppState` is constructible in tests; the view
wiring is reviewed and validated by the user from the build (no app launch; Keychain, learnings #3/#4).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency)
- **[Story]**: US1 (browse during stream), US2 (return to stream), US3 (defaults at start/finish)

---

## Phase 1: State (foundational)

- [x] T001 [US1][US2] `State/AppState.swift`: add `@Published public var watchingStream: Bool = false`;
      add `func selectAsset(_ asset: Asset?)` (sets `selectedAsset`, clears `watchingStream`); add
      `func watchStream()` (sets `watchingStream = true` only when `streamingJobID != nil`).
- [x] T002 [US3] `State/AppState+Jobs.swift`: set `watchingStream = true` at stream start (beside
      `streamingText = ""; streamingJobID = job.id`); set `watchingStream = false` in
      `clearStreaming(_:)` where it nils `streamingJobID`.

## Phase 2: Preview pane

- [x] T003 [US1] `Views/AssetBrowser/MarkdownPreview.swift`: change the body stream condition to
      `state.streamingJobID != nil && state.watchingStream`; so a selected item shows during a
      generation when not watching.
- [x] T004 [US1] `Views/AssetBrowser/MarkdownPreview.swift`: update the space-bar monitor guard to
      `!(state.streamingJobID != nil && state.watchingStream)` so Quick Look works for the selected
      item during a generation (FR-056).
- [x] T005 [P][US1] (Optional, D-E) `MarkdownPreview.swift`: show the streaming job's title in the
      live header ("Generating <title>...") if cleanly available; skip if it adds plumbing.

## Phase 3: Selection + bottom bar

- [x] T006 [US1] `Views/AssetBrowser/AssetBrowserView.swift`: the `List(selection:)` `Binding.set`
      calls `state.selectAsset(resolved)` instead of assigning `state.selectedAsset` directly.
- [x] T007 [US2] `Views/BottomBar/BottomBarView.swift`: in the running status block (next to
      `Cancel`), add a **Watch** `GhostButtonStyle` button shown when
      `state.streamingJobID != nil && !state.watchingStream`, calling `state.watchStream()`.

## Phase 4: Verify & document

- [x] T008 [US3] `WatchModeTests.swift` (if `AppState` is constructible in tests): assert
      `watchStream()` no-ops without a stream and sets the flag with one; `selectAsset(_:)` clears
      `watchingStream`. Otherwise record manual validation only.
- [x] T009 `swift build` clean (0 warnings) + `swift test` green; confirm no new dependency.
- [x] T010 [P] Update `CHANGELOG.md` (next/Unreleased) and the README "Live streaming preview" bullet.
- [x] T011 Manual validation pass (see plan "Manual validation") captured in the PR description.

---

**Checkpoint**: During a generation, the user can browse/preview and Quick Look library items, and
return to the live stream via the bottom-bar **Watch**; start/finish defaults unchanged; build +
tests green.

## Suggested commit / PR shape

One focused change on a `004-streaming-preview-browse` branch (state + 4 view edits + optional test +
docs), opened as a PR for the user to validate, consistent with 003. Commit/push/PR only when asked.
