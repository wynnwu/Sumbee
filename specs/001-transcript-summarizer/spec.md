# Feature Specification: Transcript & Video Sumbee

**Feature Branch**: `001-transcript-summarizer`

**Created**: 2026-06-20

**Status**: Draft

**Input**: User description: "macOS app that turns meeting/interview transcripts and YouTube videos into saved Markdown summaries using configurable prompt styles." Full source requirements: `REQUIREMENTS.md`.

## Clarifications

### Session 2026-06-20

The source `REQUIREMENTS.md` arrived with its open questions already resolved (its §16
decision log). One additional high-impact decision was raised and resolved with the
user before planning; the rest are confirmations of source decisions:

- Q: Should the product be a true native macOS app or a cross-platform web shell, given
  the emphasis on a glass aesthetic and native feel? → A: **Native macOS app.** The
  user explicitly prioritized an elegant, glass, futuristic, native-feeling UI and a
  real built `.app`; native materials/vibrancy deliver this directly. (This is a HOW
  detail captured here only because it was an explicit user decision; mechanics live in
  `plan.md`.)
- Q: Output format default? → A: Markdown by default, HTML opt-in (source §16.1).
- Q: Where do style prompts live and what survives a rename? → A: Inside each style's
  own library folder, tracked by a stable id across renames (source §16.2).
- Q: Caption language default and source preference? → A: English; human-authored subs
  preferred over auto-generated (source §16.3).
- Q: Batch concurrency for multiple dropped files? → A: Sequential in v1 (source §16.5).
- Q: Minimum OS and distribution posture? → A: macOS 15 (Sequoia); local/personal
  unsigned build for v1, signing/notarization deferred (source §16.6).

No [NEEDS CLARIFICATION] markers remain; `/speckit-clarify` produced no blocking
questions for this feature.

### Session 2026-06-21 (Revision 2 - reliability, drop UX, live models)

Three follow-up changes, added as FR-021..FR-023 below:

- **Resilient retry queue (FR-021).** Transient/environmental failures (no internet,
  the model not being available, or a VPN routing through a country that doesn't permit
  the model, plus rate limits and overload) must not kill a job. Jobs retry
  automatically with exponential backoff capped at 5 minutes, and the user can trigger a
  manual "Run queue" to retry immediately (e.g. after fixing their connection/VPN).
- **Square drop tiles (FR-022).** File-style targets render as a grid of square tiles
  with dotted borders; hovering a *valid* file type turns the border solid orange with an
  outer glow and lifts the tile slightly.
- **Live model list (FR-023).** The model picker is populated from the models actually
  available on the Anthropic account (`GET /v1/models`), falling back to the built-in
  presets when offline or before a key is set.

### Session 2026-06-21 (Revision 3 - UI refinement)

Small UX/visual refinements, added as FR-024..FR-028 below:

- **Switchable model in the bottom bar (FR-024).** The bottom-bar model control is a menu
  that switches the active model directly.
- **Library tabs + one-line rows (FR-025).** The library navigator separates "Summaries"
  and "Source" into tabs (source isn't always visible); each row is a single line with the
  title on the left and the date-time on the right.
- **Datetime-prefixed source names (FR-026).** Archived source filenames are prefixed (not
  suffixed) with the datetime so they sort chronologically.
- **Futuristic-minimal visual language (FR-027).** Square edges (sharp corners) on panels,
  layouts, and borders; larger base fonts and icons; drop tiles show a large, left-aligned,
  faded style name (no helper text) that emphasizes on valid-type hover.
- **Lively summarizing animation (FR-028).** During active summarization the whole bottom
  bar comes alive with a colorful animated treatment.
- **Control labels & polish (refines FR-024/025/027).** A larger base font across the whole
  app; the bottom-bar controls carry text labels ("Model", "Output"); the output options read
  "Markdown" and "HTML Webpage"; model lists are sorted alphabetically; and the YouTube action
  is a right-aligned, generously-padded button labeled "Summarize YouTube Video".

## User Scenarios & Testing *(mandatory)*

A single desktop app with one window. The left side offers ways to start a summary
(drop a file onto a style, or paste a video link and pick a style). The right side
is a live browser of everything that has been saved. Settings (reached from a gear)
hold the secret key, generation options, the library location, and the editable
styles. Each "style" is just a named, user-editable prompt that also names a folder
in the library.

### User Story 1 - Summarize a dropped transcript into a saved file (Priority: P1)

A user drags one or more transcript files onto a style's drop zone (or clicks it to
pick files) and receives, for each file, a clean structured summary saved as a file
in that style's library folder, with the original safely archived.

**Why this priority**: This is the core value and the MVP. If only this works, the
app is already useful: drop a transcript, get a saved summary you own.

**Independent Test**: With a valid key set and at least one file style configured,
drop a `.txt`/`.md`/`.pdf`/`.docx`/`.rtf` transcript onto a style; verify a Markdown
summary file appears in that style's folder, named by date + a generated title, with
metadata linking to an archived copy of the original, and that progress and a cancel
control were shown while it ran.

**Acceptance Scenarios**:

1. **Given** a valid key and a configured file style, **When** the user drops a
   supported transcript file onto that style, **Then** the app extracts the text,
   archives a copy of the original, produces a summary in the configured format, and
   saves it to the style's folder named `YYYY-MM-DD HHmm - <Title>.md`.
2. **Given** several files dropped at once, **When** processing runs, **Then** each
   file becomes its own queued job and its own saved summary, and one file failing
   does not abort the others.
3. **Given** an unsupported file type is dropped, **When** the drop occurs, **Then**
   the app rejects it with a clear inline message and starts no job.
4. **Given** no key is stored, **When** the app launches, **Then** it opens to
   Settings and summarization is disabled with a "set your key to begin" state.
5. **Given** a file with no extractable text (e.g. a scanned PDF), **When** extraction
   runs, **Then** the app reports a clear "no extractable text" error and makes no
   summarization call.

---

### User Story 2 - Summarize a YouTube video from its captions (Priority: P2)

A user pastes a YouTube URL, presses a style button, and receives a saved summary
generated from the video's captions, with the cleaned transcript archived and the
original URL recorded.

**Why this priority**: A distinct, high-value input path that reuses the same
summarize-and-save pipeline; valuable but secondary to file summarization and
dependent on an external caption tool.

**Independent Test**: With a valid key and the caption tool available, paste a valid
watch URL and press a YouTube style button; verify a summary file appears in that
style's folder, the cleaned transcript is archived, and the URL is recorded in the
summary's metadata.

**Acceptance Scenarios**:

1. **Given** a valid YouTube URL and an available caption tool, **When** the user
   presses a YouTube style button, **Then** the app fetches captions, cleans them
   into a transcript, summarizes with that style, and saves the result.
2. **Given** an invalid or empty URL, **When** the user looks at the YouTube section,
   **Then** the style buttons are disabled with a hint.
3. **Given** a video has no captions (or is private/region-locked/live), **When** the
   user requests a summary, **Then** the app reports a specific, friendly failure and
   saves nothing.
4. **Given** the caption tool is missing or outdated, **When** the user requests a
   summary, **Then** the app explains the situation and offers a way to install or
   update it, while the rest of the app remains usable.

---

### User Story 3 - Create and edit summary styles (Priority: P2)

A user adds, edits, reorders, enables/disables, and deletes summary styles in
Settings. A style has a name, a channel (file drop zone vs. video button), and an
editable prompt. Changes are reflected immediately in the main window.

**Why this priority**: Styles are the product's core configurability; useful defaults
ship seeded, but the ability to tailor prompts is what makes the tool personal.

**Independent Test**: In Settings, create a new file style with a custom prompt;
verify a new drop zone appears in the main window and a corresponding folder is
created in the library; rename it and verify the folder and existing summaries move
with it; delete it and verify the style disappears but its saved summaries remain.

**Acceptance Scenarios**:

1. **Given** Settings is open, **When** the user creates a style with a name, channel,
   and prompt, **Then** a matching drop zone or button appears and a library folder is
   scaffolded for it.
2. **Given** an existing style, **When** the user renames it, **Then** its folder is
   renamed and its existing summaries stay attached to it.
3. **Given** an existing style, **When** the user deletes it, **Then** it stops
   appearing as a style but its folder and saved summaries are preserved (after a
   warning).
4. **Given** the user chooses "reset to defaults", **When** confirmed, **Then** the
   seeded styles are restored.
5. **Given** a user edits a style's prompt file directly on disk, **When** the app
   next scans the library, **Then** the change is picked up.

---

### User Story 4 - Browse and manage the saved library (Priority: P3)

A user browses saved summaries organized by style, previews them, and acts on them
(reveal in Finder, open externally, copy, delete). The view stays in sync with the
folder on disk.

**Why this priority**: Improves the experience of living with the output, but the
core promise (files you own in a folder) is already met by US1/US2 even without an
in-app browser.

**Independent Test**: After producing several summaries, confirm they appear grouped
by style, newest first; select one and preview it; reveal it in Finder; delete one in
Finder and confirm the in-app list updates.

**Acceptance Scenarios**:

1. **Given** saved summaries exist, **When** the user opens the browser, **Then**
   summaries are grouped by style folder, sorted newest first, with a `source` group
   for archived originals.
2. **Given** a summary is selected, **When** the user chooses an action, **Then**
   reveal-in-Finder, open-externally, copy, and delete all work; a read-only preview
   is available.
3. **Given** a file changes on disk (added/removed in Finder), **When** that happens,
   **Then** the in-app list reflects it without a manual refresh.

---

### Edge Cases

- Input larger than the model's context window: the user is warned; v1 may truncate
  with an explicit notice rather than failing silently.
- Empty extraction (no text found): error, no summarization call.
- Title collisions in the same folder: a numeric suffix is appended; nothing is
  overwritten.
- Folder renamed in Finder while the app runs: the style stays attached via its
  stable identifier; summaries are not lost.
- Authentication failure mid-use: the app re-gates to Settings and explains why.
- Rate limiting / service overload: the app backs off and retries with a notice
  rather than failing outright.
- Offline: browsing and opening existing summaries works; summarization and caption
  fetching fail gracefully with clear messaging.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST present file-style targets as drop zones accepting
  `.md`, `.docx`, `.pdf`, `.txt`, `.rtf` (single or multiple), and reject unsupported
  types with a clear message; clicking a zone MUST offer a file picker.
- **FR-002**: The app MUST extract readable plain text from each supported format and,
  when no text can be extracted, report a clear error and make no summarization call.
- **FR-003**: Before summarizing, the app MUST archive a copy of each original input
  into a `source` area, date-stamped, never moving the user's original.
- **FR-004**: The app MUST summarize using the selected style's prompt plus a shared
  output convention, streaming progress and allowing cancel.
- **FR-005**: The app MUST save each summary to the style's folder using a date-time +
  generated-title filename in the chosen output format, with metadata linking back to
  the archived source (or video URL).
- **FR-006**: The app MUST process multiple dropped files as independent queued jobs
  where one failure does not abort the batch.
- **FR-007**: The app MUST accept a YouTube URL, validate it, fetch captions via an
  external tool, clean them into a transcript, archive the transcript, and summarize
  with the chosen video style, recording the source URL in metadata.
- **FR-008**: The app MUST clearly handle YouTube failure modes (no captions,
  private/region/live, network failure, missing/outdated tool) without crashing or
  aborting other work.
- **FR-009**: The app MUST let users fully manage styles (create, edit name/channel/
  prompt, reorder, enable/disable, delete, reset-to-defaults), persisting each style's
  prompt and metadata inside its own library folder so the library is self-describing
  and rename-safe.
- **FR-010**: Renaming a style MUST move its folder and keep existing summaries
  attached; deleting a style MUST preserve its folder and summaries (after a warning).
- **FR-011**: The app MUST require an Anthropic API key before any summarization,
  store it securely, validate it on request, and re-gate automatically on an
  authentication failure; a remove-key action MUST exist.
- **FR-012**: The app MUST never expose the API key in config files, logs, summaries,
  or any visible surface.
- **FR-013**: The app MUST expose generation options (model, with presets plus a custom
  value, defaulting to the latest most-capable model; output length; faithfulness
  control; and any reasoning/effort control), showing only the controls the chosen
  model actually supports.
- **FR-014**: The app MUST let the user choose the library root folder, show the
  active path, reveal it in Finder, and validate writability; changing it MUST not
  move existing files.
- **FR-015**: The app MUST offer Markdown (default) or HTML output globally, with an
  optional shared HTML-styling prompt applied to all HTML output.
- **FR-016**: The app MUST instruct the model to begin each summary with a single
  title heading, parse that title for the filename, and fall back to the source name
  if absent.
- **FR-017**: The app MUST browse the library grouped by style (plus a source group),
  newest first, with reveal/open/copy/delete actions and a read-only preview, staying
  in sync with on-disk changes.
- **FR-018**: The app MUST keep the window responsive during jobs, show job status in
  a status area, and surface errors as dismissible notices.
- **FR-019**: The app MUST clearly state its privacy boundary: transcript text and
  prompts go to the summarization service; caption fetching goes to the video host;
  nothing else leaves the machine.
- **FR-020**: The app MUST seed a set of default styles on first run (general meeting,
  product-review to-dos, short interview scorecard, long interview debrief, and a
  YouTube summary) and allow restoring them.
- **FR-021**: On transient/environmental failures (no network, model unavailable,
  region/VPN access blocked, rate limit, overload), the app MUST keep the job and retry
  automatically with exponential backoff whose interval is capped at 5 minutes, without
  losing the already-extracted/archived input; it MUST provide a manual control to run the
  queue immediately, and MUST let the user cancel a waiting job. Non-transient failures
  (bad/empty file, no captions) MUST fail with a clear message rather than retry forever.
- **FR-022**: File-style targets MUST render as a grid of square tiles with dotted
  borders; when a *valid* (accepted) file type is dragged over a tile, its border MUST
  become a solid orange with an outer glow and the tile MUST lift slightly.
- **FR-023**: The model picker MUST be populated from the models available on the user's
  Anthropic account (live), falling back to built-in presets when offline or before a key
  is set; a custom model id MUST still be allowed and capability-gating MUST apply to live
  and custom ids alike.
- **FR-024**: The bottom-bar model indicator MUST be an interactive control that switches
  the active model (from the available list), persisting the choice.
- **FR-025**: The library navigator MUST separate summaries and archived sources into
  distinct tabs, and render each entry on a single line with the title left-aligned and the
  date-time right-aligned.
- **FR-026**: Archived source filenames MUST be prefixed with the datetime
  (`YYYY-MM-DD_HHmmss__<name>.<ext>`) so they sort chronologically.
- **FR-027**: The interface MUST use a square-edged (sharp-corner) visual language with
  larger base fonts/icons; file-style drop tiles MUST present a large, left-aligned style
  name that is faded by default (no helper text) and emphasizes on valid-type hover. Type
  MUST come from a **shared font system** (a small set of named tokens) sized **generously by
  default**. Implementations MUST NOT scatter hard-coded small font sizes through the views
  (macOS's default text styles read too small), and MUST NOT rely on `dynamicTypeSize` to
  enlarge built-in styles (it barely moves them on macOS).
- **FR-028**: During active summarization the bottom bar MUST display a lively, colorful
  animation; it returns to a calm state when idle. The blend MUST adapt to appearance:
  `.plusLighter` glows over dark but washes out on light, so light mode uses a solid (`.normal`)
  higher-opacity wash so the color chase is clearly visible in both schemes.
- **FR-029**: The original source link (e.g. a YouTube URL) MUST be recorded programmatically
  and never sent to/returned from the model: in Markdown it lives in the `source:` front-matter;
  in HTML it is also rendered as a small, centered, grey, underlined link just before `</body>`.
- **FR-030**: The default max-output-tokens preset MUST be generous enough for verbose HTML
  output (8192), since an HTML summary is materially larger than the same content in Markdown.
- **FR-031**: "Reveal in Finder" MUST open Finder at the selected item's containing folder.
  Diagnosis on the target machine: `selectFile`/`activateFileViewerSelecting` DO succeed
  (`selectFile` returned `true`); they do select the file, but a pre-existing **Home window
  stays frontmost**, so the selection is hidden behind it and it looks like "it just opens
  Home." The reliable fix is to OPEN the containing FOLDER as a window
  (`NSWorkspace.open(folder, configuration:)` with `activates = true`): opening a folder brings
  *that folder's* window to the front. Do NOT rely on file-selecting reveal alone here.
- **FR-032**: Attempting to quit while one or more summaries are running MUST warn the user
  ("Quit Anyway" / "Keep Working"); confirming cancels in-flight work cleanly (assets are
  written atomically only on completion, so nothing is left partially written).
- **FR-033**: Submitting a YouTube URL MUST give immediate feedback (the input briefly shows
  "Got it!" and then clears) so it's obvious the job was queued.

### Session 2026-06-21 (Revision 6 - shared system prompt, unified editor, readable preview)

Three changes, added as FR-034..FR-036 below:

- **FR-034**: A single, editable **global system prompt** MUST be prependable in front of every
  style's prompt, so shared instructions live in one place instead of being duplicated across
  styles. It is stored in app settings, empty by default, and the assembled prompt order is
  [global system prompt → style prompt → app output convention]. When empty it changes nothing.
- **FR-035**: Prompt editing MUST be **unified** and **non-modal**: the system prompt, each
  style's prompt, and the HTML-styling prompt share one editing surface inside Settings: a
  full-height editor pane (not a floating modal/sheet) so many more lines of text are visible at
  once. Editing a style happens inline in the Settings detail, not in a stacked sheet.
- **FR-036**: The preview pane MUST offer **increase/decrease base-font-size** controls in its
  toolbar; the chosen size MUST persist across sessions (sticky) and scale the rendered body and
  headings proportionally.

### Session 2026-06-21 (Revision 7 - regenerate, geek mode, streaming, power-user touches)

Added as FR-037..FR-044 below. Design intent: deepen the core without adding surface area.
Several of these (regenerate, streaming) reuse machinery the app already has (the archived
`source/`, the SSE stream, the per-style `modelOverride`).

- **FR-037 (Regenerate)**: A saved summary MUST be re-runnable from its archived source without
  re-dropping the file. The user picks a style (defaulting to the summary's own) and may override
  the model and output format; the app reconstructs the input from the archive (re-extracting an
  archived file, or re-fetching a YouTube URL) and produces a **new** summary (non-destructive:
  the original is never overwritten). Regenerate is unavailable if the source can't be located.
- **FR-038 (Per-style model/format overrides)**: The style editor MUST expose the existing
  per-style `modelOverride` (model, output format, max tokens) so a style can pin its own model/
  format; unset fields fall back to the global settings. This adds no new data; it surfaces what
  the model already supports.
- **FR-039 (Geek mode)**: A bottom-bar **geek mode** toggle (persisted). When ON, starting a
  **single** summary (one dropped file, a YouTube URL, or a regenerate) MUST **immediately** present
  a **modal** that blocks the rest of the UI: first a spinner ("Preparing prompt stats and preview…")
  while the input is prepared, then it reveals the **exact prompt to be sent** (assembled system
  prompt + user message) with an **estimated token count**, and Send / Cancel. Cancelling during
  preparation aborts the prepare. When OFF, behavior is unchanged. Multi-file batch drops are not
  individually previewed (power-user bulk path); the estimate is a fast local heuristic (offline,
  no added latency).
- **FR-040 (Streaming preview)**: While a summary is generating, the preview pane MUST show the
  output **streaming in live**, then settle on the saved file when done. No separate window.
- **FR-041 (Library search)**: The library MUST offer a search/filter field over summary titles;
  **⌘F** focuses it. Filtering is local and instant. Empty query shows everything.
- **FR-042 (Drag out & Quick Look)**: A summary MUST be **draggable** to Finder/other apps from the
  **library row**, Finder-style (a quick click selects, a press-and-drag exports the file) while
  click-selection and arrow-key navigation keep working. Use SwiftUI `.draggable` (NOT the older
  `.onDrag`, which swallows the row's mouse-down and breaks click-to-select). If `.draggable` still
  can't coexist with `List` selection on the target OS, back the list with an AppKit `NSTableView`
  (the guaranteed Finder-exact path). Do NOT put drag on the preview title (the window background is
  movable, so the title would drag the window). **Space bar** Quick Looks the selected summary.
- **FR-043 (Richer preview)**: The Markdown preview MUST additionally render **tables** and
  **clickable links** (kept deliberately lightweight, no full CommonMark engine).
- **FR-044 (Keyboard shortcuts)**: **⌘N** creates a new style (opens the style editor); together
  with ⌘F (FR-041) and existing ⌘, (Settings), the core flow is keyboard-reachable.
- **FR-045 (YouTube file naming)**: For YouTube inputs, both the saved summary and the archived
  transcript MUST be named after the **original video title** with a `Youtube - YYYY-MM-DD - ` prefix
  (e.g. `Youtube - 2026-06-22 - How to Build a Mac App.md`), and the summary's library title shows the
  video title. Non-YouTube assets keep the `YYYY-MM-DD HHmm - <title>` convention.
- **FR-046 (Share Sumbee)**: The main panel header MUST show a top-right "Enjoying Sumbee?"
  prompt stacked above a compact "Share" button (across from the brand) that opens a share modal.
  The modal MUST let the user copy the canonical public repo link to the clipboard, provide a
  ready-to-post message, offer one-click "Post on X" and "Email a friend" deep links, and hand off
  to the native macOS share services (`NSSharingServicePicker`). The shared message MUST end with
  the repo link so it survives truncation. No analytics or tracking are added; sharing only opens
  the user's chosen app.

### Key Entities *(include if feature involves data)*

- **Summary Style**: A named, user-editable prompt with a stable identifier, a channel
  (file vs. video), a sort order, an enabled flag, optional per-style generation
  overrides, and a display name that is also its library folder name. Self-described
  on disk inside its own folder.
- **Asset (Summary)**: A saved Markdown/HTML summary file plus light metadata derived
  from its path and embedded frontmatter/meta: title, owning style, creation time, and
  a reference to its source.
- **Source (Archived Input)**: A date-stamped copy of an original dropped file or a
  cleaned video transcript, kept so the user can delete the original and lose nothing.
- **App Settings**: Library location, generation options, caption language, output
  format and HTML-styling prompt, and window state, stored separately from styles and
  separately from the (Keychain-held) API key; versioned for safe migration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a stored key and a configured style, a user can drop a transcript
  and end with a saved summary file in three actions or fewer (drop → wait → done),
  with no manual file naming.
- **SC-002**: 100% of saved summaries are openable and readable with the app closed,
  directly from the chosen folder in Finder or another editor.
- **SC-003**: After deleting an original input, the project still contains everything
  needed (an archived copy of every processed source) in 100% of cases.
- **SC-004**: Dropping N files yields N independent results; a single failure leaves
  the other N−1 successes intact (no all-or-nothing batch loss).
- **SC-005**: The app never starts summarization without a stored key, and recovers to
  a clear "fix your key" state on every authentication failure.
- **SC-006**: The API key never appears in any file the app writes or any log it emits.
- **SC-007**: The interface remains interactive (scroll, cancel, navigate) throughout
  a running summarization job.
- **SC-008**: Browsing and opening existing summaries succeeds with no network access.
- **SC-009**: The app adapts to system light/dark appearance automatically with a
  coherent accent and legible contrast in both.
- **SC-010**: Adding a new model identifier requires no change to how requests are
  built; unsupported parameters are never sent to a model that rejects them.

## Assumptions

- The single user is technically comfortable and runs the app on their own Mac
  (macOS 15+); no multi-user, accounts, or sync are needed.
- Inputs are already text (or have captions); audio/video transcription is out of
  scope for this version.
- A working internet connection is available when summarizing or fetching captions;
  all other use works offline.
- The user supplies their own summarization-service API key.
- Default output is Markdown; HTML is an opt-in alternative.
- Batch processing is sequential in this version (kindest to rate limits); small
  concurrency is a later enhancement.
- The app ships as a local/personal build; public signing/notarization is deferred.
- Reasonable defaults (faithful-summary settings, ~80-char title length, English
  captions, standard error messaging) are used where the source did not dictate
  otherwise, and are recorded here and in the plan.
