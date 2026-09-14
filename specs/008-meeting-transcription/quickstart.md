# Validation Guide — Meeting Transcription

**Status:** Implementation and local model checks are underway. Read [validation-results.md](validation-results.md)
for observed results and open gates; use this guide to reproduce the corresponding [tasks](tasks.md).

## Prerequisites

- macOS 15+ on Apple Silicon; reference performance machine is M1 / 16 GB RAM.
- Xcode/Swift toolchain, vendored dependencies, and a writable temporary test library.
- Explicitly installed, verified local ASR/diarization models. Subsequent local tests run
  with networking disabled and without a summarization API key.
- Consented local recordings: clean English call, in-room meeting, interruptions/overlap,
  one 60-minute file, and distinct enrollment/development/held-out recordings with recurring
  and unfamiliar speakers. Annotate words, speaker turns, and identity labels. Record device,
  microphone, duration, and fixture hashes; do not commit private recordings.

## 1. Build and deterministic tests

```sh
swift build
swift test
```

Verify zero build warnings and passing existing/new tests. For the offline-build check,
use an isolated fresh checkout and empty dependency caches with network denied; do not
reuse the working app's populated SwiftPM cache. Confirm no remote package/artifact fetch.

After T044 implements local signing, select the existing Apple Development identity once
with `bash scripts/setup-signing.sh` (or specify `SUMBEE_SIGNING_IDENTITY`). Bundle with
`./scripts/bundle.sh`, then run `codesign --verify --strict --verbose=2 dist/Sumbee.app`.
Repeat a bundle build and compare `codesign -d -r- dist/Sumbee.app` output: the signer and
designated requirement should remain stable with bundle ID `com.sumbee.app`. Exercise the
missing-identity error before bundle replacement. Launch the bundled app for UI/permission
validation; record any one-time approval needed when switching from an older ad-hoc build.
No private key or identity-selection file is committed. These steps validate local signing,
not notarization; `swift build` and `swift test` need no certificate.

## 2. Local import and review (US1)

The source build opens Meetings without an API key. Choose **Download meeting models** once
(486 MB); the installer verifies all assets. Models live in Application Support/Sumbee/models;
saved recordings and the participant catalog live in the library's hidden `.meetings` folder.
The supplied test audio is in the sibling `summarizer-sample` folder. At the user's direction,
six disjoint clips were created under `meeting-transcription-fixtures`; they are same-meeting
smoke inputs, not independent recordings. Their hashes and boundaries are recorded in results.

Opt-in evaluations after `swift test` builds the test executable:

```sh
# Existing downloaded model folder, original local recording, and local-only JSON output:
# Optionally set SUMBEE_MEETING_EXPECTED_SPEAKERS=3 when the true count is known.
# This asserts output count; it does not force clustering or prove correct attribution.
# For the annotated marketing recording, SUMBEE_MEETING_REFERENCE=marketing also
# checks the user's six speaker ranges (without feeding the labels to inference).
SUMBEE_MEETING_MODELS=/path/to/verified-assets \
SUMBEE_MEETING_AUDIO=/path/to/recording.m4a \
SUMBEE_MEETING_RESULT=/tmp/meeting-result.json \
swift test --skip-build --filter MeetingModelEvaluationTests/testLocalRecording

# Six split WAV inputs; results stay outside the repository:
SUMBEE_MEETING_MODELS=/path/to/verified-assets \
SUMBEE_MEETING_SPLIT_FIXTURES=/path/to/meeting-transcription-fixtures \
SUMBEE_MEETING_SPLIT_RESULTS=/tmp/meeting-split-results \
swift test --skip-build --filter MeetingModelEvaluationTests/testSplitRecordings

# A local folder containing sample.wav, sample.mp3, and sample.m4a with speech:
SUMBEE_MEETING_MODELS=/path/to/verified-assets \
SUMBEE_FORMAT_FIXTURES=/path/to/format-fixtures \
swift test --skip-build --filter MeetingModelEvaluationTests/testSupportedFormatsImportReviewAndReopenOffline

# A non-silent speech clip shorter than one second:
SUMBEE_MEETING_MODELS=/path/to/verified-assets \
SUMBEE_SHORT_AUDIO=/path/to/short.wav \
swift test --skip-build --filter MeetingModelEvaluationTests/testSubsecondSpeechKeepsWordsWithoutSpeakerClaims

# Cancel after a substantial recording's staged audio copy becomes visible:
SUMBEE_IMPORT_CANCEL_AUDIO=/path/to/hour-long-recording.m4a \
swift test --skip-build --filter MeetingModelEvaluationTests/testCancellationDuringRealImportRemovesStagingAndSavedJob
```

Use `sandbox-exec -p '(version 1) (allow default) (deny network*)'` around the commands for
the offline check, and add `--disable-sandbox` to SwiftPM under that outer sandbox. Normal
unit tests skip these opt-in cases. macOS codec services must remain available; a generic
process sandbox that blocks audio codec access is not equivalent to denying network access.

Replay those sparse speaker checks against an already saved marketing result without
running the models again:

```sh
SUMBEE_MEETING_AUDIO=/path/to/annotated-marketing-recording.m4a \
SUMBEE_DIARIZATION_REPLAY=/path/to/its-saved-result.json \
swift test --skip-build --filter MeetingModelEvaluationTests/testAnnotatedSpeakerRangesFromSavedResult
```

The test verifies the recording's SHA-256, checks substantial detected coverage in each
range, consistent attribution within and across each person's examples, and separation
between the three people. Group names may change between runs. These sparse references
do not establish full-meeting accuracy or waive the separate expected-speaker-count check.
The same test checks the user-confirmed three-person overlap at 2022–2026 seconds:
attribution may be unknown, but must not introduce a fourth identity. See T045 and the
recorded before/after results for this overlap check.

Start without an API key. Open Meetings; import each supported format, then a mixed batch.
Expect stage progress and a serial queue. Try unsupported/corrupt/silent files; one failure
must not stop the batch. Play an excerpt, edit words, reassign a turn, and merge labels.
Restart: saved content and playback remain available, with original input files unchanged.
Use **Delete audio…** in the list and review. Cancel first to verify nothing changes, then
confirm on a disposable fixture. Only the retained audio disappears: review/edit/export,
summary snapshots, participant names, remembered voice matching and models remain available.
Reopen and verify playback/retry are disabled with an audio-unavailable message. Active,
queued and still-cancelling work must block deletion; changing libraries dismisses confirmation.
Cancel during import and inference; acknowledgement <=2 seconds, no late ready result, and
no concurrent replacement inference. Fail/cancel/force-stop during audio staging: no saved
job remains, staging is cleaned, and the original can be imported again. Interrupt processing
after publication: the retained-audio job offers retry, never a falsely complete transcript.

## 3. Catalog and voice reuse (US2/US3)

Create two people with the same name and verify distinct IDs. Assign one to a speaker;
check that no profile exists until “Remember this voice”. Enroll an eligible confirmed
cluster, restart, and process a different meeting. Verify suggested names require confirmation,
unfamiliar voices abstain, and attendee selection only narrows suggestions.
The original enrollment cluster and each new query cluster must have at least ten seconds
of clear, non-overlapping speech. Short or fully overlapping query clusters stay unnamed;
manual naming is always available. Participant choices show a recent confirmed meeting for
context when names are duplicated, even if no voice was remembered.
Reject a suggestion; confirm that its profile is not updated. Correct source attribution
and verify all profiles sourced from that meeting become ineligible. Attempt enrollment on
short/mixed/corrected clusters: manual naming remains available with guidance to use another
recording. A clean cluster in a separate normal import can enroll; no reprocessing UI is needed.
Remove a profile, merge people, and delete a participant;
restart after each and verify historical transcript wording and summaries are unchanged.

## 4. Summary handoff (US4)

Use a fake/capturing summarizer first: no API call should occur before Summarize. Confirm
only reviewed text/prompts cross the boundary, with generic labels for unconfirmed names.
Preview and actual request must agree. Oversize a meeting transcript: reject before sending
with a larger-context-model recovery action, without truncation. Normal document/YouTube
flows retain their existing behavior.

With a configured API key, use Meeting Notes on fixtures containing explicit and missing
owners/dates. Compare action items and evidence times with the reviewed snapshot. Edit the
meeting afterward; existing summaries and regeneration must still use the original snapshot.
A new summary/export must reference a new saved file. Rename a confirmed participant without
editing the meeting: the new export uses the latest name, and retry/regeneration of an older
summary keeps its original names. Repeat after participant merge/deletion and catalog read failure.

## 5. Acceptance measurement and recovery

Run the same fixed recordings on the reference Mac. Record elapsed time, peak memory,
word error rate, diarization error rate, and held-out identity suggestion precision/coverage
in `validation-results.md` (created during implementation). Compare with SC-001–SC-006 and
the <=6 GiB engineering memory target. Freeze thresholds before held-out evaluation; count
all eligible enrolled speakers in coverage and include unfamiliar voices in precision tests.

Move the whole library including hidden `.meetings`, select the new root, and repeat
playback/catalog/regeneration. Change library selection during an active import: it must
finish in the captured root or fail recoverably. Corrupt a copied catalog/model asset and
verify visible recovery without data reset or implicit download.

Check keyboard navigation, focus after speaker assignment, VoiceOver labels, light/dark
appearance, and responsive cancel/playback controls during processing. Record actual
results and unresolved failures; documentation-only review is not a passing model benchmark.
The user can complete import/review/naming without interpreting scores or adjusting thresholds.
Errors identify a direct next action; setup and summary handoff explain where audio/text go.
For isolated native appearance checks, launch the signed executable with `SUMBEE_SMOKE=1`,
`SUMBEE_SMOKE_SECONDS=900`, an isolated `SUMBEE_LIBRARY`, and `SUMBEE_APPEARANCE=light`
or `dark`. This changes only the verification process's appearance, not macOS settings.
Use `SUMBEE_MODEL_ROOT` to select the isolated installed model cache. In review, Tab reaches
the paragraph editor and Command-S saves; speaker samples have a Stop control and stop when
the assignment sheet closes.

## Internal scoring conventions

These checks support the existing quality targets; they are not setup steps or controls for users.
Use a fixed, documented set with at least three held-out meetings containing recurring and
unfamiliar speakers, separate from enrollment and tuning audio. The same meetings can cover
clean call, room, and interruption conditions; record counts and results without extrapolating
them into a general accuracy claim. No new benchmark dashboard is required.

- WER: lowercase reference and hypothesis, remove punctuation, split on whitespace, and
  compute (substitutions + deletions + insertions) / reference words over clean English speech.
  Apply identical normalization and record reference word counts; zero-word clips belong to
  no-speech checks, not this denominator.
- DER: use optimal one-to-one reference/hypothesis speaker mapping, a 250 ms boundary collar,
  and exclude overlapping reference speech for the clean-English gate. Divide missed speech,
  false-alarm speech, and speaker-confusion duration by scored reference speech duration.
  Report harder room/overlap conditions separately with their scoring settings.
- Identity precision: correct offered cluster-to-person suggestions / all offered suggestions,
  including suggestions on unfamiliar voices; a mixed-identity cluster suggestion is incorrect.
  Zero suggestions is not a passing result. Report numerator and denominator alongside SC-004.
- Identity coverage: count unique ground-truth person/meeting pairs with an active compatible
  enrollment and at least 10 seconds of non-overlapping reference speech, restricted to selected
  attendees only when a filter was explicitly set. Coverage is pairs with at least one correct
  suggestion / eligible pairs; split clusters do not multiply the denominator. Eligibility is
  established from reference annotations before scoring, independently of the model's output.
- Keep these settings and recognition thresholds fixed before held-out evaluation. Runtime
  measures one fully retained recording from processing start to ready; UI acknowledgement
  and peak process memory are measured separately on the reference Mac.
