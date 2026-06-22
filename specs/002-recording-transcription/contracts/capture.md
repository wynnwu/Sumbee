# Contract — Audio Capture

Capture is two interchangeable sources behind one coordinator. Output everywhere is **16 kHz mono
Float32** PCM frames tagged with a `channelID` and a capture timestamp, so transcription and
diarization are source-agnostic.

```swift
struct AudioFrames: Sendable {            // a small buffer of PCM
    let channelID: Int                    // 0 = local (mic), 1 = system (tap)
    let samples: [Float]                  // 16 kHz mono Float32
    let hostTime: UInt64                  // for cross-source alignment
}

protocol AudioCapturing: AnyObject {
    var channelID: Int { get }
    var displayName: String { get }
    var level: Float { get }              // live RMS for the meter
    func start(_ onFrames: @escaping @Sendable (AudioFrames) -> Void) throws
    func stop()
}

enum CaptureError: Error { case micPermissionDenied, tapPermissionDenied,
                                 tapUnavailable, noInputDevice, deviceChanged }
```

- **MicCapture** (`AudioCapturing`): `AVAudioEngine` input tap → `AVAudioConverter` to 16 kHz mono.
  Enables macOS voice processing (AEC / voice isolation) where available. `channelID = 0`.
- **SystemAudioTap** (`AudioCapturing`): a **Core Audio process tap** (`CATapDescription` for the
  chosen process → `AudioHardwareCreateProcessTap` → aggregate device → IO callback) at `channelID = 1`.
  Falls back to ScreenCaptureKit audio if a tap can't be created. Exposes the candidate apps:

```swift
struct CaptureTarget: Identifiable { let id: pid_t; let name: String; let bundleID: String? }
protocol SystemAudioDiscovering { func audioProducingApps() -> [CaptureTarget] }   // for the SourcePicker
```

- **FileAudioSource** (`AudioCapturing`, FR-017): decodes an imported file (`.m4a/.mp3/.wav/.aiff/.caf`)
  via `AVAudioFile`/`AVAssetReader` + `AVAudioConverter` to 16 kHz mono and emits `AudioFrames`
  (`channelID = 0`) in **batch** — as fast as the transcriber consumes them — then signals end-of-file.
  No permissions, no real-time pacing; reports determinate progress (total duration is known).

> `AudioCapturing` is the universal **`AudioFramesProducer`**: mic, system tap, and file all conform,
> so the `TranscriptionPipeline` (see `asr-diarization.md`) never knows or cares where audio came from
> (FR-018). Adding a future source = one more conformer, nothing downstream changes.

- **CaptureCoordinator**: owns the active sources, writes each to a per-source **ring buffer** and a
  **temp file** (bounded memory, FR-015), publishes `level`s, and forwards `AudioFrames` to the
  transcription worker. Handles device-change/teardown safely (FR-009/015).

**Permissions**: mic via `AVCaptureDevice.requestAccess(for: .audio)`
(`NSMicrophoneUsageDescription`); the tap via the audio-capture TCC path (no Screen Recording).
Every denial maps to a `CaptureError` that the UI turns into a recoverable state (FR-012); a denied
tap degrades to **mic-only** (FR-003).

**Invariant**: capture performs **no network I/O** (SC-004). Sources are never pre-mixed before ASR
(separate channels are the diarization prior and prevent echo double-transcription, FR-016).
