# Implementation Plan: Local Meeting Transcription & Participants

**Branch**: `008-meeting-transcription` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Input**: Approved direction in [brief.md](brief.md), expanded into feature 008.
**Status**: Design complete; all implementation and model-validation tasks remain pending.
Feature 008 supersedes module 002; live recording and licensing are deferred.

## Summary

Add a Meetings mode for local audio import, transcript review, participant naming, and
confirmed voice enrollment. FluidAudio performs ASR and within-meeting diarization;
app-owned matching suggests catalog identities. Save immutable reviewed transcript
revisions and send only their text through the existing summarization pipeline on request.

## Technical Context

**Language/Version**: Existing Swift 6 toolchain / Swift 5 language mode; SwiftUI + AppKit.

**Primary Dependencies**: FluidAudio v0.12.4 audited baseline, Parakeet TDT 0.6B v2,
OfflineDiarizerManager; Core ML and AVFoundation. Vendor the pinned dependency graph.
See [research.md](research.md) D1–D4 for APIs and first-task pin verification.

**Storage**: Versioned local JSON and retained audio in `<library>/.meetings/`; immutable
Markdown revisions under `<library>/source/`; model assets in Application Support.

**Testing**: Existing Swift tests plus deterministic model/store/matching/summary-boundary
fixtures; manual model evaluation on consented local audio with recorded ground truth.

**Target Platform**: macOS 15+, Apple Silicon; baseline M1 / 16 GB RAM.

**Project Type**: Native macOS desktop app; existing `SumbeeKit` library and `Sumbee` executable.

**Performance Goals**: SC-002 latency/runtime; peak process memory target <=6 GiB;
one inference job at a time; no fabricated inference percentage.

**Constraints**: Offline fresh builds, offline inference after explicit model setup,
no audio/profile upload, local workflows independent of API-key setup, existing styles retained.

**Scale/Scope**: Personal per-library catalog; 2–6 speakers and >=60-minute recordings;
no cross-device sync, live capture, video import, dedicated reprocessing, or calendar identity lookup.

## Constitution Check

**Before research: PASS.** The scoped FluidAudio/model-download exception was already
approved for module 002 and is carried forward to 008 in constitution 1.1.1.
**After design: PASS, subject to implementation verification below.**

| Principle | Design response | Implementation evidence required |
|---|---|---|
| Native/offline build | SwiftUI/Core ML; vendor all source and artifacts | Empty-cache build with network denied |
| Testable core | Narrow adapter, pure assembler/matcher, actor-owned stores | Unit and service-boundary tests |
| Local-first privacy | Only installer downloads; only explicit summary sends text | Network-denied inference and captured API request |
| Secret handling | Existing Keychain/API-key flow applies only to summarization | No-key local flow and unchanged key tests |
| User-owned files | Local JSON/audio plus Markdown source revisions | Relocation/restart and corruption tests |
| Accessible native UI | Meetings/Participants views, stage progress, cancel | Keyboard, light/dark, responsiveness checks |
| Pragmatic tests | Deterministic logic tests and real-recording evaluation | Green suite and benchmark report |

No new principle exception is requested. Real model performance and packaging are not yet verified.

## Project Structure

### Documentation (this feature)

`brief.md`, `spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`,
`contracts/processing.md`, `contracts/persistence.md`, `tasks.md`, and
`checklists/requirements.md` live in `specs/008-meeting-transcription/`.

### Source Code (repository root; proposed additions)

```text
Vendor/FluidAudio/                    # pinned source and locally resolved dependencies
Vendor/README.md                      # revisions, licenses, reproducible vendoring notes
Resources/Models/meeting-models.json   # immutable model assets, sizes, hashes
Sources/SumbeeKit/
  Models/Meeting.swift                # meeting, turn, speaker, revision, durable job status
  Models/Participant.swift            # catalog, participant, profile, merge redirect
  Services/Meetings/
    MeetingTranscribing.swift         # app-owned SDK boundary and result types
    FluidAudioTranscriber.swift       # only SDK-dependent adapter
    MeetingModelManager.swift         # explicit installer and verified local loading
    TranscriptAssembler.swift         # token/word/turn attribution
    MeetingStore.swift                # audio copy, documents, restart, immutable snapshots
    ParticipantStore.swift            # catalog mutations and profile eligibility
    ParticipantMatcher.swift          # compatible-profile scoring and abstention
    MeetingSummaryInputBuilder.swift  # saved revision -> PreparedInput
  Services/SummaryInputBudget.swift  # shared preview/send size policy
  State/MeetingProcessingState.swift  # sequential local queue and cancellable stages
  State/AppState+Meetings.swift       # import/review/catalog/summary coordination
  Views/Meetings/
    MeetingModePanel.swift
    MeetingReviewView.swift
    SpeakerAssignmentView.swift
    ParticipantsView.swift
    MeetingModelSetupView.swift
Tests/SumbeeKitTests/                  # tests named for the corresponding services
```

**Structure Decision:** Extend the existing app, not a second executable or Python service.
Reuse `Job` only for explicit summarization. Add `InputMode.meetings`; make `MainPanelView`
routing exhaustive. Update no-key bootstrap/banner/drop handling so local features work
before API setup. Keep file/YouTube behavior and file-channel styles compatible.

## Processing and persistence boundaries

1. Stage and validate audio plus the initial meeting record, then atomically publish them
   into hidden meeting storage. Pre-copy jobs are transient; failures leave no saved job.
   Capture the library root per job; never use a mutable global root mid-job.
2. Verify local models, run ASR and offline diarization sequentially, assemble review turns,
   and save raw recognition provenance alongside editable turns. Cancellation may wait for
   the SDK's current call to return, but late results cannot overwrite user state.
3. Compare eligible whole-cluster embeddings with compatible catalog profiles; persist
   suggestions separately. Naming/confirmation changes the meeting; enrollment is a separate
   catalog mutation. Attribution revisions prevent stale profiles from being reused.
4. Review audio/text, merge labels, reassign turns, and explicitly enroll clean unchanged
   clusters. Ten seconds of non-overlapping attributed speech is the initial enrollment minimum.
5. Each explicit export/new summary saves a uniquely named Markdown snapshot using the
   latest confirmed participant names; existing summary retries reuse their saved file.
   Feed its text and library-relative
   `sourceRef` into summary preparation; require whole-input fit before sending. Reuse normal
   retry/save paths. Regeneration reads the same snapshot and meeting input policy.

Contracts define [processing and UI actions](contracts/processing.md) and
[on-disk ownership](contracts/persistence.md). [data-model.md](data-model.md) owns validation rules.

## Delivery strategy

- **Setup and foundation:** Audit/vendoring/model manifest; prove representative files; define
  model/store contracts and fixtures. Record baseline quality before investing in catalog UX.
- **US1 MVP:** No-key local import, durable transcript, playback and corrections.
- **US2:** Participant catalog, explicit naming, merge/delete behavior.
- **US3:** Remember voice, calibrated suggestions, rejection and version mismatch handling.
- **US4:** Immutable reviewed text -> notes/actions via existing styles and explicit API request.
- **Release validation:** Offline build/inference, long-file runtime/memory, held-out matching,
  interrupted writes, regression suite, and accessible native UI.

US1 is a useful milestone; the complete requested feature includes US2–US4. Benchmark failures
must be fixed or explicitly revisited before shipping; they are not hidden by high-confidence UI.

## Complexity Tracking

The existing FluidAudio exception covers vendored third-party code and explicit model setup.
An app-owned participant matcher is necessary because offline diarization returns meeting-local
clusters, not persistent people. Immutable transcript revisions preserve summary evidence.
These are bounded responsibilities; no general workflow engine or custom diarization is added.

## Simplicity decisions — 2026-09-10

Keep catalog names current at export without name-history or refresh UI. Persist imports only
after audio and the initial record are saved. Defer dedicated reprocessing: users can name
speakers manually and enroll voices from another normal import. Keep quality measurement
internal; present simple stages, editable names, and clear recovery actions in the app.
