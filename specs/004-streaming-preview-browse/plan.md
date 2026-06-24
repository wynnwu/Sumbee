# Implementation Plan: Browse the library while a summary streams

**Spec**: `spec.md`  ·  **Decisions**: `research.md`  ·  **Tasks**: `tasks.md`

## Summary

Stop the live stream from monopolizing the preview pane. Add one published flag
(`watchingStream`), gate the stream view on it, let user selection clear it, and add a **Watch**
button in the bottom bar to set it. Re-enable space-bar Quick Look for the selected item during a
generation. No new dependency; no model/persistence changes.

## Architecture & touch points

```
Sources/SumbeeKit/
  State/
    AppState.swift            # EDIT  + @Published watchingStream; + selectAsset(_:); + watchStream()
    AppState+Jobs.swift       # EDIT  set watchingStream=true at stream start; =false in clearStreaming
  Views/AssetBrowser/
    MarkdownPreview.swift     # EDIT  PreviewPane.body stream condition; space-monitor guard; (opt) title
    AssetBrowserView.swift    # EDIT  list selection Binding.set -> state.selectAsset(...)
  Views/BottomBar/
    BottomBarView.swift       # EDIT  add "Watch" button in the status block
Tests/SumbeeKitTests/
    WatchModeTests.swift      # NEW (if AppState is constructible in tests) state-transition tests
```

No changes to models, services, persistence, the job engine's behavior, or the streaming buffer.

## Component contracts

### `AppState` (state + intent methods)

```swift
@Published public var watchingStream: Bool = false

/// User picked a library item: show it, leave live-watch. (Called from the library list only.)
public func selectAsset(_ asset: Asset?) {
    selectedAsset = asset
    watchingStream = false
}

/// Bottom-bar "Watch": return to the live stream (no-op if nothing is streaming).
public func watchStream() {
    if streamingJobID != nil { watchingStream = true }
}
```

### `AppState+Jobs` (defaults at start / clear at stop)

- At stream start (where `streamingText = ""; streamingJobID = job.id`): also `watchingStream = true`
  (FR-054, "watch it write itself" default).
- In `clearStreaming(_:)` (the single funnel for done/cancel/fail/retry): when it nils
  `streamingJobID`, also set `watchingStream = false` (FR-057). Display already falls back via the
  nil `streamingJobID`; this keeps the flag tidy.

### `PreviewPane` (MarkdownPreview.swift)

- Body condition:
  ```swift
  if state.streamingJobID != nil && state.watchingStream { streamingView }
  else if let asset { toolbar + preview }
  else { placeholder }
  ```
- Space monitor guard (FR-056):
  ```swift
  guard !(state.streamingJobID != nil && state.watchingStream),
        let url = state.selectedAsset?.url else { return event }
  ```
- Optional (D-E): stream header shows the streaming job's title if cleanly available.

### `AssetBrowserView` (library list)

- The `List(selection:)` `Binding.set` currently does `state.selectedAsset = resolved`. Change to
  `state.selectAsset(resolved)` so user selection also clears `watchingStream` (D-B).

### `BottomBarView` (Watch control)

- Inside the `if let line = state.statusLine { ... }` running block, next to the `Cancel` button, add:
  ```swift
  if state.streamingJobID != nil && !state.watchingStream {
      Button("Watch") { state.watchStream() }
          .buttonStyle(GhostButtonStyle())
          .help("Return to the live generation in the preview")
  }
  ```

## Testing

- **Unit (if feasible)**: `WatchModeTests` over `AppState` transitions that do not require a live job:
  - `watchStream()` is a no-op when `streamingJobID == nil`; sets `watchingStream` when a stream id
    is present.
  - `selectAsset(_:)` sets `selectedAsset` and clears `watchingStream`.
  - If constructing `AppState` in a test is impractical (it wires services/Keychain), skip and rely
    on manual validation, mirroring how 003's `WKWebView` view was review-only. Decide during T-impl.
- **Build/verify**: `swift build` (0 warnings), `swift test` green. No app launch (Keychain;
  learnings #3/#4) - user validates the interaction from the build.
- **Manual validation** (for the PR description): during a generation, (1) select an item -> it shows;
  (2) space bar Quick Looks it; (3) bottom bar shows **Watch**; (4) click Watch -> stream returns and
  auto-scrolls; (5) on completion the new summary is selected and the Watch control is gone.

## Risks & mitigations

- *No local visual check*: keep the logic in `AppState` methods (testable, reviewable); the view
  edits are small and mechanical.
- *Focus pull on batch stream starts*: accepted per FR-054; revisit if annoying.

## Rollback

Self-contained: revert the `watchingStream` flag, the two `AppState` methods, and the four small view
/ job edits. No persistence or format changes.

## Docs to update on completion

- `CHANGELOG.md` (next/Unreleased).
- `README.md` "Live streaming preview" bullet (note you can browse the library while it streams and
  return via the bottom-bar Watch).
- Keep `specs/004-streaming-preview-browse/*` current (this set).
