# Feature Specification: Local Meeting Transcription & Participants

**Feature Branch**: `008-meeting-transcription`

**Created**: 2026-09-09

**Status**: Specified; implementation pending

**Input**: Restart the approved module 002 direction as feature 008: import meeting audio,
transcribe and distinguish speakers on-device, name participants, remember their voices
in a local catalog for future meetings, then summarize the reviewed transcript.

## Context and scope

This feature supersedes `002-recording-transcription`. Its [approved brief](brief.md)
provides context; this specification governs behavior. File import is the first release.
Live microphone/system recording, live captions, meeting bots, calendar integration,
video import, translation, and licensing are outside this feature. English is the quality
target; Chinese/Cantonese passages are best-effort and do not block release.

## User Scenarios & Testing

### User Story 1 — Import and review a meeting locally (Priority: P1)

A user drops an existing recording into Sumbee and gets a saved transcript showing
speaker turns and times. They can listen to an excerpt, correct text or speaker
attribution, and continue later without repeating transcription.

**Why this priority**: Creates a useful local transcript even without a summarization account.

**Independent Test**: With no summarization API key and networking disabled after model
setup, import a two-speaker recording, review it, restart the app, and reopen the result.

**Acceptance Scenarios**:

1. **Given** an `.m4a`, `.mp3`, or `.wav` file, **when** dropped or selected, **then**
   Sumbee processes it locally and displays progress, speaker turns, and timestamps.
2. **Given** missing models, **when** import starts, **then** the user sees download size
   and an explicit install action; cancellation leaves the original audio intact.
3. **Given** a detected speaker or turn, **when** its playback control is selected,
   **then** the corresponding original audio plays locally.
4. **Given** incorrect words, a mislabeled turn, or duplicate speaker labels, **when**
   corrected, **then** the saved transcript reflects the edit without losing other text.
5. **Given** a failed or interrupted import, **when** the app reopens, **then** its status
   is recoverable and retry is offered; incomplete output is never presented as complete.
6. **Given** several audio files, **when** dropped together, **then** they queue in order;
   cancelling or failing one does not cancel the others.

### User Story 2 — Name speakers and manage a participant catalog (Priority: P1)

A user assigns detected speakers to named people and maintains those people in one
searchable catalog. Naming a person and remembering their voice are separate actions.

**Why this priority**: Named contributions make notes and assigned work useful.

**Independent Test**: Using a saved meeting, create a participant, assign two turns,
rename them, restart, and verify the assignment; exercise merge and deletion separately.

**Acceptance Scenarios**:

1. **Given** an unnamed speaker, **when** the user selects an existing participant or
   creates one, **then** that meeting speaker is linked to the selected person.
2. **Given** the Participants screen, **when** searching, adding, or renaming a person,
   **then** changes persist across restarts; people with identical names remain distinct.
3. **Given** duplicate catalog entries, **when** merged, **then** references and compatible
   voice profiles resolve to the chosen surviving person, without duplicate identities.
4. **Given** a deleted participant or removed voice profile, **when** another meeting is
   processed, **then** the removed recognition data is no longer used; historical saved
   transcript wording and already generated summaries remain readable and unchanged.
5. **Given** a meeting with uncertain attribution, **when** the user leaves a speaker
   unnamed, **then** review, saving, and summarization remain available.

### User Story 3 — Reuse confirmed voices in later meetings (Priority: P1)

After naming a speaker, a user can remember their voice. Future meeting imports offer
suggested participant matches for review rather than silently asserting an identity.

**Why this priority**: Repeated meetings should require less manual speaker naming.

**Independent Test**: Enroll a named speaker from meeting A, restart, then process a
separate meeting B with that person and an unfamiliar voice; confirm and reject suggestions.

**Acceptance Scenarios**:

1. **Given** a confirmed speaker assignment with usable audio, **when** “Remember this
   voice” is selected, **then** a reusable local profile is saved. Naming alone saves no profile.
2. **Given** compatible saved profiles, **when** a new meeting is processed, **then**
   sufficiently strong, unambiguous matches appear as suggestions pending confirmation.
3. **Given** optional expected attendees, **when** selected, **then** suggestions are
   restricted to that set, while unfamiliar speakers can remain unknown or be added.
4. **Given** a rejected suggestion, **when** corrected, **then** the assignment is fixed;
   an unconfirmed guess never trains or updates a participant profile.
5. **Given** incompatible voice-profile versions, too little clear speech, or overlapping
   speech, **when** reuse is attempted, **then** uncertain recognition is withheld and
   the user can still name the speaker manually or enroll a fresh usable speaker cluster.

### User Story 4 — Generate notes and traceable action items (Priority: P2)

A user sends a reviewed transcript through the existing summary styles to produce
notes, decisions, and action items with evidence in the meeting.

**Why this priority**: Builds on existing summarization after local review is useful.

**Independent Test**: Summarize a reviewed meeting containing one explicit owner/date
and one unassigned task; compare notes with the transcript and revisit the cited times.

**Acceptance Scenarios**:

1. **Given** a reviewed transcript, **when** the user chooses a style and summarizes,
   **then** the existing summarization flow receives that saved text with confirmed names.
   If the entire transcript exceeds the selected model’s input budget, explain the limit
   before sending and let the user choose a larger-context model; do not truncate it.
2. **Given** no API key, **when** summarization is requested, **then** existing key setup
   applies; local import, editing, and participant management remain available.
3. **Given** a meeting-notes style, **when** extracting actions, **then** its instructions
   require the task, owner and due date only when established, and supporting timestamps.
4. **Given** an unconfirmed name suggestion, **when** summarizing, **then** the transcript
   uses the generic speaker label rather than treating the suggested name as a fact.
5. **Given** edits after a summary was generated, **when** saved, **then** existing summaries
   are retained; the user may generate a new summary from the new transcript revision.

### Edge Cases

- Corrupt, unsupported, silent, truncated, or unreadable audio: explain the failure and
  preserve the original; silence produces an explicit “No speech detected” result.
- Missing timestamps: preserve text and order, label affected turns untimed, and avoid
  invented precise citations; nearby audio playback remains available.
- Short interjections, background voices, and simultaneous speech: preserve recognized
  words and uncertainty; automatic diarization does not guarantee recovery of all overlapping words.
- One person split into multiple speakers, or multiple people merged: allow relabeling
  individual turns as well as merging detected speaker labels.
- Insufficient disk space, cancelled downloads, app termination, or library relocation:
  preserve completed records and expose retryable failures without deleting user audio.
- Duplicate participant names: selection uses stable identities, with sample playback
  or meeting context to distinguish them.
- A catalog or meeting file with an unsupported version/corrupt content: report the
  affected record and preserve its bytes; never replace the catalog with an empty one.

## Requirements

### Functional Requirements

- **FR-001**: Accept audio through drag-and-drop and a file picker, initially `.m4a`,
  `.mp3`, and `.wav`; preserve the source and report unsupported/unreadable files.
- **FR-002**: Perform audio processing and voice recognition locally; only explicit
  model setup may download assets. Audio and voice profiles must never be uploaded.
- **FR-003**: Keep import, playback, editing, catalog management, and recognition usable
  without a summarization API key or network after model installation.
- **FR-004**: Queue imports, show stage/progress, allow cancellation and retry, and
  recover interrupted jobs; expose only complete saved transcripts as ready for summary.
- **FR-005**: Produce ordered, timestamped speaker turns, preserving recognized speech
  when attribution is uncertain and allowing unknown speaker labels.
- **FR-006**: Support local excerpt playback, text correction, turn reassignment, and
  merging detected speakers; persist edits and retain the imported audio for review.
- **FR-007**: Provide a searchable participant catalog with add, rename, merge, and delete;
  distinct participants may share a display name.
- **FR-008**: Link a meeting speaker to a catalog participant through explicit confirmation;
  preserve generic labels until confirmation and retain historical transcript wording.
- **FR-009**: Save voice profiles only through “Remember this voice” on confirmed usable
  speech; allow profile removal without deleting the participant. Profiles derived from subsequently corrected speaker attribution must
  become ineligible for reuse until explicitly re-enrolled.
- **FR-010**: Suggest names from compatible saved profiles in later meetings, optionally
  restricted to expected attendees, and leave weak or ambiguous matches unknown.
- **FR-011**: Keep suggestions separate from confirmed assignments; only explicit confirmed
  enrollment may update profiles, and incompatible versions require fresh enrollment.
- **FR-012**: Persist meetings, catalog identities, and recognition data locally across
  restarts; deletion removes usable recognition data and preserves historical transcripts.
- **FR-013**: Save a readable timestamped transcript and route it through existing summary
  styles only on user request; summarization may send transcript text and prompts to its API. Preserve the exact reviewed revision used for
  each summary and reject oversized meeting inputs before sending rather than truncating.
- **FR-014**: Supply a meeting-notes style requiring decisions, action items, evidence
  timestamps, and unspecified owners/dates where absent; preserve existing user-edited styles.
- **FR-015**: Support recordings of at least 60 minutes and meetings with 2–6 speakers,
  with an interactive, keyboard-accessible interface during background processing.
- **FR-016**: Preserve completed records through interrupted writes and library moves;
  reject incompatible/corrupt data without resetting user settings or catalog data.

### Key Entities

- **Meeting**: A locally retained audio recording, processing status, reviewed transcript,
  and revision used when generating a summary.
- **Transcript Turn**: Recognized or edited text, start/end time, and meeting speaker.
- **Meeting Speaker**: An identity within one recording, optionally linked to a confirmed
  participant; suggestions are tracked separately.
- **Participant**: A persistent catalog identity with an editable display name.
- **Voice Profile**: Confirmed local voice characteristics and version information used
  to suggest future matches, removable independently of the participant. Profiles derived from subsequently corrected speaker attribution must
  become ineligible for reuse until explicitly re-enrolled.
- **Model Installation**: Locally installed processing assets and their verified versions.

## Success Criteria

### Measurable Outcomes

These are implementation acceptance targets, not claims about measurements already taken.

- **SC-001**: After model setup, each supported format completes import, local review,
  save, restart, and reopen with no network and no summarization API key.
- **SC-002**: On the reference Mac, a 60-minute meeting completes within 60 minutes;
  controls acknowledge input within one second and cancellation acknowledges within two.
- **SC-003**: On the annotated clean-English evaluation set, transcription word error
  rate is at most 15% and speaker diarization error rate is at most 20%; harder room and
  overlap recordings are measured separately, with editable output in every case.
- **SC-004**: On held-out meetings with enrolled and unfamiliar speakers, at least 95%
  of offered identity suggestions are correct. Report suggestion coverage alongside
  precision; achieve at least 50% coverage of eligible enrolled speakers so abstaining
  on everything cannot satisfy the criterion.
- **SC-005**: All scripted correction, enrollment, rejection, profile-removal, participant
  merge/deletion, and restart scenarios preserve expected identities and saved content.
- **SC-006**: The meeting-summary evaluation set retains correct explicit owners and dates,
  leaves unstated ones unspecified, and produces evidence timestamps that exist in the
  reviewed transcript; failures are reported rather than attributed to recognition certainty.

## Assumptions

- Users already have permission to record; this feature imports existing recordings.
- Reference hardware: Apple Silicon M1 with 16 GB RAM, macOS 15 or later. Quality/runtime
  targets are verified before release; failure triggers documented tuning, not a silent model swap.
- The initial evaluation set includes at least three meeting conditions (clean call,
  in-room, interruptions), separate enrollment and held-out recordings, and one 60-minute file.
  Audio fixtures are local and must be supplied or recorded for validation; none are yet provided.
- Naming a participant is always possible even when audio is too weak to enroll a voice.
- A personal, single-user local catalog is sufficient; cross-device sync is deferred.
- The current text summarization provider remains in use. Fully local summarization is
  a separate roadmap item; cloud transcription is excluded.
- Automated tests are required for persistence, attribution/matching decisions,
  corrections, and summary-input boundaries; actual model quality uses the evaluation recordings.
