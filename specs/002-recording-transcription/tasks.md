# Tasks - Recording / Transcription / Diarization

Grouped by the phase plan (research D10 / plan.md). Each phase is independently shippable and
on-device testable. `[test]` = unit-testable without a device.

## Phase 0 - Foundations & plumbing
- [ ] T001 Add `RecordingSettings` fields to `AppSettings` (+ CodingKeys + field-tolerant decode). `[test]`
- [ ] T002 Add recording models (`RecordingSession`, `AudioSource`, `TranscriptSegment`, `Speaker`, `ModelAsset`).
- [ ] T003 `FeatureGate` + `DefaultFeatureGate` (always allow; increments counter). `[test]`
- [ ] T004 `ModelManager` (paths, installed/not-installed, async download+verify; stubbed downloader for tests). `[test]`
- [ ] T005 Vendor whisper.cpp xcframework (Metal); wire into Package.swift as a binary target; `bundle.sh` copies it.
- [ ] T006 `bundle.sh`: add `NSMicrophoneUsageDescription` + audio-capture usage string(s) to Info.plist.

## Phase 1 - Mic → live transcript → summarize (proves the core)
- [ ] T101 `MicCapture` (AVAudioEngine input tap → 16 kHz mono Float32; level metering).
- [ ] T102 `CaptureCoordinator` (single source; ring buffer; stream-to-temp-file; teardown).
- [ ] T103 `WhisperTranscriber`: windowed streaming inference; partial + finalized `ASRSegment`s; overlap de-dup. `[test: de-dup]`
- [ ] T104 `RecordingState` (@MainActor): status, segments, livePartial, level; start/stop/cancel.
- [ ] T105 `TranscriptWriter`: segments → datetime-prefixed Markdown in `source/` (summarizer-compatible shape). `[test]`
- [ ] T106 `RecordButton` in MainPanel + `RecordingPanel` (levels, elapsed, live text, Stop/Cancel) + model-not-installed state.
- [ ] T107 Wire saved transcript into the existing file-summarize flow (pick a style → summarize).
- [ ] T108 Manual on-device test: latency, finalize, save, summarize (User Story 1).

## Phase 1B - Audio file import (reuses the Phase 1 transcriber)
- [ ] T150 `AudioFramesProducer` protocol; make `MicCapture` conform; fixture producer for tests. `[test]`
- [ ] T151 `TranscriptionPipeline` (source-agnostic; `.streaming` + `.batch` modes; windowing/flush). `[test: batch over a fixture]`
- [ ] T152 `FileAudioSource` (AVFoundation decode → 16 kHz mono frames; supported UTIs; determinate progress).
- [ ] T153 Route **audio-typed** file drops to the pipeline (text drops still go straight to summary); unsupported → inline error.
- [ ] T154 `TranscriptWriter`: `(import)` naming + `source: import` front-matter. `[test]`
- [ ] T155 Manual test: drop `.m4a`/`.mp3` → transcript → summarize (User Story 5).

## Phase 2 - Both sides + channel diarization
- [ ] T201 `SystemAudioTap` via Core Audio process tap (CATapDescription → aggregate device → IO callback) @ channel 1.
- [ ] T202 `SystemAudioDiscovering` + `SourcePicker` (choose the meeting app); SCK fallback path.
- [ ] T203 Two-source capture + timestamp alignment in `CaptureCoordinator`; per-source levels.
- [ ] T204 `ChannelDiarizer` (local = "Me", system = "Remote"); attribute finalized segments. `[test]`
- [ ] T205 Echo mitigation (separate-source capture, AEC, headphone hint); tap-denied → mic-only degrade.
- [ ] T206 Manual on-device test: capture a 2-party Meet without joining (User Story 2 / SC-002).

## Phase 3 - Per-person diarization + hardening
- [ ] T301 `SpeakerEmbedder` (Core ML ECAPA-style; model via `ModelManager`).
- [ ] T302 `EmbeddingDiarizer`: VAD-gated embeddings + online clustering on the system channel; never-drop-text rule. `[test: clustering]`
- [ ] T303 Editable/renamable speakers in `LiveTranscriptView`; persist renames into the saved transcript. `[test: writer with names]`
- [ ] T304 Long-session hardening (bounded memory; disk check; device-change handling; quit/sleep finalize-and-save).
- [ ] T305 One-time consent/ethics notice before first recording (persist acknowledgement).
- [ ] T306 Trial counter increments on completion via `FeatureGate.recordingCompleted()`. `[test]`
- [ ] T307 Manual on-device test: 2–3 remote voices clustered + rename flow (User Story 3 / SC-003).

## Phase 4 - Future (paid; NOT in this feature)
- [ ] Enforce ≈20-trial limit via `LicensedFeatureGate` + StoreKit.
- [ ] Cross-recording speaker enrollment (voiceprints); medium/large model option; optional translation.

## Definition of done (per phase)
`swift build` clean (0 warnings) · unit tests green · the phase's manual on-device test passes ·
specs updated if the design shifted · no network in capture/ASR/diarization (verified).
