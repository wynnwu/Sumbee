# Data Model — Meeting Transcription

**Status:** Proposed persisted schema v1. Types belong to `SumbeeKit`; SDK types stay
inside the adapter. A catalog belongs to the selected library. Names are never identity keys.

## Validation rules

These exact rules are carried into implementation tasks; C-numbers are stable contract references.

- **C01:** IDs are UUIDs and remain stable across save/reload.
- **C02:** Participant names are trimmed, nonempty, and at most 120 characters; duplicate names are allowed.
- **C03:** Persisted documents use schemaVersion 1; unsupported versions or corrupt content fail without overwriting the original.
- **C04:** Turn bounds are both null or finite seconds satisfying 0 <= start <= end <= duration; untimed turns retain their text and order.
- **C05:** Transcript text is preserved through attribution edits; a no-speech result has zero turns and an explicit status.
- **C06:** reviewRevision and attributionRevision are positive integers; review edits increment the former and attribution edits also increment the latter.
- **C07:** confirmedParticipantID is nullable; suggestedParticipantID never becomes confirmed without user action.
- **C08:** Profile vectors are finite, nonzero, normalized, dimension-compatible, and fingerprint-compatible; their source attribution revision must still match.
- **C09:** Enrollment requires an explicitly confirmed unchanged single-voice cluster with at least 10 seconds of non-overlapping speech.
- **C10:** Durable states are queued, importing, awaitingModels, transcribing, diarizing, assembling, ready, noSpeech, failed, cancelled, or interrupted.
- **C11:** Persisted asset paths are library-relative and cannot escape the library root; summary sourceRef points to an immutable Markdown revision.
- **C12:** Merge redirects are acyclic and resolve to one participant or a deleted tombstone; deletion removes that participant's usable profiles.

New optional fields decode with defaults; missing required identity/audio/version fields are
errors. Preserve unrelated settings during migrations. All mutations validate before atomic write.

## Meeting document (`Models/Meeting.swift`)

| Field | Meaning / rules |
|---|---|
| schemaVersion, id | Document envelope; C01/C03 |
| title, createdAt | User-facing title and creation time; title defaults to imported filename |
| audioPath, originalFilename, audioSHA256 | Retained audio reference and import provenance; C11 |
| durationSeconds | Finite nonnegative decoded duration; invalid audio is an import failure |
| status, failureMessage | Durable state C10; failure text is local and contains no credentials |
| reviewRevision, attributionRevision | C06; initialize both at 1, including queued records |
| modelFingerprint | ASR/embedding revisions and preprocessing identifier for reproducibility |
| turns, speakers | Ordered editable transcript plus meeting-local identities |
| recognitionResult | Original timing/cluster provenance for review and enrollment eligibility |
| expectedParticipantIDs | Optional UUID set; empty means search all active participants |
| exportedRevisions | Revision number to immutable transcript path mapping; C11 |

State path: queued -> importing -> awaitingModels (if needed) -> transcribing -> diarizing
-> assembling -> ready/noSpeech. Active stages may become failed/cancelled. On restart,
nonterminal active stages become interrupted and can be retried from retained audio.
Queued records can resume after the user resumes processing. Retrying never overwrites a
reviewed meeting; create a new processing revision and replace working results only explicitly.
A cancelled import before durable audio exists has no ready meeting record.

## Transcript turn and meeting speaker (`Models/Meeting.swift`)

A turn has `id`, `text`, optional `start`/`end`, `speakerID`, and original token/segment
references (C01/C04/C05). A speaker has `id`, `genericLabel`, optional SDK cluster keys,
`confirmedParticipantID`, saved `displayNameSnapshot`, optional suggestion + score,
and enrollment eligibility (C01/C07/C09). Scores are local ranking values, not probabilities.

An untimed turn cannot offer exact timestamp playback/citation; the UI labels it untimed
and allows nearby audio review. A detected-speaker merge remaps turns without deleting text;
a new speaker identity can be created when correcting turns from a mixed cluster.
Attribution changes invalidate affected stored profile sources through C06/C08, even if
a crash occurs before eager profile cleanup. Text-only corrections do not invalidate voices.

## Participant catalog (`Models/Participant.swift`)

One versioned catalog document contains active participants, voice profiles, and merge/deletion
records so a catalog operation can commit atomically (C03). A participant has `id`, `name`,
`createdAt`, and `updatedAt` (C01/C02). A rename affects future exports/assignments; existing
saved display-name snapshots and immutable transcript revisions do not change automatically.

Merge chooses a surviving ID; move source profiles to it and record a redirect for the retired
ID (C12). Historical meeting links resolve through the redirect, retaining saved wording.
Delete records a nameless tombstone, removes that identity's profiles, and disables future
recognition; saved meeting names/text remain readable. Deleting a voice profile alone keeps
its participant and confirmed meeting links. No deleted identity is revived by a name match.

## Voice profile (`Models/Participant.swift`)

Fields: `id`, `participantID`, `embedding`, `embeddingFingerprint`, `dimension`, `sourceMeetingID`,
`sourceClusterKeys`, `sourceAttributionRevision`, `createdAt` (C01/C08/C09).
The fingerprint covers embedding model commit/checksum, preprocessing and normalization version.
Keep separate confirmed profiles from different meetings; score a candidate participant using
its best eligible compatible profile, then compare the top two distinct participants.
Missing/incompatible/stale profiles abstain. Threshold and margin are versioned calibration
configuration, frozen before evaluating held-out recordings.

## Model installation and summary input

A model manifest records immutable asset URLs/revisions, expected byte counts, SHA-256 hashes,
model roles, and license/provenance. An installation becomes active only when its full bundle
verifies; staging directories are never interpreted as active models.

`MeetingSummaryInput` identifies meeting ID, review revision, readable transcript text, and
relative snapshot path (C11). Extend `PreparedInput` with an input-kind/policy defaulting to
existing behavior; meeting inputs reject truncation. Snapshot metadata lets regeneration restore
that policy. The API receives transcript text and prompts, not local asset paths or embeddings.
