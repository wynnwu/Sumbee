# Implementation Plan — Recording / Transcription / Diarization

Pairs with `spec.md`, `research.md`, `data-model.md`, and `contracts/`. Builds in the de-risking
phase order from research D10. Min OS unchanged (macOS 15+); process tap is 14.4+ so always present.

## Architecture

```
        ┌─────────────── RecordingState (@MainActor, ObservableObject) ───────────────┐
        │  session, segments, livePartial, speakers, levels, status                    │
        └──────────────▲───────────────────────────▲──────────────────────────────────┘
                       │ main-actor publishes        │
   ┌───────────────────┴─────┐        ┌──────────────┴──────────────┐
   │ CaptureCoordinator       │ PCM    │ TranscriptionWorker (whisper)│ segments
   │  • MicCapture (AVEngine) ├───────▶│  • sliding-window inference  ├──────────▶ DiarizationWorker
   │  • SystemTap (CATap)     │ buffers│  • partial/final segments    │            • embeddings (CoreML)
   │  • per-source ring buf   │        └──────────────────────────────┘            • online clustering
   └──────────┬───────────────┘                                                     • speakerID per segment
              │ stream to temp file (bounded memory)
              ▼
        TranscriptWriter → <library>/source/…(recording).md  → existing summarize pipeline
```

All workers run off the main actor; results hop back to `RecordingState`. Models come from
`ModelManager` (runtime download). `FeatureGate` is consulted once at start.

## Module layout (new)

```
Sources/SumbeeKit/
  Models/
    Recording.swift              # RecordingSession, AudioSource, TranscriptSegment, Speaker, RecordingSettings, ModelAsset
  Services/Recording/
    AudioFramesProducer.swift    # the universal source protocol (mic, tap, file all conform)
    CaptureCoordinator.swift     # owns mic + system tap, format conversion, ring buffers, levels
    MicCapture.swift             # AVAudioEngine input tap → 16k mono Float32
    SystemAudioTap.swift         # Core Audio process tap (+ SCK fallback), app picker support
    FileAudioSource.swift        # decode an imported audio file → frames, batch mode (FR-017)
    TranscriptionPipeline.swift  # source-agnostic: producer → transcriber → diarizer → segments (FR-018)
    Transcriber.swift            # protocol; WhisperTranscriber wraps the xcframework
    Diarizer.swift               # protocol; ChannelDiarizer (Phase 2) + EmbeddingDiarizer (Phase 3)
    SpeakerEmbedder.swift        # Core ML embedding model wrapper (Phase 3)
    ModelManager.swift           # download/verify/update whisper + embedding models
    TranscriptWriter.swift       # segments → datetime-prefixed Markdown in source/
    FeatureGate.swift            # GateDecision + DefaultFeatureGate (always allow + count)
  State/
    RecordingState.swift         # @MainActor store driving the panel
  Views/Recording/
    RecordButton.swift           # entry point in MainPanel
    RecordingPanel.swift         # levels, elapsed, live transcript, Stop/Cancel
    LiveTranscriptView.swift     # speaker-labeled streaming text + rename
    SourcePicker.swift           # choose which app's audio to tap
    ConsentNotice.swift          # one-time ethics notice
Vendor/ (gitignored build input or vendored xcframework)
  whisper.xcframework            # Metal-built; see quickstart for provenance/build
```

Package.swift: add the whisper xcframework as a binary target (or a `Vendor/` linked framework).
`bundle.sh`: add `NSMicrophoneUsageDescription` and the audio-capture usage string(s) to Info.plist;
copy the xcframework into the app bundle.

## Integration with existing code

- `AppSettings`: add the `RecordingSettings` fields (rides field-tolerant decoding — no migration).
- `MainPanelView`: add the **Record** entry (button) next to drop tiles / YouTube.
- Output: `TranscriptWriter` writes into `source/` using `DateUtil` naming; the user summarizes via
  the existing file flow. **No change** to `SummarizationEngine`, styles, or library.
- `ContentView`: present `RecordingPanel` as an overlay/sheet while recording.

## Phasing (each independently shippable + on-device testable)

**Phase 1 — Mic → transcript (proves the core).**
ModelManager (whisper download) · MicCapture · WhisperTranscriber (windowed) · RecordingState ·
RecordingPanel (levels, elapsed, live text, Stop) · TranscriptWriter · summarize the result.
Acceptance: User Story 1.

**Phase 1B — Audio file import (nearly free once Phase 1 exists).**
`AudioFramesProducer` protocol · `FileAudioSource` (AVFoundation decode → frames) ·
`TranscriptionPipeline` in **batch** mode · route audio-typed file drops here (text drops still go
straight to summary) · determinate progress · save → summarize. No permissions, no real-time — the
lowest-risk way to exercise the whole on-device pipeline end-to-end.
Acceptance: User Story 5.

**Phase 2 — Both sides + channel diarization.**
SystemAudioTap (Core Audio process tap) + SourcePicker · two-source capture + alignment ·
ChannelDiarizer (Me/Remote) · echo handling · graceful tap-denied degrade.
Acceptance: User Story 2 + SC-002.

**Phase 3 — Per-person diarization + hardening.**
SpeakerEmbedder (Core ML) · EmbeddingDiarizer (online clustering) · editable/renamable speakers ·
long-session memory bounds · consent notice · trial counter + FeatureGate seam.
Acceptance: User Story 3, 4 + SC-003/005/006.

**Phase 4 — (future, paid).** Enforce ≈20-trial gate via FeatureGate + StoreKit; speaker enrollment
across recordings; larger model option. Not in this feature.

## Testability

Pure/unit-testable without devices/audio:
- `TranscriptWriter` (segments → expected Markdown shape) — like existing codec tests.
- Online clustering (synthetic embedding vectors → stable IDs; threshold behavior).
- `FeatureGate` (counter increments; decision today always `.allowed`).
- `ModelManager` path/state logic (installed/not-installed) with a stubbed downloader.
- Window de-dup logic for streaming whisper (overlapping windows → no duplicated finalized text).

Device-only (manual, documented in quickstart): mic capture, the process tap, real ASR latency,
diarization quality. These need a Mac with mic + a meeting playing; can't be headless-verified.

## Key risks (carried from research) & mitigations

| Risk | Mitigation |
|---|---|
| whisper isn't streaming | windowed inference + overlap de-dup; tune window/latency |
| process-tap API new/undocumented | app-scoped tap + SCK fallback + mic-only degrade |
| real-time multi-speaker diarization is hard | channel prior baseline; embeddings layered; editable labels; DER as a metric not a gate |
| echo (mic hears remote) | capture sources separately; AEC/voice isolation; headphone hint |
| CPU/thermals on long calls | background queues; model-size choice; stream-to-disk |
| ad-hoc TCC churn in dev | documented; fine once Developer-ID signed |
| zero-deps principle | documented scoped exception (research D9), narrowest possible |
