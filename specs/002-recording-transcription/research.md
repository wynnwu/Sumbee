# Phase 0 Research & Decisions - Recording / Transcription / Diarization

The hardest, riskiest feature in Sumbee. Each decision lists rationale + alternatives rejected, and
flags the real engineering risks. Constitution principles in tension (zero-dependency; privacy;
local-first) are addressed explicitly.

## D1. Microphone capture - AVAudioEngine

**Decision**: Capture the mic with `AVAudioEngine` (install a tap on `inputNode`), 16 kHz mono
Float32 for ASR, with `AVAudioConverter` from the device format. Request mic permission via
`AVCaptureDevice.requestAccess(for: .audio)`; Info.plist `NSMicrophoneUsageDescription`.

**Rationale**: Lowest-latency, callback-based PCM; trivial format control; pairs with macOS voice
processing (AEC/voice isolation) on the input node. **Rejected**: `AVCaptureSession` (heavier,
oriented to A/V files), `AudioQueue` (older, more boilerplate).

## D2. Far-side/system audio - Core Audio process tap (chosen), ScreenCaptureKit (fallback)

**Decision**: Tap the meeting app's audio with a **Core Audio process tap**
(`AudioHardwareCreateProcessTap` + `CATapDescription` targeting the browser/meeting process,
plus an aggregate device to pull the tapped stream), macOS 14.4+. The app targets macOS 15+, so it's
always available. This captures *what the meeting app outputs* (the remote participants) **without
joining the call** and **without Screen Recording permission** (audio-only; uses the audio-capture
TCC path). ScreenCaptureKit (`SCStream` audio, `capturesAudio`, exclude-current-process) is the
**documented fallback** when a tap can't be created.

**Rationale**: "Both sides without joining" = mic (you) + system output of the meeting (them). A
process tap is the lightest, most private way (audio-only, app-scoped, no screen capture). Keeping it
**app-scoped** (tap the browser, not the whole system) avoids capturing unrelated audio (Music, etc.).
**Rejected**: virtual audio drivers (BlackHole/Loopback) require a kernel/driver install, terrible
UX, not shippable; ScreenCaptureKit as primary needs the scarier Screen Recording permission.

**Risks**: the process-tap API is new and lightly documented; DRM'd/"protected" audio can't be
tapped; identifying the right process (the browser tab playing Meet) needs a picker ("which app's
audio?"). Mitigation: a source picker listing running audio-producing apps; SCK fallback; mic-only
degrade (FR-003/012).

## D3. On-device ASR - bundled whisper.cpp (Metal), runtime-downloaded model

**Decision**: Vendor **whisper.cpp** built with Metal as a prebuilt **xcframework** (no build-time
network, see D9). Run streaming inference over a **sliding window** of recent audio to emit partials,
finalizing segments on pauses/window completion. The **GGUF model** (start with `small`/`base`;
allow `medium`) is **downloaded at runtime** into `~/Library/Application Support/Sumbee/models/` via
a `ModelManager` (same pattern as `yt-dlp`), with verify/update and a "not installed" state.

**Rationale**: User-selected (best accuracy, any language, fully offline, macOS 15+). Runtime model
download keeps the **repo + build network-free** and avoids shipping 100s of MB. **Rejected**:
`SFSpeechRecognizer` (continuous-mode limits, weaker long-form); `SpeechAnalyzer`/`SpeechTranscriber`
(excellent but macOS 26-only, would bump the feature's min OS); cloud ASR (violates privacy promise).

**Risks**: real-time with whisper means **chunked/windowed** inference (whisper is not natively
streaming): tuning window length vs latency vs duplicate text at boundaries is the core ASR work;
CPU/Metal load during a long call (battery/thermals). Mitigation: window ≈ 5–10 s with ~1 s overlap +
de-dupe on finalize; run on a background queue; expose model-size choice (speed vs accuracy);
`whisper`'s token timestamps drive segment boundaries.

## D4. Diarization - channel prior + speaker embeddings + online clustering

**Decision**: Two layers.
1. **Channel prior (free, reliable)**: the `local` (mic) source is always its own speaker; the
   `system` source is "remote." This alone solves 2-party calls perfectly and is the safety net.
2. **Per-person within a source**: compute **speaker embeddings** (a small ECAPA-TDNN / wespeaker-style
   model converted to **Core ML**, no runtime dep, downloaded like the ASR model) on short voiced
   windows, and **cluster online** (incremental cosine-similarity assignment to centroids; new
   centroid when below threshold; periodic re-clustering). Speaker IDs are stable per session;
   labels are **user-editable** post-hoc (FR-008).

**Rationale**: The user wants true per-person, but real-time multi-speaker diarization is the single
hardest, least-reliable part. Anchoring on the channel prior guarantees a useful baseline; embeddings
+ online clustering layer per-person separation on top, primarily on the remote channel. Editable
labels make inevitable errors recoverable. **Rejected**: whisper `tinydiarize` (2-speaker turn marks
only); requiring a heavy offline diarizer (pyannote full pipeline) is not real-time, Python-bound.

**Risks**: diarization error rate is genuinely hard to guarantee; treated as a **tracked metric,
not a hard gate** (SC-003). Overlapping speech degrades embeddings. Mitigation: VAD-gated embedding
windows; cluster only confident, voiced frames; never let a clustering error drop text (assign to
"Unknown speaker" rather than discard); ship channel-prior first (Phase A), layer clustering (Phase B).

## D5. Real-time pipeline & concurrency

**Decision**: A capture actor feeds a ring buffer per source; a transcription worker (off main)
windows audio → whisper → segments; a diarization worker tags finalized segments; results hop to the
`@MainActor` store for live UI. Audio is **streamed to a temp file** (not all held in RAM) for
bounded memory on long sessions (FR-015). Backpressure: drop/merge windows if ASR falls behind rather
than unbounded queueing.

**Rationale**: Mirrors the existing engine's off-main pattern; keeps the UI responsive; bounds memory.

## D6. Privacy & permissions

**Decision**: **On-device only** for capture/ASR/diarization, with no network in this pipeline (SC-004).
Permissions: microphone (`NSMicrophoneUsageDescription`); audio-capture TCC for the tap; (SCK fallback
would add Screen Recording). Each requested with an explainer; denial leads to graceful degrade (FR-012). A
one-time **consent/ethics notice** before first recording (FR-013). `bundle.sh` must add the
usage-description strings to the generated Info.plist.

**Risk**: ad-hoc signing makes TCC grants churn per rebuild (known from feature 001's reveal saga):
painful in dev, fine once Developer-ID signed. Note in quickstart.

## D7. Integration - recording is just another input

**Decision**: A finished recording writes a **Markdown transcript** into `source/` (datetime-prefixed,
speaker-labeled, timestamped) and is selectable as a summarization input; `SummarizationEngine` and
styles are **unchanged**. Internally this is a new `Job.Input` only if we summarize directly; the
simplest path is: recording → saved transcript file → user picks a style (reuses file-drop flow).

**Rationale**: Maximum reuse, minimum new surface, on-brand. The recording feature owns capture +
transcription; summarization stays exactly as it is.

## D8. Licensing / trial seam (no gate now)

**Decision**: A `FeatureGate` protocol with `func canStartRecording() -> GateDecision` returning
`.allowed` always today; a persisted `recordingsCompleted` counter in settings. Future paid build:
flip the gate to `.needsLicense` after ≈20 and add StoreKit, with **no other code changes**.

**Rationale**: One checkpoint, future-proof, zero user friction now (FR-014). **Rejected**: building
StoreKit now (premature; user said no gates yet).

## D9. Dependency exception - whisper.cpp & a Core ML embedding model

**Decision**: Sumbee's "zero third-party dependencies" principle gets a **documented, scoped
exception**: a vendored, prebuilt **whisper.cpp xcframework** (Metal) and a converted **Core ML**
speaker-embedding model. Both are **on-device, offline at runtime**; models download at first use
(no repo bloat, no build-time network). No other third-party runtime deps.

**Rationale**: On-device, real-time, high-accuracy ASR + diarization is not achievable to this bar
with only first-party frameworks on macOS 15. The exception is narrow (one native ASR lib + model
files), preserves privacy + offline operation, and is the minimum needed for the chosen capability.
The constitution note should record this exception explicitly. **Rejected**: SwiftPM source
dependency on whisper.cpp (build-time network/compile of C++/Metal, fragile); onnxruntime (a second
heavy dep) for embeddings, prefer Core ML.

## D10. Phasing (deliver carefully, de-risk early)

- **Phase 1**: Mic-only record → whisper streaming transcript → save to `source/` → summarize.
  (Proves ASR + pipeline + UX; no system audio, no clustering.)
- **Phase 2**: Core Audio process tap (system audio) + source picker → two-source capture →
  **channel-prior** speaker labels (Me/Remote). Echo handling.
- **Phase 3**: Per-person diarization (embedding + online clustering) on the remote channel; editable
  speaker names; long-session hardening; consent notice; trial counter + `FeatureGate` seam.
- **Phase 4 (future, paid)**: enforce the ≈20-trial limit via `FeatureGate` + StoreKit; optional
  cross-recording speaker enrollment; medium/large model option.

Each phase is independently shippable and testable on-device.

## D11. Audio file import - decode to frames with AVFoundation

**Decision**: A `FileAudioSource` decodes an imported file to the canonical 16 kHz mono Float32
frames using `AVAudioFile` (or `AVAssetReader` for compressed/AVAsset-backed formats) + `AVAudio
Converter`, then emits those frames into the **same** pipeline as live capture. Supported in v1:
`.m4a`, `.mp3`, `.wav`, `.aiff`, `.caf` (anything AVFoundation decodes). The audio track of a video
file (`.mov`/`.mp4`) is a near-free future extension via `AVAssetReader`.

**Rationale**: Reuses the entire transcription/diarization/summary stack; a file is just another
frame producer. No permissions, no real-time constraints → the **easiest, lowest-risk** way to get
the whole on-device pipeline exercised end-to-end (great early deliverable). **Rejected**: a separate
file-only transcription path (would duplicate logic and drift from live capture).

**Notes**: batch mode can run **faster than real-time** (feed frames as fast as whisper consumes
them) with **determinate progress** (we know total duration), unlike the live meter. The existing
file-drop zone should detect audio UTIs and route them here (text transcripts still go straight to
summary; audio files transcribe first).

## D12. Modular, source-agnostic `TranscriptionPipeline` (FR-018)

**Decision**: Factor transcription + diarization into one module that depends only on an
`AudioFramesProducer` and a `Mode` (`.streaming` | `.batch`), not on *where* audio comes from:

```
AudioFramesProducer  (MicCapture | SystemAudioTap | FileAudioSource)
        │  AudioFrames (16 kHz mono, channel-tagged)
        ▼
TranscriptionPipeline (mode)  →  Transcriber (whisper) → Diarizer → [TranscriptSegment]
        ▼
TranscriptWriter → source/…(recording|import).md → existing summarize pipeline
```

The pipeline owns windowing, finalize/flush, and diarization wiring; producers only emit frames;
the summary side is untouched. Adding a future source (e.g. another app's audio, a video track, a
network stream) means writing one producer; nothing downstream changes.

**Rationale**: Directly satisfies the user's "modularize so dropped files and live recording share
the path." Keeps each piece small and independently testable (a frames producer can be a fixture
array in unit tests). **Rejected**: branching `if file/live` logic inside the transcriber couples
concerns and invites drift.

**Mode differences the module must encode** (so producers stay dumb):
- *streaming*: real-time pacing; partials emitted; window de-dup; bounded memory; ends on user stop.
- *batch*: consume as fast as possible; determinate progress; ends at end-of-file; one mixed channel
  ⇒ no channel prior ⇒ diarization is embedding-clustering-only with single-speaker fallback (FR-019).
