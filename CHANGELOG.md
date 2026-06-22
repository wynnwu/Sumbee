# Changelog

All notable changes to Sumbee are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## [0.2.6] - 2026-06-22

### Added
- **Share**: an "Enjoying Sumbee?" prompt with a Share button in the main panel header opens a
  share sheet (copy a ready-made message, post to X/Twitter, or email) so it's easy to spread the
  word. (FR-046)

## [0.2.5] - 2026-06-22

### Changed
- Main panel header renamed to **"Summary Styles - Drag & Drop Transcript Files Here (txt, md,
  pdf, docx, rtf)"**, and the YouTube section label to **"YouTube - Summarize from Captions"**.
- Removed every em dash from the app text, README, and docs; parenthetical em-dash sentences were
  rewritten into clean punctuation. No functional change.

## [0.2.4] - 2026-06-22

### Fixed
- **Glitchy shadowing/blurring behind the prompt editor**: the Settings panel used a translucent
  material, which flickers and casts shadow-like artifacts behind the prompt editor's (AppKit)
  scroll view. The panel is now a solid, flat surface (also the conventional macOS Settings look).

## [0.2.3] - 2026-06-22

### Changed
- **Prompt editors are flat**: the System Prompt / style / HTML-styling text areas dropped the
  frosted-glass material (which rendered a soft drop shadow) for a plain, conventional editable-text
  surface.
- **Privacy & About** now shows the app **version and build number**, and leads with data ownership:
  your summaries are plain files on your Mac that you fully own, kept wherever you like; the app
  never uploads or sees your library; no proprietary format, no lock-in.

### Added
- "Coming soon" note (Privacy + README) for **fully on-device summarization with local models via
  Ollama**.

### Removed
- "No analytics / no telemetry" claims (a future build may add **opt-out** usage telemetry).

## [0.2.2] - 2026-06-22

### Changed
- **Settings is flatter & more readable**: removed the elevated card/drop-shadow on every section;
  the Model picker and the segmented controls (Output format, Reasoning effort, per-style override)
  are now flat (no native bezel/shadow); the panel uses a brighter surface so the small grey
  caption text is legible.
- **API Key**: when a key is active it shows a large green check + **Update Key** / **Remove Key**
  (no entry box). **Update Key** reveals the entry form with **Save & Validate** / **Cancel**.
- **Styles**: reorder by **drag-and-drop** (handlebars on the left); removed the up/down buttons;
  the edit icon is larger.

### Internal
- Headless smoke runs skip the Keychain read (it was triggering ad-hoc access prompts).
- Added a "stale incremental build can hang at launch" entry to `docs/swift-macos-learnings.md`.

## [0.2.1] - 2026-06-22

### Fixed
- Clicking a library item now selects it reliably; the row's drag gesture was swallowing the click
  (arrow keys still worked, which was the tell).
- The summarizing animation on the bottom bar is now clearly visible in **light mode** (the glow
  blend washed out on light backgrounds).

### Changed
- **Drag-to-export** moved to the library **row** (Finder-style: quick click selects, press-and-drag
  exports) via `.draggable`; removed the preview-title drag (it dragged the window).
- **YouTube** summaries and archived transcripts are now named `Youtube - YYYY-MM-DD - <video title>`
  and the library shows the video title.
- **Geek mode** now opens its prompt-preview as an immediate modal (spinner → full preview), instead
  of leaving the UI live and popping the preview in afterward.
- Bottom bar: more spacing + vertical dividers between controls, and the gear now has a "Settings"
  label. Drop-zone style names use a lighter, thin weight.

### Docs
- Added `docs/swift-macos-learnings.md` (gotchas we hit + rules) referenced from `CLAUDE.md`, and the
  full design spec for the planned on-device recording/transcription/diarization feature (`specs/002`).

## [0.2.0] - 2026-06-21

### Added
- **Regenerate**: re-run any saved summary from its archived original with a different style,
  model, or output format; produces a new summary and never overwrites the original.
- **Live streaming preview**: the summary streams into the preview pane as it generates, then
  settles on the saved file.
- **Geek mode**: a bottom-bar toggle; when on, single summaries first show the exact prompt to be
  sent plus an estimated token count, with Send / Cancel.
- **Per-style model & output-format overrides**: surfaced in the style editor; unset fields fall
  back to the global settings.
- **Library search** (⌘F) over summary titles, and **⌘N** to start a new style.
- **Drag a summary out** to Finder/other apps, and **space-bar Quick Look**.
- **Richer Markdown preview**: renders tables and clickable links.

### Notes
- 47 unit tests. Settings decoding remains field-tolerant, so the new `geekMode` setting (and any
  future field) never resets an existing config.

## [0.1.1] - 2026-06-21

### Added
- **Shared system prompt**: one editable prompt, prepended in front of every style's prompt so
  common instructions aren't duplicated. Edited in a new Settings ▸ System Prompt section. Empty
  by default (no change to existing behavior until set).
- **Unified, non-modal prompt editor**: the system prompt, each style's prompt, and the
  HTML-styling prompt now share one full-height editor inside Settings (the style editor is no
  longer a floating sheet); the Settings window is larger so many more lines are visible.
- **Resizable, sticky preview font**: increase/decrease the preview pane's base font size from
  its toolbar; the size persists across sessions and scales body text and headings proportionally.

### Changed
- Settings JSON decoding is now field-tolerant (defaults for missing keys), so adding a new
  setting never resets an existing config.

### Fixed
- App icon rendered as garbage in Finder; rebuilt the `.icns` properly from the iconset.
- The two smallest icon sizes now show the bee only (no summary lines), which were illegible
  at 16/32 px.

## [0.1.0] - 2026-06-21

First public release.

### Added
- Native macOS app (SwiftUI + AppKit, macOS 15+) that turns transcripts and YouTube videos into
  Markdown or HTML summaries saved as plain files you own.
- Drag-and-drop transcripts (`.md`, `.txt`, `.pdf`, `.docx`, `.rtf`) onto a **style**; originals
  are archived alongside the summary.
- Batch queue: drop many at once, processed one at a time, with automatic backed-off retries for
  transient/network/model-unavailable errors and a manual "Run queue" trigger. One failure never
  aborts the batch.
- YouTube summaries from video captions via `yt-dlp` (auto-discovered or installed from Settings).
- Full CRUD for summary styles (name, channel, prompt), reflected live in the main window.
- Live library browser grouped by style: preview, reveal-in-Finder, open, copy, delete.
- Secure Anthropic API key storage in the macOS Keychain; summarizing is gated until a valid key
  is set and re-gated automatically on auth failure.
- Model-capability-aware requests: defaults to the latest Claude model and only sends parameters a
  given model accepts.
- Markdown (default) or HTML output, with an optional shared HTML-styling prompt. For YouTube, the
  original video link is recorded in the summary (front-matter / footer) without passing through
  the model.
- Default library lives at `~/Sumbee Summaries` (a non-TCC-protected folder, so "Reveal in Finder"
  works for unsigned builds). Existing libraries from earlier locations are migrated automatically.

### Notes
- The 0.1.0 download is ad-hoc signed and not notarized; see the README for first-launch steps.
