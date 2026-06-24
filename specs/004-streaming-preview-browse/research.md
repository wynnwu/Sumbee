# Research & Decisions: Browse the library while a summary streams

Decisions are lettered `D-A...` to stay local to this feature.

## D-A. One new piece of state: `watchingStream`

The behavior is a two-way toggle between "show the live stream" and "show the selected item" during
a generation. The cleanest model is a single published flag on `AppState`:

```swift
@Published public var watchingStream: Bool = false
```

The preview pane shows the live stream only when **both** a job is streaming **and** the user is
watching:

```swift
if state.streamingJobID != nil && state.watchingStream { streamingView }
else if let asset { ...selected item... }
else { placeholder }
```

- **Set true** when a job begins streaming (`streamingText = ""; streamingJobID = job.id` in
  `AppState+Jobs`), so the stream is the default view at start (FR-054).
- **Set false** when the user selects a library item, so selection takes over (FR-053).
- **Set true** by the bottom-bar **Watch** button (FR-055).
- Reset to false whenever streaming stops (`clearStreaming`), so the flag is clean for next time
  (display already falls back because `streamingJobID` becomes nil).

Rejected: deriving the mode implicitly (e.g., "show stream unless selection changed since stream
start") - that needs timestamps/extra bookkeeping and is harder to reason about than one boolean.

## D-B. Distinguish *user* selection from *programmatic* selection

Selecting an item must leave watch-mode, but the completion handler also sets
`selectedAsset = asset` programmatically (to auto-show the finished summary), and that must NOT be
treated as "user navigated away" (it happens as streaming ends anyway).

- The library list's selection `Binding.set` is invoked **only** by user interaction (click / arrow
  keys); programmatic `state.selectedAsset = ...` bypasses it. So the user-selection hook lives
  there.
- To keep this testable and centralized, add `AppState.selectAsset(_:)` that sets `selectedAsset`
  and clears `watchingStream`, and have the list binding call it. The completion path keeps assigning
  `selectedAsset` directly (no watch change needed; streaming is ending).

## D-C. The Watch control lives in the bottom bar's existing status block

`BottomBarView` already renders, when `state.statusLine != nil`, a spinner + the status text + a
`Cancel` button for the running job. `statusLine` is non-nil whenever a job is running (it reads
`currentJobID`). The **Watch** button slots in next to `Cancel`, shown only when
`state.streamingJobID != nil && !state.watchingStream` (there is a live stream and the user is not
already watching it). It calls a tiny `AppState.watchStream()` that sets `watchingStream = true`
when a stream exists.

- Styling: reuse `GhostButtonStyle` (same as `Cancel` / `Run queue`) for consistency.
- When the user is already watching, the button is absent (FR-055.3); the animated bar + status text
  already communicate "streaming".

## D-D. Re-enable Quick Look (and confirm other actions) during a generation

The space-bar monitor currently bails while any job streams
(`guard state.streamingJobID == nil`). Replace that with a guard that only blocks Quick Look while
the live stream is actually on screen:

```swift
guard !(state.streamingJobID != nil && state.watchingStream),
      let url = state.selectedAsset?.url else { return event }
```

The other toolbar actions (font size, regenerate, open, reveal, copy, delete, View-in-Browser) are
rendered by the selected-item branch, so they become available automatically once that branch shows
during streaming (FR-056). No further change needed for them.

## D-E. Optional polish: name the streaming item

Today the live header says only "Generating...". Showing the job's title ("Generating <title>...")
in the stream header and/or the bottom-bar status is a small nicety. Treated as optional (it does
not affect the toggle behavior); include only if it is a clean one-liner from the streaming job.

## Risks

- **Cannot launch locally** (ad-hoc signing -> Keychain prompt; learnings #3/#4). Verify via
  `swift build` + `swift test`; the change is a few state transitions plus view conditions, validated
  by the user from the build. Keep the state transitions in `AppState` methods so they are unit
  testable without the UI where practical.
- **Auto-watch at each stream start in a batch** could feel like it "pulls" focus. Accepted per
  FR-054 (sequential queue; predictable default); revisit only if it proves annoying.
