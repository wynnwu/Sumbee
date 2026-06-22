# Contract — Transcription, Diarization, Models, Gate

All on-device. All inputs are the `AudioFrames` from `capture.md`. All outputs flow to
`RecordingState` on the main actor.

## Transcriber (whisper.cpp)

```swift
struct ASRSegment: Sendable {
    let channelID: Int
    let text: String
    let start: TimeInterval        // seconds from session start
    let end: TimeInterval
    let isFinal: Bool              // partials are volatile and replaceable
    let confidence: Float?
}

protocol Transcribing: AnyObject {
    func loadModel(at url: URL, language: String?) throws
    /// Feed frames; emits volatile partials and, on window/pause boundaries, finalized segments.
    func accept(_ frames: AudioFrames)
    var onSegment: (@Sendable (ASRSegment) -> Void)? { get set }
    func flush()                   // finalize on stop
}
```

- `WhisperTranscriber` wraps the vendored xcframework. **Streaming = windowed**: maintain a sliding
  window (~5–10 s, ~1 s overlap) per channel; emit a partial for the live window; **finalize** a
  segment at a detected pause or window roll-off; **de-duplicate** overlap so finalized text never
  repeats. Token timestamps set `start`/`end`. Runs off the main actor.

## Diarizer

```swift
protocol Diarizing: AnyObject {
    /// Given a finalized ASR segment (+ its audio window), return the speaker id to attribute it to.
    func attribute(segment: ASRSegment, window: [Float]) -> UUID
    var speakers: [Speaker] { get }
    func rename(_ speaker: UUID, to name: String)
}
```

- **ChannelDiarizer** (Phase 2): one speaker per `channelID` (local = "Me", system = "Remote").
  Deterministic, never wrong about local-vs-remote.
- **EmbeddingDiarizer** (Phase 3): wraps `ChannelDiarizer` for the prior, then on the **system**
  channel computes a voice embedding for the segment's voiced window (`SpeakerEmbedder`, Core ML) and
  assigns it to the nearest existing centroid by cosine similarity, or spawns a new speaker when below
  threshold; centroids update as running means; periodic light re-clustering. **Never drops text** —
  an unconfident segment is attributed to an "Unknown" speaker rather than discarded (FR-008).

```swift
protocol SpeakerEmbedding: AnyObject { func embed(_ samples: [Float]) -> [Float]? }   // Core ML ECAPA-style
```

## ModelManager (runtime model acquisition — FR-011)

```swift
enum ModelKind: Equatable { case whisper(size: String); case speakerEmbedding }
protocol ModelManaging {
    func isInstalled(_ kind: ModelKind) -> Bool
    func localURL(_ kind: ModelKind) -> URL?
    func install(_ kind: ModelKind, progress: @Sendable (Double) -> Void) async throws  // download+verify
}
```

Downloads into `~/Library/Application Support/Sumbee/models/`, verifies (size/checksum), supports
update. Mirrors the `yt-dlp` runtime-acquisition pattern → repo and build stay network-free. UI shows
a "model not installed → Install (xxx MB)" state before the first recording.

## FeatureGate (licensing seam — FR-014, no gate now)

```swift
enum GateDecision: Equatable { case allowed; case needsLicense(trialsUsed: Int, limit: Int) }
protocol FeatureGate {
    func canStartRecording() -> GateDecision   // DefaultFeatureGate: always .allowed
    func recordingCompleted()                  // increments AppSettings.recordingsCompleted
}
```

Consulted once at record start. Today `DefaultFeatureGate` always returns `.allowed`. A future
`LicensedFeatureGate` returns `.needsLicense(20)` once the counter reaches the limit and no StoreKit
entitlement is present — the *only* change required to monetize.

## Cross-cutting invariants

- **No network** in capture/ASR/diarization (SC-004); only model download (explicit) and the existing
  summarization step (user-initiated) touch the network.
- Every stage degrades, never crashes: missing model → install prompt; denied tap → mic-only;
  diarization doubt → "Unknown" speaker; stop at any time → finalize + save what exists.
