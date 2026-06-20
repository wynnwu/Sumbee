# Changelog

All notable changes to Sumbee are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-06-21

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
- Live library browser grouped by style — preview, reveal-in-Finder, open, copy, delete.
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
