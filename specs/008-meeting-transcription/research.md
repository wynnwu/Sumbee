# Research — Meeting Transcription

**Date:** 2026-09-09. Research establishes design feasibility; no audio model, accuracy,
runtime, or memory benchmark has been run. Decisions implement [spec.md](spec.md).

## D1 — Native local SDK and reproducible dependencies

**Decision:** Use FluidAudio with Parakeet TDT v2 and its offline diarization pipeline.
Use **v0.12.4 as the audited baseline**, pinned to its resolved commit when vendoring;
pin the complete transitive dependency graph and record all licenses and local patches.
A newer SDK revision requires a documented compatibility audit before replacing this baseline.
The baseline uses Swift tools 6.0, supports macOS 14+, and depends on swift-transformers,
which brings swift-jinja and swift-collections. Vendor source under `Vendor/` with local
package references so a fresh checkout builds without downloading dependencies.

**Why:** Native Swift/Core ML fits the existing app. A pinned URL alone still requires
network on a fresh build. Main and the README install example expose different APIs.
**Alternatives:** WhisperKit/SpeakerKit remain alternatives if measured quality fails;
a Python runtime or bespoke diarization engine adds unnecessary packaging/maintenance.

Sources: [FluidAudio v0.12.4 package](https://github.com/FluidInference/FluidAudio/blob/v0.12.4/Package.swift),
[swift-transformers 1.1.6 dependencies](https://github.com/huggingface/swift-transformers/blob/1.1.6/Package.swift).
The first implementation task verifies the complete dependency/artifact graph and an
empty-cache offline build; this document does not claim that test has passed.

## D2 — Batch transcription, timestamp alignment, and progress

**Decision:** Keep SDK details inside `FluidAudioTranscriber`. Decode retained audio
through AVFoundation/SDK converters to the required 16 kHz mono Float32 representation.
Process one meeting at a time. ASR and diarization can run sequentially to limit memory.
Use `tokenTimings` to aggregate subword tokens into words, then match word intervals to
speaker intervals. Preserve text when timestamps or attribution are missing; attach
untimed words to their surrounding timed segment, or an explicit untimed turn if no
safe bound exists. Tied/overlapping attribution stays unknown. Never claim to recover
words that the recognizer itself missed.

Expose stages with indeterminate inference progress where the pinned SDK lacks callbacks;
show measured bytes/progress for copying/downloading. A cancellation request acknowledges
immediately, stops between safe SDK stages, and discards late results. Finishing an
uncancellable SDK call may take longer; do not start another inference concurrently.

**Why:** v0.12.4 exposes optional subword timings and disk-backed diarization, but newer
main-only helpers/progress callbacks cannot be assumed. Percentages must reflect real work.
**Alternative:** Using streaming managers for prerecorded meetings introduces identity drift
and overlap/window bookkeeping without delivering the requested value.

Sources: [tagged ASR types](https://github.com/FluidInference/FluidAudio/blob/v0.12.4/Sources/FluidAudio/ASR/AsrTypes.swift),
[tagged offline manager](https://github.com/FluidInference/FluidAudio/blob/v0.12.4/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift),
[ASR guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md).

## D3 — Separate meeting diarization from participant recognition

**Decision:** Match offline `speakerDatabase` embeddings to a separate participant catalog.
Use normalized finite nonzero vectors and cosine similarity, with both a minimum score
and a separation margin from the second candidate. Calibrate and freeze those thresholds
on development recordings; score held-out meetings separately. Restrict candidates to
selected attendees when supplied. No qualifying candidate means no suggestion.

The offline manager's speaker IDs are local to a recording. Legacy `initializeKnownSpeakers`
is not an enrollment API for this offline manager. Store our own participant UUIDs and
compatible embedding fingerprints (model revision, preprocessing, vector dimension).

Enrollment uses the **whole detected speaker cluster**, not just the playback excerpt:
`speakerDatabase` does not promise a new embedding for the selected excerpt. Require
explicit naming, confirmation that the cluster contains one voice, at least ten seconds
of non-overlapping attributed speech, and an unchanged cluster. Corrected/mixed clusters cannot enroll; keep manual naming available and enroll from a
clean cluster in another import. Dedicated reprocessing is deferred (2026-09-10 simplification). Any later attribution correction invalidates
profiles whose source attribution revision no longer matches. Naming remains available.

**Why:** A short clean preview cannot remove contamination from an averaged cluster.
**Alternative:** Automatic profile updates from suggestions would reinforce identification errors.

Sources: [result types](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/Diarizer/Core/DiarizerTypes.swift),
[diarization guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md),
[reconstruction](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/Diarizer/Offline/Utils/OfflineReconstruction.swift).
These main-branch references explain behavior; the adapter audit must confirm it at the pinned baseline.

## D4 — Explicit model setup and an offline inference boundary

**Decision:** A model installer is the only audio-module component with network access.
Download immutable-revision assets against a checked-in size/hash manifest into temporary
storage, verify them, then atomically activate. The manifest includes all ASR bundles and
vocabulary plus diarization segmentation, FBank, embedding, PLDA model and PLDA parameters.
Loading uses explicit local model constructors; inference never invokes download helpers.
Missing/corrupt assets produce a setup-required error while preserving existing good installs.

Do not call `prepareModels()` during offline inference: its retry path can download/purge.
Do not assume main's `ModelHub.offlineMode` is available at v0.12.4. Validate the local-only
loading path with network denied after setup.

Sources: [ASR local loading](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ManualModelLoading.md),
[offline model bundle](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerModels.swift),
[tagged manager](https://github.com/FluidInference/FluidAudio/blob/v0.12.4/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift).

## D5 — Local meeting flow and user-owned storage

**Decision:** Add a Meetings mode and `AppState+Meetings`; keep local processing outside
existing API-key-gated summary jobs. Reuse file-channel styles after explicit review.
Use library-relative `.meetings/` storage for retained audio, editable meeting documents,
and participant catalog; export immutable Markdown revisions under `source/`.
Model caches live in Application Support, independent of the chosen library.

**Why:** `enqueueFiles`/`runJob` and existing drop views require an API key. Bootstrap also
opens key settings automatically; local Meetings must be reachable without that step.
`LibraryStore` exposes every nonhidden file in `source/`, so audio/JSON do not belong there.
`prepareFromArchive` expects a readable transcript at `sourceRef`, not audio or JSON.
**Alternative:** Reusing `archiveFile` for required audio persistence is unsafe because that
helper tolerates copy failure. Meeting imports need transactional, failure-reporting copies.

Evidence: `Sources/SumbeeKit/State/AppState+Jobs.swift`, `AppState.swift`,
`Services/LibraryStore.swift`, `Services/SummarizationEngine.swift`, and
`docs/swift-macos-learnings.md` (all relative to repository root).

## D6 — Immutable summary input and bounded first release

**Decision:** Each explicit export/new summary saves the reviewed text with the latest
confirmed catalog names into a new uniquely named snapshot before enqueueing. Preserve the
snapshot for retries/regeneration and reference it from the summary. Later corrections
create a new revision. A meeting-specific prepared-input policy rejects oversize input
before the API call; generic text/YouTube retain existing behavior. Use the same prompt
assembly and budget calculation for geek-mode preview, normal execution, and regeneration.
Offer a built-in Meeting Notes style without replacing user-edited prompts.

**Why:** Existing `finish` truncates large inputs with a notice. A meeting summary that
quietly omits the end can lose decisions and action owners. Chunked summarization is a
separate feature; selecting a larger-context model is the initial recovery action.
**Alternative:** Feeding mutable working transcripts would change evidence under saved notes.

Evidence: `Services/SummarizationEngine.swift`, `Services/PromptBuilder.swift`,
`Services/DefaultStyles.swift`, and `State/AppState+Jobs.swift`.

## Validation decisions

Use the reference hardware and acceptance targets in SC-001–SC-006. Development and held-out
recordings must be separate; include unfamiliar voices and microphone changes. Record WER,
diarization error, match precision/coverage, runtime, and peak memory. Peak process memory
should stay within 6 GiB on the reference machine; this is an engineering target to measure.
Missing real recordings are an implementation-validation dependency, not a reason to fabricate
results. Begin with an integration spike and keep all benchmark results marked pending until run.
