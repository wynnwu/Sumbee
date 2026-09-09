# Validation Guide — Meeting Transcription

**Status:** Planned checks; implementation and model evaluation have not run.
Use this guide after completing the corresponding [tasks](tasks.md).

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

## 2. Local import and review (US1)

Start without an API key. Open Meetings; import each supported format, then a mixed batch.
Expect stage progress and a serial queue. Try unsupported/corrupt/silent files; one failure
must not stop the batch. Play an excerpt, edit words, reassign a turn, and merge labels.
Restart: saved content and playback remain available, with original input files unchanged.
Cancel during import and inference; acknowledgement <=2 seconds, no late ready result, and
no concurrent replacement inference. Force-stop during a write; restart must show either
last committed data or an interrupted job, never a falsely complete transcript.

## 3. Catalog and voice reuse (US2/US3)

Create two people with the same name and verify distinct IDs. Assign one to a speaker;
check that no profile exists until “Remember this voice”. Enroll an eligible confirmed
cluster, restart, and process a different meeting. Verify suggested names require confirmation,
unfamiliar voices abstain, and attendee selection only narrows suggestions.
Reject a suggestion; confirm that its profile is not updated. Correct source attribution
and verify the old profile becomes ineligible. Attempt enrollment on short/mixed clusters;
manual naming must still work. Remove a profile, merge people, and delete a participant;
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
A new summary from the updated meeting must reference a new revision.

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
