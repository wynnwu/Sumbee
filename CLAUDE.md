# CLAUDE.md - working on Sumbee

Guidance for Claude (and humans) working in this repo.

## ⚠️ Read first: hard-won learnings
Before touching **persistence, permissions/TCC, the library list, drag-and-drop, fonts, icons, or
shell scripts**, read **[`docs/swift-macos-learnings.md`](docs/swift-macos-learnings.md)**. It
records real bugs we already hit and patched (config-reset on Codable changes; `~/Documents` TCC
breaking Reveal-in-Finder; `.onDrag` breaking `List` selection; ad-hoc-signing permission churn;
`.dynamicTypeSize` not scaling macOS fonts; malformed `.icns`; BSD `sed`; etc.). Don't relearn them.

## What this is
A native macOS app (SwiftUI + AppKit, macOS 15+) that turns transcripts and YouTube videos into
Markdown/HTML summaries saved as plain files, with local meeting audio transcription. Network
access is used for explicit model installation, Anthropic summaries/model selection, and YouTube
caption fetching. Audio and voice profiles stay local. Bundle id `com.sumbee.app`; library
defaults to `~/Sumbee Summaries` (deliberately NOT `~/Documents`; see learnings #2).

## Design process (Spec Kit)
Design lives in `specs/`. `001-transcript-summarizer/` is the shipped app (FRs, research decisions
D1–D16, contracts, tasks). For audio import, diarization, or participant recognition, read
[`008-meeting-transcription/spec.md`](specs/008-meeting-transcription/spec.md) and its plan/tasks.
Feature 008 supersedes module 002; 002 is a historical redirect.
**Update the relevant spec when you change behavior** (this project keeps specs current so a
greenfield rebuild inherits every decision). For new features, follow the existing doc structure.

## Architecture (quick map)
SwiftPM package: `SumbeeKit` (library: all logic + SwiftUI views, unit-tested) + `Sumbee` (thin
executable). `Sources/SumbeeKit/{Models,Services,State,Views}`. `AppState` is the `@MainActor`
root store; services run off-actor. Audio transcription produces a saved transcript for the existing
summarize pipeline; keep new input sources behind that boundary (see the feature 008 plan).

## Build / verify
```bash
swift build            # 0 warnings is the bar
swift test             # keep green (47+ tests)
./scripts/bundle.sh    # dist/Sumbee.app (release, locally signed; bumps Info.plist version here)
open dist/Sumbee.app
```
For bundle signing setup or repeated permission prompts, read **Build from source** in
`README.md`. Use the same existing Apple Development identity across builds; keys stay in
Keychain and `.signing-identity` stays untracked. Core builds/tests need no certificate.

Headless smoke + screenshot hooks exist for verification (`SUMBEE_SMOKE/SHOT/LIBRARY`,
`SUMBEE_OPEN_SETTINGS/SETTINGS_SECTION/EDIT_FIRST_STYLE`); see how existing screenshots are taken.
Verify each change group builds before moving on (learnings #14).

## Conventions
- Settings and optional meeting metadata use field-tolerant `Codable` (learnings #1); required
  record identity/version fields remain strict. Pinned FluidAudio dependencies resolve from
  local `Vendor` source; provenance and compatibility edits are in `Vendor/README.md`.
- For meeting model changes, read feature 008 `validation-results.md` and the pinned manifest.
  Run deterministic tests and the relevant opt-in local evaluation; keep recordings/results
  outside Git. Treat unmeasured accuracy gates as open, even when model execution succeeds.
- Fonts via the shared `Font.ui*` tokens, sized generously (learnings #10).
- Commit messages end with the project's Co-Authored-By trailer; releases are cut via `gh` with the
  built zip attached (see CHANGELOG / prior releases). Commit/push/release only when asked.
