# Feature Specification: Browse the library while a summary streams

**Feature Branch**: `004-streaming-preview-browse`

**Created**: 2026-06-24

**Status**: Draft

**Input**: User description: "When a generation is in process and it starts streaming, I can't then
select items in the asset browser and preview them. Add a 'Streaming... [Watch]' affordance to the
bottom bar (it naturally fits there since there is already a message telling you it is generating).
When you select, the selection takes over the preview; you can then click back to watch the stream."

## Background

When a summary generates, its text streams live into the preview pane so you can "watch it write
itself" (FR-040). That live view is implemented in `PreviewPane.body` as an unconditional branch:

```swift
if state.streamingJobID != nil { streamingView }   // takes over the WHOLE pane while any job streams
else if let asset { ...selected item preview... }
else { placeholder }
```

So for the entire duration of a generation, the preview pane is monopolized by the live stream.
Clicking a library row still updates `state.selectedAsset` (the list itself works), but that
selection is never shown, because the `if` short-circuits to `streamingView`. Space-bar Quick Look
is also gated off during streaming (`guard state.streamingJobID == nil` in the key monitor). Net
effect: you cannot read or preview anything in your library until the current generation finishes.

The bottom bar already shows a live status ("Summarizing N of M...", an animated background, a
Cancel button), so it is the natural, low-clutter home for a control that returns you to the stream.

## Clarifications

### Session 2026-06-24

- Q: Where should the "return to the live stream" control live? -> A: In the **bottom bar**, next to
  the existing generating status, as a **Watch** button. It fits where the "it is generating" message
  already is, and keeps the preview pane uncluttered.
- Q: What shows in the preview pane during a generation, by default? -> A: When a job **begins
  streaming**, the preview defaults to the **live stream** (preserves the current "watch it write
  itself" behavior). The moment the user **selects a library item**, that selection **takes over**
  the preview. Clicking **Watch** in the bottom bar returns the preview to the live stream.
- Q: Concurrent generations? -> A: The queue runs **sequentially** (001 FR), so only one job streams
  at a time. "Watch" always refers to the job that is currently streaming. (No multi-stream UI.)
- Q: Relocate the stream out of the preview pane, or split the pane to show both at once? -> A: **No.**
  The stream stays in the preview pane; it is shown OR the selected item is shown, toggled by
  selection and the bottom-bar Watch control. (Simpler; one area; matches the request.)

## User Scenarios & Testing

### User Story 1 - Read other summaries while one generates (Priority: P1)

A user drops a transcript (or starts a YouTube summary); while it streams, they want to re-read an
earlier summary.

**Why this priority**: This is the reported bug. Today the library is effectively frozen for viewing
until the current job completes.

**Acceptance**:
1. **Given** a job is streaming, **when** the user selects a library item, **then** that item's
   preview replaces the live stream in the preview pane (with its normal toolbar).
2. **Given** the user is previewing a selected item during a generation, **when** they select a
   different item, **then** the preview follows the selection (no stale content).
3. **Given** the user is previewing a selected item during a generation, **when** they press the
   space bar, **then** Quick Look opens for that selected item (today it is blocked while streaming).

### User Story 2 - Return to watching the live stream (Priority: P1)

After browsing away, the user wants to watch the in-progress generation again.

**Why this priority**: The live-streaming preview is a valued feature; leaving it must be reversible.

**Acceptance**:
1. **Given** a job is streaming and the user has selected an item (so the item is shown), **then**
   the bottom bar shows a **Watch** control alongside the generating status.
2. **Given** that Watch control, **when** the user clicks it, **then** the preview pane returns to
   the live stream and resumes auto-scrolling as text arrives.
3. **Given** the user is currently watching the live stream, **then** the Watch control is not
   offered (there is nothing to return to); the bottom bar simply shows the generating status.

### User Story 3 - Sensible defaults at start and finish (Priority: P2)

**Why this priority**: The change must not regress the "watch it write itself" default or the
end-of-generation behavior.

**Acceptance**:
1. **Given** no generation is running, **when** a job **begins streaming**, **then** the preview pane
   defaults to the live stream (unchanged from today).
2. **Given** a generation **completes**, **then** the new summary is auto-selected and previewed and
   the live indicator / Watch control disappears (unchanged end state).
3. **Given** a generation is cancelled or fails, **then** the live stream view and the Watch control
   disappear, and the preview shows the current selection (or the placeholder).

### Edge Cases

- **Pre-stream phases** (extracting / fetching, before any tokens stream): there is nothing to watch
  yet, so the Watch control is absent and the preview shows the current selection or placeholder.
  When the job transitions into streaming, the preview defaults to the stream.
- **Batch**: each job that begins streaming defaults the preview to its stream (the user can break
  away again). Acceptable because the queue is sequential and the prior job has finished.
- **Nothing selected** while browsing away: selecting is the only way to leave the stream, so a
  selection always exists once the user has left it; clicking Watch returns to the stream.
- **Switching to an HTML summary** during a generation behaves exactly like the normal HTML viewer
  (003); no interaction with streaming.

## Requirements

### Functional Requirements

- **FR-053**: While a job is streaming, selecting any library item MUST display that item in the
  preview pane (with its normal toolbar and actions). The live stream MUST NOT unconditionally
  occupy the preview pane.
- **FR-054**: When a job begins streaming, the preview pane MUST default to the live stream
  (preserving "watch it write itself"). Selecting a library item MUST switch the preview to that item
  (leaving live-watch).
- **FR-055**: While a job is streaming, the bottom bar (next to the existing generating status) MUST
  offer a **Watch** control that returns the preview to the live stream. The control is shown only
  when the user is not currently watching the stream.
- **FR-056**: Preview interactions for the selected item MUST work while a generation runs and that
  item is being previewed: space-bar Quick Look (currently blocked) and the existing toolbar actions
  (font size, regenerate, open, reveal, copy, delete, and for HTML the View-in-Browser button).
- **FR-057**: On completion, cancellation, or failure, the live stream view and the Watch control
  MUST clear; on completion the new summary remains auto-selected and previewed (unchanged).

### Out of scope (this feature)

- Relocating the live stream out of the preview pane (e.g., a floating inspector or the main panel).
- A simultaneous split view showing the stream and a selected item at the same time.
- Multiple concurrent live streams (the queue is sequential).

## Success Criteria

- **SC-001**: During an active generation, a user can select and fully read any library item, then
  return to the live stream in one click, with no wait for the job to finish.
- **SC-002**: The "watch it write itself" default at stream start and the auto-select-on-completion
  behavior are unchanged.
- **SC-003**: `swift build` is clean (0 warnings) and `swift test` is green. No new dependency.
- **SC-004**: No regression to streaming, cancel, retry, the bottom-bar status, or other previews.
