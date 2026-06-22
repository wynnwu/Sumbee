# Feature Specification: On-device Recording, Real-time Transcription & Diarization

**Feature Branch**: `002-recording-transcription`

**Created**: 2026-06-21

**Status**: Draft (design, not yet implemented)

**Input**: User: "On-device recording, real-time transcripts, and speaker diarization. Be thoughtful
and careful. A paid feature in the future (≈20 free trials), no gates for now. Record both sides of
a Google Meet call without joining the meeting. Use the full, detailed Spec Kit process."

## Summary

Add the ability to **record audio on the Mac**, **transcribe it live on-device**, and **attribute
text to speakers**, including capturing **both sides of a video call (e.g. Google Meet) without
Sumbee joining the call**, by mixing the local microphone with a tap of the meeting app's audio
output. A finished recording becomes a transcript that flows into Sumbee's existing
style→summarize→library pipeline unchanged. Everything (capture + ASR + diarization) runs **locally**;
only the final transcript text is ever sent for summarization (existing, disclosed behavior).

The same on-device transcription→diarization pipeline also powers **importing your own audio files**
(drag in an `.m4a`/`.mp3`/`.wav`/…) → transcribe → summarize. Live capture and file import are two
*sources* into one shared, modular pipeline.

This is intended to become a **paid feature** (≈20 free recordings, then a license). For now it is
**ungated**: the trial counter and licensing seam exist but never block.

## Clarifications

### Session 2026-06-21 (decisions that shape the design)

- Q: On-device real-time ASR engine / minimum OS? → **A: Bundle `whisper.cpp`** (Metal-accelerated).
  Best accuracy, any language, fully offline, keeps the feature on **macOS 15+**. Accepted as a
  deliberate, scoped exception to the zero-dependency principle (see research D9 / constitution note).
- Q: Speaker diarization scope for v1? → **A: True per-person diarization** that distinguishes each
  individual speaker, not merely "Me vs Remote." The two capture channels (mic vs system) are used
  as a strong prior; voice-embedding + online clustering separates multiple people within a channel.
- Q: How to capture the call's far side without joining? → **A: Core Audio process tap**
  (`AudioHardwareCreateProcessTap`, macOS 14.4+) on the meeting app/browser, audio-only, no Screen
  Recording permission. ScreenCaptureKit is the documented fallback (research D2).
### Session 2026-06-22 (audio file import + modular pipeline)

- Q: Should users also be able to drop **their own audio files** through this? → **A: Yes.** A
  dropped/imported audio file (`.m4a`, `.mp3`, `.wav`, `.aiff`, `.caf`, …) is decoded to PCM and fed
  through the **same** on-device transcription→diarization pipeline, producing a transcript that then
  summarizes via the existing styles. (See FR-017.)
- Q: Architectural implication? → **A: Modularize.** The transcription/diarization stage MUST be a
  **source-agnostic module** (`TranscriptionPipeline`) that consumes audio *frames* from any producer
  (live mic, the system tap, or a file reader) in either **streaming** (live) or **batch** (file)
  mode. Live recording and file import are just two `AudioFramesProducer`s. (See FR-018, research D11/D12.)
- Note: a single dropped file is usually **one mixed channel**, so the channel prior (mic-vs-system)
  doesn't apply; file diarization relies on embedding clustering alone (FR-019).

- Resolved without asking: **on-device only** (no cloud ASR, preserving the privacy promise);
  **ungated now** but a `FeatureGate` + trial counter (target 20) are built as a seam;
  a **one-time consent/ethics notice** is shown before the first recording (recording others may
  require their consent); the **whisper model and the speaker-embedding model are downloaded at
  runtime** into Application Support (like `yt-dlp`), so the repo and build stay network-free.

## User Scenarios & Testing *(mandatory)*

A new **Record** entry point (alongside drop-a-file and paste-a-YouTube-URL). Starting a recording
opens a live panel: levels, elapsed time, and a **live transcript that labels speakers as it runs**.
Stopping saves the transcript (and optionally the audio) into the library's `source/`, from which the
user picks a style and summarizes, reusing the entire existing pipeline.

### User Story 1 - Record a meeting and get a live, speaker-labeled transcript (Priority: P1)

A user clicks **Record**, grants microphone (and, for the far side, audio-capture) permission, and
watches the transcript appear in real time with speaker labels. On stop, a transcript file is saved
and can be summarized with any style.

**Independent test**: Start a recording with the mic only; speak; verify partial text appears within
~1–2 s, finalizes into segments, and that stopping writes a transcript file into `source/` that can
be summarized.

**Acceptance**:
1. **Given** mic permission granted, **When** the user records and speaks, **Then** live partial
   transcript appears (<~2 s latency) and finalized segments accumulate with timestamps.
2. **Given** a stopped recording, **When** it finishes, **Then** a transcript (Markdown with speaker
   labels + timestamps) is saved to `source/` and appears as a summarizable input.
3. **Given** no mic permission, **When** the user tries to record, **Then** a clear permission
   prompt/explainer is shown and no capture starts.

### User Story 2 - Capture both sides of a Google Meet without joining (Priority: P1)

A user is in a Meet call in their browser. They click **Record** in Sumbee. Sumbee captures the
**microphone** (local voice) **and** taps the **browser's audio** (remote voices), without Sumbee
joining the meeting, and produces a single transcript with both sides attributed.

**Independent test**: Play two distinct voices through the system output (simulating remote) while
speaking into the mic; verify the transcript contains both, with the local voice and the system
voices attributed to different speakers.

**Acceptance**:
1. **Given** audio-capture permission and a meeting playing on the Mac, **When** recording, **Then**
   both the mic and the meeting app's audio are captured as distinct sources and transcribed.
2. **Given** the two sources, **When** diarization runs, **Then** the local speaker and each remote
   speaker are labeled distinctly (local is always its own speaker; remote may be 1..N people).
3. **Given** the meeting app can't be tapped (permission denied / unsupported), **Then** Sumbee
   degrades to mic-only with a clear notice rather than failing.

### User Story 3 - Per-person diarization (Priority: P2)

Within the remote channel, multiple participants are separated into distinct speakers; the user can
**rename** speakers (e.g., "Speaker 2" → "Priya"), and the summary uses those names.

**Acceptance**:
1. Distinct remote voices are clustered into stable speaker IDs across the recording.
2. The user can rename a speaker; the rename is reflected in the saved transcript.
3. Diarization errors are recoverable: speaker labels are editable post-hoc; a wrong split/merge
   never loses transcript text.

### User Story 4 - Trial seam, no gate (Priority: P2)

Recording is free and unlimited **now**, but each completed recording increments a counter, and a
`FeatureGate` abstraction is consulted (always allowing) so a future build can enforce ≈20 free
trials + a license without re-architecting.

**Acceptance**: Recording is never blocked; the completed-recording count persists; `FeatureGate`
is the single checkpoint that a future paid build flips to enforcing.

### User Story 5 - Import your own audio file → transcript → summary (Priority: P1)

A user drags an existing audio recording (a `.m4a` voice memo, an `.mp3`, a `.wav` interview) into
Sumbee. It is transcribed on-device with speaker labels, saved as a transcript, and summarized with a
chosen style, reusing the exact same pipeline as live recording, just with a file as the source.

**Independent test**: Drop a known `.m4a` containing two speakers; verify a transcript file appears
in `source/` with per-speaker segments, and that it summarizes with a style.

**Acceptance**:
1. **Given** a supported audio file, **When** imported, **Then** it is decoded to PCM and run through
   the same transcription→diarization pipeline as live capture, producing a transcript in `source/`.
2. **Given** a multi-speaker file, **When** transcribed, **Then** speakers are separated by embedding
   clustering (no channel prior available for a single mixed file) and labels are editable.
3. **Given** an unsupported or unreadable file, **When** dropped, **Then** a clear inline error is
   shown and no job starts (consistent with today's unsupported-file handling).
4. Batch transcription MAY run faster than real-time and shows determinate progress, not a live meter.

## Requirements *(mandatory)*

- **FR-001**: A **Record** action MUST be available as a first-class input alongside file-drop and
  YouTube, producing a transcript that feeds the existing summarize pipeline.
- **FR-002**: The app MUST capture the **microphone** on-device using a documented AVFoundation path,
  after obtaining microphone permission (with a usage-description string).
- **FR-003**: The app MUST capture the **far-side/system audio of a specific app** (e.g. the browser
  running Google Meet) via a **Core Audio process tap**, *without joining the meeting* and without
  requiring Screen Recording permission. ScreenCaptureKit is an allowed fallback.
- **FR-004**: Mic and system audio MUST be kept as **distinct, time-aligned sources** so that (a)
  the local speaker is always separable from remote, and (b) downstream diarization can cluster
  within each source.
- **FR-005**: Transcription MUST run **fully on-device** (bundled `whisper.cpp`), in **near-real-time**
  (streaming/sliding-window), emitting **partial** (volatile) and **finalized** segments with
  start/end timestamps.
- **FR-006**: The recording audio MUST NOT leave the device. Only the final **transcript text** is
  sent to the summarization API, and only when the user summarizes, identical to today's disclosure.
- **FR-007**: Diarization MUST attribute each finalized segment to a **speaker**: the local source is
  one speaker; the system source is split into **one or more** speakers via voice-embedding +
  **online clustering**. Speakers MUST have stable IDs for the session.
- **FR-008**: Speakers MUST be **renamable**, and labels editable after the fact; renames MUST persist
  in the saved transcript. Diarization mistakes MUST NEVER drop transcript text.
- **FR-009**: A live recording panel MUST show **input levels**, **elapsed time**, a **live
  speaker-labeled transcript**, and **Stop**/**Cancel**. Stopping MUST be safe (no truncation/corruption).
- **FR-010**: On stop, Sumbee MUST save a **Markdown transcript** (speaker-labeled, timestamped) into
  the library `source/` area, named with the datetime prefix convention, and make it immediately
  summarizable with any style. Saving the raw **audio** file is optional and user-controlled.
- **FR-011**: The ASR model and the speaker-embedding model MUST be **acquired at runtime** (download
  into Application Support, like `yt-dlp`) so the repo and the build remain network-free; a model
  manager handles download/verify/update and a clear "model not installed" state.
- **FR-012**: All required permissions (microphone; audio capture for the tap; whichever TCC class
  the chosen APIs need) MUST be requested with clear explanations, and every denial MUST degrade
  gracefully (mic-only, or a clear blocked state), never a silent failure.
- **FR-013**: Before the **first** recording, a one-time **consent/ethics notice** MUST be shown
  (recording others may require their consent; laws vary). It is acknowledged once and recorded.
- **FR-014**: Recording MUST be **ungated now**: a `FeatureGate` is consulted before each recording
  and currently always allows; the count of completed recordings is persisted for a future ≈20-trial
  limit. No StoreKit/licensing UI ships in this feature.
- **FR-015**: The feature MUST be resilient to long sessions (≥60 min): bounded memory (stream to
  disk, don't hold all audio in RAM), no unbounded transcript growth in a single view, and graceful
  handling of device changes (e.g., switching output/AirPods mid-call).
- **FR-016**: Echo/feedback MUST be mitigated: the mic source and the tapped system source are
  captured **separately** (not mixed before ASR) so the mic doesn't double-transcribe remote audio
  played through speakers; recommend the user wear headphones, and apply AEC/voice isolation where
  available.
- **FR-017 (Audio file import)**: The app MUST accept **imported audio files** (drag-in or picker;
  at least `.m4a`, `.mp3`, `.wav`, `.aiff`, `.caf`), decode them to PCM, and run them through the
  **same** transcription→diarization pipeline as live capture, producing a transcript in `source/`
  that summarizes via the existing styles. Unsupported/unreadable files fail with a clear inline
  message and start no job.
- **FR-018 (Modular, source-agnostic pipeline)**: Transcription + diarization MUST be a **single
  reusable module** consuming audio *frames* from any `AudioFramesProducer` (mic, system tap, or
  file reader) in **streaming** (live) or **batch** (file) mode. Adding a future source MUST require
  only a new producer, not changes to the transcription/diarization/summary stages.
- **FR-019 (File diarization)**: For a single mixed file (no channel prior), diarization MUST rely on
  embedding clustering alone; if it cannot separate speakers confidently it MUST fall back to a single
  speaker rather than fabricating splits, and labels remain editable (per FR-008).

### Key Entities

- **RecordingSession**: a live capture (id, started, sources, status, settings) producing segments.
- **AudioSource**: `local` (mic) or `system` (process tap of a chosen app), each a mono/stereo stream
  with a stable channel id used as a diarization prior.
- **TranscriptSegment**: `{ speakerID, text, start, end, source, isFinal, confidence }`.
- **Speaker**: `{ id, displayName, source, embeddingCentroid? }`; renamable.
- **ModelAsset**: a downloaded model (whisper GGUF; speaker-embedding) with size/version/path.
- **TrialState / FeatureGate**: completed-recording count + an always-allow gate (future paid seam).

## Success Criteria *(mandatory)*

- **SC-001**: Live partial transcript latency ≤ ~2 s on Apple-silicon; finalized segments within a
  few seconds of speech end.
- **SC-002**: A 30-minute 2-party Meet call (mic + tapped browser) yields a single transcript with
  the local speaker correctly separated from remote ≥95% of segments (channel prior).
- **SC-003**: For 2–3 distinct remote voices, per-person clustering keeps a stable identity for each
  for the majority of their speech (diarization error rate is a tracked, improvable metric, not a
  hard gate for v1).
- **SC-004**: No audio leaves the device (verifiable: capture/ASR/diarization make no network calls;
  only summarization does, on user action).
- **SC-005**: Recording is never blocked; the trial counter increments and persists.
- **SC-006**: A denied permission always yields a clear, recoverable state.
- **SC-007**: A dropped supported audio file produces a saved, speaker-labeled transcript via the
  same pipeline and is summarizable, with no new code in the transcription/diarization/summary
  stages beyond the file producer (validates the modular boundary, FR-018).

## Edge cases

- No mic / no input device; device change mid-recording (AirPods connect).
- Meeting app not tappable (sandboxed, DRM'd audio, or permission denied) → mic-only + notice.
- Silence / overlapping speech / cross-talk → segments may be imperfect; never crash or drop text.
- Very long sessions → memory-bounded; disk space check before recording.
- App quit / sleep mid-recording → finalize and save what exists (no corruption).
- Non-English / mixed-language audio → whisper auto-detect or a chosen language.
- Headphones absent → echo risk; mitigated by separate-source capture + AEC + a UX hint.

## Out of scope (kept minimal)

- Cloud transcription; meeting-bot auto-join; calendar integration; video capture.
- Live translation; real-time summarization during the call (summary still runs after, via styles).
- A full audio editor. Speaker ID across *different* recordings (voiceprints/enrollment) is future.
- Shipping StoreKit/licensing UI (only the gate seam + counter ship now).
