# Quickstart — Recording / Transcription / Diarization

How to build, run, and (manually) verify the feature. Most of it can only be exercised on a real Mac
with a microphone and a meeting playing — note the device-only caveats.

## Prerequisites
- macOS 15+ (the process tap needs 14.4+, always satisfied).
- The whisper xcframework vendored into `Vendor/` (see "Models & vendoring").
- First run downloads the whisper model (and, in Phase 3, the speaker-embedding model) into
  `~/Library/Application Support/Sumbee/models/`.

## Build & run
```bash
cd Sumbee
swift build
swift test                      # unit-testable parts (writer, clustering, gate, model-state, dedup)
./scripts/bundle.sh             # adds mic/audio-capture usage strings + copies the xcframework
open dist/Sumbee.app
```

## Permissions (first run)
- **Microphone** — granted on first record (NSMicrophoneUsageDescription explains why).
- **Audio capture** (for the system tap) — granted when you first capture the far side; if denied,
  recording continues **mic-only** with a notice.
- **Ad-hoc signing caveat:** because dev builds are ad-hoc signed, TCC grants can reset on every
  rebuild (same issue as feature 001's reveal). For stable testing, grant again after a rebuild, or
  test from a Developer-ID-signed build.

## Manual verification (device-only)
1. **Mic transcript (Phase 1):** Record, speak; partials appear < ~2 s; Stop writes a
   `… (recording).md` into `source/`; summarize it with a style.
1b. **Audio file import (Phase 1B):** Drop an `.m4a`/`.mp3`/`.wav` onto Sumbee; it transcribes in
   batch (determinate progress), writes a `… (import).md` into `source/`, and summarizes with a style.
   (No mic/permission needed — the easiest end-to-end test of the pipeline.)
2. **Both sides (Phase 2):** Join a Meet in your browser, pick the browser in the source picker,
   Record (don't make Sumbee join). Confirm your voice and the remote voices both appear, labeled
   Me vs Remote. Use **headphones** to avoid echo.
3. **Per-person (Phase 3):** With 2–3 distinct remote voices, confirm stable per-speaker labels;
   rename a speaker and confirm it persists in the saved transcript.

## Models & vendoring
- **whisper.cpp**: vendor a prebuilt **Metal** `whisper.xcframework` in `Vendor/` (record its source
  commit + build flags here when added). Keeps the build network-free. The **GGUF model file** is
  downloaded at runtime by `ModelManager` (not committed).
- **Speaker embedding**: a Core ML ECAPA-style model, also downloaded at runtime.
- `.gitignore`: ignore downloaded models and any large vendored binaries not meant for the repo;
  document provenance here so a contributor can reproduce.

## Privacy check (must hold)
Capture, ASR, and diarization make **no network calls** (verify with a network monitor). Only
`ModelManager` downloads (explicit, one-time) and the existing summarization step (user-initiated)
use the network. Recorded audio never leaves the device.

## Definition of done
See `tasks.md` → "Definition of done (per phase)".
