# Phase 1 Data Model — Recording / Transcription / Diarization

New Swift types live in `Sources/SumbeeKit/Models/` (recording) and a new `Services/Recording/`
group. Nothing here changes existing summarization/library types; a recording's *output* is an
ordinary transcript file in `source/`.

## RecordingSession (transient, @Published in a RecordingState)

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `startedAt` | `Date` | stamped at start |
| `status` | `enum` | `idle / requestingPermission / recording / finalizing / saved(URL) / failed(String) / cancelled` |
| `sources` | `[AudioSource]` | `local` always; `system` if a tap is active |
| `segments` | `[TranscriptSegment]` | finalized; live partials kept separately |
| `livePartial` | `String` | volatile current-window text (not yet finalized) |
| `speakers` | `[Speaker]` | discovered this session |
| `elapsed` | `TimeInterval` | derived |
| `settings` | `RecordingSettings` | snapshot for this session |
| `saveAudio` | `Bool` | persist the raw audio file too (default false) |

## AudioSource

| Field | Type | Notes |
|---|---|---|
| `kind` | `enum { local, system, file }` | mic, process tap, or an imported audio file |
| `channelID` | `Int` | stable diarization prior (local = 0, system = 1; a single file = 0, no prior) |
| `displayName` | `String` | "Microphone" / "Chrome (Meet)" / the file name |
| `level` | `Float` | live RMS for the meter (live sources only; files show determinate progress) |

A **live recording** session has a `local` source (and a `system` source when tapping); an **audio
file import** is a session with one `file` source running in **batch** mode (FR-017/018, research
D11/D12). Both are `AudioFramesProducer`s into the one `TranscriptionPipeline`.

## TranscriptSegment

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `speakerID` | `UUID` | resolved by diarization; never nil (falls back to channel speaker, else "Unknown") |
| `text` | `String` | finalized text |
| `start` / `end` | `TimeInterval` | seconds from session start |
| `channelID` | `Int` | which source produced it (the prior) |
| `isFinal` | `Bool` | true once committed (partials are volatile) |
| `confidence` | `Float?` | ASR/diarization confidence (optional) |

## Speaker

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | stable for the session |
| `displayName` | `String` | "Me", "Speaker 2", or user-renamed |
| `channelID` | `Int` | originating source |
| `embeddingCentroid` | `[Float]?` | running mean of voice embeddings (system channel) |
| `isLocal` | `Bool` | the mic speaker |

## RecordingSettings (persisted in AppSettings)

| Field | Default | Notes |
|---|---|---|
| `whisperModel` | `"small"` | `base/small/medium`; speed↔accuracy |
| `transcriptionLanguage` | `nil` (auto) | whisper language hint |
| `captureSystemAudio` | `true` | tap the meeting app when available |
| `saveAudioByDefault` | `false` | keep the raw recording or not |
| `recordingsCompleted` | `0` | trial counter (FR-014); future ≈20 gate |
| `recordingConsentAcknowledged` | `false` | one-time ethics notice (FR-013) |

These extend `AppSettings` and ride its existing field-tolerant decoding (D15 of feature 001), so
adding them never resets a config.

## ModelAsset (managed by ModelManager)

| Field | Type | Notes |
|---|---|---|
| `kind` | `enum { whisper(size), speakerEmbedding }` | |
| `version` | `String` | for update checks |
| `url` | `URL` | local path in `…/Application Support/Sumbee/models/` |
| `bytes` | `Int` | size, for the download UI |
| `installed` | `Bool` | drives a "model not installed" state |

## FeatureGate / TrialState (licensing seam)

```
enum GateDecision { case allowed, case needsLicense(trialsUsed: Int, limit: Int) }

protocol FeatureGate {
    func canStartRecording() -> GateDecision   // today: always .allowed
    func recordingCompleted()                  // increments recordingsCompleted
}
```

`DefaultFeatureGate` returns `.allowed` always and increments the counter. A future
`LicensedFeatureGate` returns `.needsLicense` once `recordingsCompleted >= 20` and no license is
present (StoreKit) — the only behavioral change required to monetize.

## On-disk output (reuses existing conventions)

A finished recording **or import** writes, into `<library>/source/`:
- `YYYY-MM-DD HHmm — <title> (recording).md` (live) or `… (import).md` (file) — the transcript:
  front-matter (`source: recording` or `source: import`,
  `recordedAt`, `durationSeconds`, `speakers`), then Markdown body of `**Speaker** (mm:ss)` lines —
  the **same shape the summarizer already understands** for transcripts.
- Optionally `… .wav/.m4a` — the raw audio, only if `saveAudio`.

The user then summarizes the transcript with any style via the existing flow (no new summarize path).
