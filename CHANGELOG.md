# Changelog

All notable changes to Sumbee are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## [0.5.1] - 2026-06-29

### Fixed
- **Settings backdrop flicker.** With Settings open, the dim backdrop and the panel's drop shadow could
  flicker on sections that host a scrolling list or text editor (Styles, Library, System Prompt). The
  backdrop is now a proper macOS frosted-glass pane (NSVisualEffectView) and the panel no longer casts
  a soft drop shadow, so nothing re-blends when a section's scroll view repaints; the app stays
  visible, frosted, behind Settings. (See `docs/swift-macos-learnings.md` #32.)

## [0.5.0] - 2026-06-29

### Added
- **Summarize a whole YouTube playlist.** A thin **mode rail** now switches the main panel between
  **Transcripts** (drag-and-drop) and **YouTube**. In YouTube mode, paste a single video or a
  **playlist** URL: a playlist fetches an inline checklist (Select all / None, with already-summarized
  videos excluded by default) and summarizes the videos you pick, one at a time, through a chosen
  YouTube style via the existing queue. Enumeration uses `yt-dlp --flat-playlist` (no new dependency);
  unlisted playlists need no sign-in, private ones use the YouTube cookie modes.
- **Playlists are kept.** Fetched playlists are saved under "Your Playlists" (a section of its own,
  separate from the URL box) and reopen instantly without re-fetching, so you can summarize a few,
  come back later, and summarize more; a **Refresh** picks up newly-added videos. Done status is
  derived from your library, and videos already summarized or currently in the queue are skipped
  automatically. Each video row reveals a **Watch on YouTube** link on hover.
- YouTube summaries now record the original **video length** in their Markdown frontmatter / HTML
  metadata. (FR-068 to FR-079; see `specs/007-playlist-summarize/`)

## [0.4.0] - 2026-06-25

### Added
- **YouTube access modes (for the "confirm you're not a bot" gate).** Settings ▸ YouTube now has a
  mode picker: Normal (default, unchanged), Client tweak (a no-login player override), and Browser
  cookies via Chrome or Safari (yt-dlp's `--cookies-from-browser`). The cookie modes spell out the
  macOS permission they need (Chrome: a Keychain prompt; Safari: Full Disk Access) and that only your
  YouTube cookies are used, only to YouTube. (FR-059 to FR-062)

### Changed
- **Browse the library while a summary streams.** The live generation preview no longer takes over
  the whole preview pane. During a generation you can select any summary to read it (space-bar Quick
  Look works too), and a new **Watch** button in the bottom bar returns you to the live stream. The
  stream is still the default view when a generation starts. (FR-053 to FR-057; see
  `specs/004-streaming-preview-browse/`)
- The "Sign in to confirm you're not a bot" failure now shows a clear, actionable message (update
  yt-dlp, drop your VPN, or enable browser cookies) instead of a raw error dump, and is not
  auto-retried because it needs a user action. (FR-058; see `specs/005-youtube-auth-modes/`)

## [0.3.0] - 2026-06-23

### Added
- **In-app HTML viewer.** HTML summaries now render with their own styling inside the preview pane
  instead of falling back to plain text. The viewer is deliberately basic and private: it does not
  run the document's JavaScript, blocks remote network loads, persists no cookies or cache, and
  opens link clicks in your browser; the preview font controls zoom it. When a summary uses
  interactive or dynamic features (scripts, embeds, media, forms), a **View in Browser** button
  appears in the top right for the full experience. (FR-047 to FR-052; see
  `specs/003-html-preview-viewer/`)

## [0.2.7] - 2026-06-22

### Fixed
- **YouTube caption fetch hitting HTTP 429 ("Too Many Requests").** The app requested
  `--sub-langs "en.*"`, which matched every auto-translated track (en-ar, en-fr, …) and made yt-dlp
  download dozens of subtitle files per video, tripping YouTube's rate limit. It now requests only
  the specific language variants, spaces requests out (`--sleep-requests`, `--retries`), and treats
  429 as a transient rate-limit so the queue retries with backoff instead of hard-failing the batch.

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
