# Tasks: Local Meeting Transcription & Participants

**Feature:** `008-meeting-transcription` | **Input:** [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts](contracts/).

**Status:** All work pending. Tests are required by the spec and constitution. Each task below is implementation work; this planning pass has not run it.

Paths are repository-relative. `[P]` marks independent files after their prerequisites. `[USn]` identifies the user story. C01–C12 are quoted from the data model where implemented.

## Phase 1: Setup

Audit the pinned integration and define reproducible local evaluation inputs.

- [ ] T001 Audit FluidAudio v0.12.4, resolve its immutable commit and full transitive graph, vendor source/artifacts with local references in `Vendor/FluidAudio/` and `Package.swift`, and record revisions/licenses/patches in `Vendor/README.md`; prove an empty-cache offline build (research D1; FR-002).
- [ ] T002 Create `Resources/Models/meeting-models.json` with revision-pinned ASR bundles/vocabulary and all offline diarization assets, byte counts, SHA-256 hashes and licenses; verify the manifest against the chosen SDK pin (D4; FR-002).
- [ ] T003 Define separate development/enrollment/held-out fixture inventory and metric methodology in `specs/008-meeting-transcription/validation-results.md`; obtain local consented recordings and record hashes, reference hardware and pending outcomes without committing private audio (SC-002–SC-004).

## Phase 2: Foundation

Complete these contracts and the local SDK boundary before UI stories.

- [ ] T004 Add meeting/turn/speaker models and schema validation in `Sources/SumbeeKit/Models/Meeting.swift`: “IDs are UUIDs and remain stable across save/reload.” “Persisted documents use schemaVersion 1; unsupported versions or corrupt content fail without overwriting the original.” “reviewRevision and attributionRevision are positive integers; review edits increment the former and attribution edits also increment the latter.” “confirmedParticipantID is nullable; suggestedParticipantID never becomes confirmed without user action.” “Durable states are queued, importing, awaitingModels, transcribing, diarizing, assembling, ready, noSpeech, failed, cancelled, or interrupted.” Require finite nonnegative durationSeconds; retain originalFilename/audioSHA256, modelFingerprint, expectedParticipantIDs and exportedRevisions (FR-004/005/008/012/016).
- [ ] T005 Add installer/local-loader tests in `Tests/SumbeeKitTests/MeetingModelManagerTests.swift` for verified activation, cancellation, corrupt/missing assets, retained good installs, and no inference-triggered downloader call (FR-002/003).
- [ ] T006 Implement `Sources/SumbeeKit/Services/Meetings/MeetingModelManager.swift` with explicit staged download/hash verification/activation and local-only model construction; keep prior valid installs on failure and store caches in Application Support (FR-002/003).
- [ ] T007 Define `Sources/SumbeeKit/Services/Meetings/MeetingTranscribing.swift` with app-owned text/timing/interval/embedding results, fingerprint, stage events, errors and cancellation; no SDK types or network capabilities escape (FR-002/004/005).
- [ ] T008 Implement `Sources/SumbeeKit/Services/Meetings/FluidAudioTranscriber.swift` using the audited pin: local model handles, sequential ASR/diarization, subword timings, speakerDatabase and honest stage progress; prohibit prepareModels/download helpers during inference and audit memory/cancellation behavior (FR-002/004/005/015).

## Phase 3: US1 — Local import and review (P1, MVP)

Independent test: no API key/network after setup; import, play, correct, restart and reopen a two-speaker recording.

- [ ] T009 [P] [US1] Add word/interval fixtures in `Tests/SumbeeKitTests/TranscriptAssemblerTests.swift` for subwords, missing timings, gaps, overlap, and ties, proving no recognized text is dropped (FR-005/006).
- [ ] T010 [P] [US1] Add temporary-library tests in `Tests/SumbeeKitTests/MeetingStoreTests.swift` for failed copies, interrupted atomic writes, corruption, schema compatibility, silence, and revision persistence (FR-001/004/006/012/016).
- [ ] T011 [US1] Implement `Sources/SumbeeKit/Services/Meetings/TranscriptAssembler.swift` including token aggregation, surrounding-segment/untimed fallback and unknown attribution: “Turn bounds are both null or finite seconds satisfying 0 <= start <= end <= duration; untimed turns retain their text and order.” “Transcript text is preserved through attribution edits; a no-speech result has zero turns and an explicit status.” (FR-005/006).
- [ ] T012 [US1] Implement `Sources/SumbeeKit/Services/Meetings/MeetingStore.swift` with verified local audio copy, hidden sidecars, validated atomic JSON, restart recovery, immutable Markdown export and Reveal files: “Persisted documents use schemaVersion 1; unsupported versions or corrupt content fail without overwriting the original.” “Persisted asset paths are library-relative and cannot escape the library root; summary sourceRef points to an immutable Markdown revision.” (FR-001/004/006/012/016).
- [ ] T013 [US1] Create opt-in model evaluation in `Tests/SumbeeKitTests/MeetingModelEvaluationTests.swift`; run baseline clean/in-room/overlap/60-minute recordings and record WER, DER, runtime and peak memory in `specs/008-meeting-transcription/validation-results.md` before UI expansion; tune/document failures (SC-002/003).
- [ ] T014 [US1] Implement serial queue/stages and durable interrupted-state recovery in `Sources/SumbeeKit/State/MeetingProcessingState.swift`; capture library root per job, acknowledge cancellation, reject late results, and wait for an uncancellable SDK call before the next inference (FR-004/015/016).
- [ ] T015 [US1] Add `Sources/SumbeeKit/State/AppState+Meetings.swift`; update `AppState.swift`, `Models/InputMode.swift`, `Sources/SumbeeKit/Views/MainPanelView.swift`, and `Sources/SumbeeKit/Views/DropZoneView.swift` for Meetings, exhaustive routing, mixed-file classification and no-key local access while preserving text/YouTube behavior (FR-001/003/004).
- [ ] T016 [US1] Build `Sources/SumbeeKit/Views/Meetings/MeetingModePanel.swift` and `MeetingModelSetupView.swift` with picker/drop, saved meeting list, setup size/action, per-stage progress, cancel/retry and recoverable errors (FR-001/003/004/015).
- [ ] T017 [US1] Build `Sources/SumbeeKit/Views/Meetings/MeetingReviewView.swift` with local timestamp/nearby playback, text edits, individual turn reassignment including new speaker creation, label merge, and saved revision updates in `MeetingStore.swift`; preserve recognized text (FR-005/006).
- [ ] T018 [US1] Add no-key/no-network local-flow and cancellation tests in `Tests/SumbeeKitTests/MeetingProcessingTests.swift`; update `PlaylistTests.swift` mode enumeration expectations and verify mixed batches plus restart recovery (FR-001/003/004/015; SC-001).

## Phase 4: US2 — Participant catalog and naming (P1)

Independent test: create/assign/rename two same-named people, restart, merge/delete one, and inspect historical wording.

- [ ] T019 [US2] Add catalog/participant/profile/redirect types in `Sources/SumbeeKit/Models/Participant.swift`: “IDs are UUIDs and remain stable across save/reload.” “Participant names are trimmed, nonempty, and at most 120 characters; duplicate names are allowed.” “Persisted documents use schemaVersion 1; unsupported versions or corrupt content fail without overwriting the original.” “Merge redirects are acyclic and resolve to one participant or a deleted tombstone; deletion removes that participant's usable profiles.” Define nullable meeting links and versioned profile provenance per data-model.md (FR-007/008/012).
- [ ] T020 [US2] Add catalog add/rename/merge/delete/corruption/reload tests in `Tests/SumbeeKitTests/ParticipantStoreTests.swift`; cover duplicate names, redirect chains, tombstones, and historical snapshots (FR-007/008/012/016).
- [ ] T021 [US2] Implement atomic catalog operations in `Sources/SumbeeKit/Services/Meetings/ParticipantStore.swift`, retaining historical names and resolving retired IDs through acyclic redirects; catalog selection follows library selection (FR-007/008/012/016).
- [ ] T022 [US2] Build `Sources/SumbeeKit/Views/Meetings/ParticipantsView.swift` with search/add/rename/merge/delete and profile removal, including sample/meeting context for duplicate names; expose it from Meetings (FR-007/009/012).
- [ ] T023 [US2] Build `Sources/SumbeeKit/Views/Meetings/SpeakerAssignmentView.swift` and wire `Sources/SumbeeKit/State/AppState+Meetings.swift` for selecting/creating and confirming a participant: “confirmedParticipantID is nullable; suggestedParticipantID never becomes confirmed without user action.” Persist display-name snapshots separately from current catalog names (FR-008).
- [ ] T024 [US2] Add assignment/revision tests in `Tests/SumbeeKitTests/MeetingParticipantTests.swift`; connect `MeetingStore.swift`/`ParticipantStore.swift` so participant merge/delete/profile removal preserves saved wording and summary sources and never reactivates deleted recognition data (FR-006/008/009/012).

## Phase 5: US3 — Confirmed voice reuse (P1)

Independent test: enroll in meeting A, restart, suggest in held-out B, reject an unfamiliar voice, and invalidate stale profiles.

- [ ] T025 [P] [US3] Add matching fixtures in `Tests/SumbeeKitTests/ParticipantMatcherTests.swift` for incompatible vectors/fingerprints, unknown voices, ambiguous top-two participants, attendee restriction, and multiple profiles per person (FR-010/011).
- [ ] T026 [P] [US3] Add enrollment/staleness tests in `Tests/SumbeeKitTests/VoiceProfileTests.swift` proving name assignment alone creates no profile, suggestions cannot train, attribution edits invalidate old sources, and short/mixed/corrected clusters cannot enroll (FR-009/011/012).
- [ ] T027 [US3] Implement `Sources/SumbeeKit/Services/Meetings/ParticipantMatcher.swift` with compatible-profile filtering, normalized cosine scores, best-profile-per-person ranking, minimum threshold and distinct-person separation margin; missing/ambiguous candidates abstain (FR-010/011).
- [ ] T028 [US3] Implement confirmed enrollment and eligibility in `Sources/SumbeeKit/Services/Meetings/ParticipantStore.swift`: “Profile vectors are finite, nonzero, normalized, dimension-compatible, and fingerprint-compatible; their source attribution revision must still match.” “Enrollment requires an explicitly confirmed unchanged single-voice cluster with at least 10 seconds of non-overlapping speech.” Persist source meeting/cluster/revision and versioned preprocessing; never derive a claimed excerpt embedding from a whole-cluster centroid (FR-009/011/012).
- [ ] T029 [US3] Wire optional attendees, suggested-versus-confirmed names, accept/reject actions, and “Remember this voice” with explicit eligibility reasons in `Sources/SumbeeKit/State/AppState+Meetings.swift`, `Sources/SumbeeKit/Views/Meetings/SpeakerAssignmentView.swift` and `ParticipantsView.swift`; keep manual naming available (FR-009/010/011).
- [ ] T030 [US3] Extend `Tests/SumbeeKitTests/MeetingModelEvaluationTests.swift` for separate enrollment/development/held-out identity evaluation; freeze per-fingerprint thresholds/margins in `Resources/Models/meeting-models.json` and record precision, coverage, unfamiliar-voice/microphone-change outcomes in `specs/008-meeting-transcription/validation-results.md` (SC-004/005).

## Phase 6: US4 — Notes and traceable actions (P2)

Independent test: summarize an immutable reviewed snapshot, verify owners/dates/times, edit the meeting, and regenerate the original summary.

- [ ] T031 [US4] Add captured-request/revision tests in `Tests/SumbeeKitTests/MeetingSummaryTests.swift`: no API call before explicit action; generic unconfirmed names; no embeddings/audio/local paths; stable retry/regeneration input; no meeting truncation (FR-003/008/013/014).
- [ ] T032 [US4] Implement `Sources/SumbeeKit/Services/Meetings/MeetingSummaryInputBuilder.swift` to atomically export and reuse the exact reviewed revision and return its text/sourceRef, enforcing “Persisted asset paths are library-relative and cannot escape the library root; summary sourceRef points to an immutable Markdown revision.” (FR-013).
- [ ] T033 [US4] Extend `Sources/SumbeeKit/Services/SummarizationEngine.swift` prepared-input policy and add `Sources/SumbeeKit/Services/SummaryInputBudget.swift`; preflight full meeting text before API calls, reject oversize with model-selection recovery, detect meeting snapshot metadata on regeneration, and preserve generic input defaults (FR-013).
- [ ] T034 [US4] Update `Sources/SumbeeKit/Services/PromptBuilder.swift` and `Sources/SumbeeKit/State/AppState+Jobs.swift` to use shared meeting context/budget assembly consistently in preview, execution, retry and regeneration; require evidence times and distinguish generic from confirmed speaker names (FR-013/014).
- [ ] T035 [US4] Add an idempotent opt-in Meeting Notes default-style entry in `Sources/SumbeeKit/Services/DefaultStyles.swift` and its creation action in `Sources/SumbeeKit/Views/Meetings/MeetingModePanel.swift`; require task/established owner/date/evidence and preserve user-edited styles (FR-014).
- [ ] T036 [US4] Wire the explicit review-to-summary action in `Sources/SumbeeKit/State/AppState+Meetings.swift` and `Sources/SumbeeKit/State/AppState+Jobs.swift`, using file-channel styles, immutable prepared input bound to the source library root and existing key setup/queue/library save; reject a root mismatch before execution; local meeting work stays available without a key (FR-003/013/014).
- [ ] T037 [US4] Extend `Tests/SumbeeKitTests/MeetingSummaryTests.swift` and `PromptBuilderTests.swift` for unknown owners/dates in prompt instructions, preview/request equivalence, missing-source errors, historical snapshots, oversize handling and unchanged document/YouTube defaults (FR-013/014; SC-006).

## Phase 7: Cross-cutting validation and documentation

Complete the requested scope only after all four stories and measured gates pass.

- [ ] T038 Add relocation/interruption tests in `Tests/SumbeeKitTests/MeetingPersistenceTests.swift` for whole-library moves, selection changes mid-job, atomic catalog writes, stale profiles after interrupted edits, manual source deletion and corrupt schemas (FR-012/016; SC-005).
- [ ] T039 Verify keyboard/VoiceOver labels, focus, light/dark, stage progress, playback and cancellation responsiveness across `Sources/SumbeeKit/Views/Meetings/`; record fixes and measured results in `specs/008-meeting-transcription/validation-results.md` (FR-015; SC-002).
- [ ] T040 Run `swift build`, `swift test`, isolated empty-cache offline build, and network-denied model loading/inference; record commands/environment/results in `specs/008-meeting-transcription/validation-results.md` and resolve failures (FR-002/003; SC-001).
- [ ] T041 Execute `specs/008-meeting-transcription/quickstart.md` including 60-minute/quality/held-out tests and real Meeting Notes evaluation with configured summarization; report SC-001–SC-006 and <=6 GiB memory target in `validation-results.md`, with zero fabricated passing results.
- [ ] T042 Update `README.md`, `CHANGELOG.md`, `CLAUDE.md`, and `specs/008-meeting-transcription/quickstart.md` for shipped behavior, model install/storage, limitations and user validation; retain module 002 supersession and mark task completion only from evidence.

## Dependencies and implementation strategy

Execute Setup -> Foundation -> US1 -> US2 -> US3 -> US4 -> cross-cutting validation. US1 is the first useful MVP; participant reuse remains required for the full requested feature. T013 is a model-feasibility checkpoint before UI expansion. Failure requires tuning or a documented design revision, not skipping the checkpoint.

US2 catalog services can be exercised with saved-meeting fixtures; US3 depends on US2 identities/profile storage and US1 clusters. US4 needs US1 immutable transcript output and US2 confirmed names; it can be developed alongside US3 after those dependencies are stable. Shared `AppState+Meetings.swift` edits must be integrated sequentially.

Write meaningful deterministic tests before their corresponding implementation and verify they fail for the missing behavior. Run the completed story’s independent acceptance scenario before advancing; finish with the full quickstart. Commit/push only on user request.

## Parallel examples

- **US1:** T009 assembler fixtures and T010 storage fixtures can proceed together after Foundation.
- **US2:** After T019, catalog UI design in T022 can use a fixture while T020/T021 establish persistence; integrate only after store behavior passes.
- **US3:** T025 matching fixtures and T026 profile eligibility fixtures can proceed together after US2.
- **US4:** Once T033 defines the prepared-input policy, T035 style work can proceed alongside T034 prompt integration; keep common view/state edits sequential.

## Requirement coverage

| Requirement | Tasks |
|---|---|
| FR-001 | T010, T012, T015, T016, T018 |
| FR-002 | T001, T002, T005–T008, T040 |
| FR-003 | T005, T006, T015, T016, T018, T031, T036, T040 |
| FR-004 | T004, T007, T008, T010, T012, T014–T016, T018 |
| FR-005 | T004, T007–T009, T011, T017 |
| FR-006 | T009–T012, T017, T024 |
| FR-007 | T019–T022 |
| FR-008 | T004, T019–T021, T023, T024, T031 |
| FR-009 | T022, T024, T026, T028, T029 |
| FR-010 | T025, T027, T029 |
| FR-011 | T025–T029 |
| FR-012 | T004, T010, T012, T019–T022, T024, T026, T028, T038 |
| FR-013 | T031–T034, T036, T037 |
| FR-014 | T031, T034–T037 |
| FR-015 | T008, T014, T016, T018, T039 |
| FR-016 | T004, T010, T012, T014, T020, T021, T038 |
| SC-001 | T018, T040, T041 |
| SC-002 | T003, T013, T039, T041 |
| SC-003 | T003, T013, T041 |
| SC-004 | T003, T030, T041 |
| SC-005 | T020, T024, T026, T030, T038, T041 |
| SC-006 | T031, T037, T041 |
