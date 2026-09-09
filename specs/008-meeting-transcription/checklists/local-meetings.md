# Local Meeting Requirements Checklist: Meeting Transcription & Participants

**Purpose**: Review requirement quality for offline privacy, participant identity, persistence, and failure recovery before implementation.
**Created**: 2026-09-09
**Feature**: [spec.md](../spec.md)
**Depth / Audience**: Standard; feature reviewer before implementation.
**Scope basis**: The user's approved on-device audio workflow, reusable participant catalog, and explicit text-only summary handoff. Live recording, sync, and local LLM implementation remain excluded.

**Note**: Generated using the installed `speckit-checklist` skill and its resolved checklist template.
**Review Ownership**: This is a reviewer-owned requirements-quality review artifact. Mark an item `[x]` only when the reviewer determines its criterion is satisfied.
**Marker Semantics**: `[x]` means requirements quality has been reviewed and satisfied; it does not mean implementation is complete. All generated items are intentionally unchecked.

## Requirement Completeness

- [ ] CHK001 Are the permitted network operations and prohibited audio/profile transfers explicitly bounded? [Completeness, Spec §FR-002/FR-013]
- [ ] CHK002 Are all local capabilities that must remain available without a key or network enumerated? [Completeness, Spec §FR-003]
- [ ] CHK003 Are requirements for explaining the local-audio/cloud-text boundary in the interface specified? [Completeness, Gap, Constitution §III]
- [ ] CHK004 Are initial model setup, failed setup, and retention of a previously valid installation covered? [Completeness, Spec §User Story 1, Data Model §Model installation and summary input, Processing Contract §Services]
- [ ] CHK005 Are participant naming, identity confirmation, voice enrollment, and profile removal defined as distinct operations? [Completeness, Spec §FR-007–FR-011]
- [ ] CHK006 Are durable recovery requirements defined for every queue stage, including records whose audio has not yet been retained? [Completeness, Gap, Spec §FR-004, Data Model §Meeting document]

## Requirement Clarity

- [ ] CHK007 Is usable enrollment speech defined with explicit duration, overlap, confirmation, and correction criteria? [Clarity, Spec §FR-009, Data Model §C09]
- [ ] CHK008 Are suggested identities clearly distinguished from confirmed names in review and exported text? [Clarity, Spec §FR-008/FR-011, Processing Contract §User actions]
- [ ] CHK009 Is the scope of voice-profile invalidation after an attribution edit clear, including unaffected speakers in the same meeting? [Clarity, Ambiguity, Spec §FR-009, Data Model §C06/C08]
- [ ] CHK010 Are rename effects on existing meeting names, future exports, and already saved transcript revisions unambiguous? [Clarity, Conflict, Spec §FR-007/FR-008, Data Model §Participant catalog]
- [ ] CHK011 Is cancellation acknowledgement distinguished from the eventual end of processing and the next queued job? [Clarity, Spec §SC-002, Processing Contract §Services]

## Requirement Consistency

- [ ] CHK012 Are rename and re-export requirements consistent with immutable snapshots and revision numbering? [Consistency, Conflict, Data Model §C06/Participant catalog, Persistence Contract §Atomic ownership]
- [ ] CHK013 Are requirements for reprocessing corrected speaker clusters consistent with preserving reviewed content and historical summaries? [Consistency, Gap, Spec §FR-009/FR-013, Research §D3, Data Model §Meeting document]
- [ ] CHK014 Are participant merge, deletion, and profile-removal semantics consistent across identities, recognition eligibility, and historical wording? [Consistency, Spec §FR-007/FR-009/FR-012, Data Model §C12]
- [ ] CHK015 Are immutable source selection and whole-input size requirements consistent across initial summary, preview, retry, and regeneration? [Consistency, Spec §FR-013, Processing Contract §Summary contract]
- [ ] CHK016 Are library selection changes distinguished from relocating the whole library for both local processing and summary requests? [Consistency, Spec §FR-016, Persistence Contract §Library changes and deletion, Processing Contract §Summary contract]

## Acceptance Criteria Quality

- [ ] CHK017 Are runtime, responsiveness, cancellation, and memory targets tied to named hardware and a defined measurement scope? [Measurability, Spec §SC-002/Assumptions, Plan §Technical Context]
- [ ] CHK018 Are transcription and diarization scoring conventions specified sufficiently to make the stated accuracy thresholds reproducible? [Measurability, Gap, Spec §SC-003, Tasks §T003]
- [ ] CHK019 Are identity precision and coverage denominators, eligibility rules, and minimum evaluation-set size defined independently of suggestions offered? [Measurability, Gap, Spec §SC-004, Tasks §T003/T030]
- [ ] CHK020 Are summary-quality criteria defined for both stated and absent owners/dates and for turns without precise evidence times? [Measurability, Spec §SC-006/Edge Cases]
- [ ] CHK021 Are unmeasured model assumptions distinguished from accepted results, with explicit handling of failed quality targets? [Acceptance Criteria, Spec §Assumptions, Plan §Delivery strategy]

## Scenario and Edge Case Coverage

- [ ] CHK022 Are unsupported, corrupt, silent, and partly timed recordings covered without promising invented speech or timestamps? [Coverage, Spec §Edge Cases/FR-005]
- [ ] CHK023 Are multiple-file imports, independent failures, and interrupted pre-copy records covered by the recovery requirements? [Coverage, Gap, Spec §User Story 1/FR-004]
- [ ] CHK024 Are unknown voices, duplicate names, ambiguous suggestions, empty attendee selection, and incompatible profiles addressed? [Coverage, Spec §User Stories 2–3, Data Model §Meeting document/Voice profile]
- [ ] CHK025 Is the user recovery path for fresh enrollment after a corrected or mixed speaker cluster explicitly specified? [Coverage, Gap, Spec §FR-009/FR-011, Research §D3]
- [ ] CHK026 Are partial writes, insufficient storage, missing source files, and corrupt or future-version records covered without destructive fallback? [Coverage, Spec §FR-016/Edge Cases, Persistence Contract §Atomic ownership/Reopening]
- [ ] CHK027 Are retained audio, raw recognition data, reusable profiles, and exported transcripts distinguished in deletion and retention requirements? [Coverage, Spec §FR-012, Persistence Contract §Library changes and deletion]

## Non-Functional Requirements and Dependencies

- [ ] CHK028 Are keyboard access, focus, assistive labels, light/dark appearance, and responsiveness specified for all new meeting and participant views? [Completeness, Spec §FR-015, Constitution §VI, Tasks §T039]
- [ ] CHK029 Are offline installation/build boundaries and model provenance, licensing, and version compatibility responsibilities explicit? [Dependencies, Spec §FR-002, Plan §Constitution Check, Tasks §T001/T002]
- [ ] CHK030 Are consented evaluation recordings, separate enrollment/development/held-out data, and the point at which these inputs are required documented? [Dependencies, Assumption, Spec §Assumptions, Tasks §T003/T013/T030]

## Notes

- This run creates 30 items; it does not evaluate or approve their checkbox state.
- References use section names and requirement IDs in the linked feature documents. `[Gap]`, `[Ambiguity]`, and `[Conflict]` identify aspects requiring reviewer attention, not implementation failures.
- Mark items `[x]` only after review determines their requirement-quality criterion is satisfied. Leave unresolved items unchecked and add evidence or findings inline.
- `speckit-implement` reads checklist state as a gate and must not modify markers.
- `checklists/requirements.md` has a separate built-in lifecycle maintained by `speckit-specify` and `speckit-clarify`.
- No extension hooks were configured for this run.

## User decisions — 2026-09-10

These decisions address review findings without changing reviewer-owned checkbox states.

- CHK010/CHK012 (I1): every explicit new export resolves the latest confirmed participant
  name into a new saved file. Existing summary retries reuse their original file. See
  [catalog and export rules](../data-model.md) and [persistence](../contracts/persistence.md).
- CHK006/CHK023 (U1): copying is transient; only verified audio plus the initial record
  create a saved job. Failed/interrupted copies leave no job. See the persistence contract.
- CHK009/CHK013/CHK025 (U2): conservative meeting-level profile invalidation; no dedicated
  reprocessing workflow. Manual naming remains available, and another normal import can
  provide a clean enrollment source. See [processing actions](../contracts/processing.md).
- CHK017–CHK019 (A1): scoring conventions are internal and fixed in
  [quickstart.md](../quickstart.md); users get simple progress, editable name suggestions,
  and errors with direct next actions, without scores or threshold controls (FR-015).
