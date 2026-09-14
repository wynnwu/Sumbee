# Meeting transcription validation

Implementation in progress. Results below are observed, not estimated quality scores.

## Development fixture and hardware

One consented local M4A recording supplied in the sibling `summarizer-sample` directory:
60 minutes 22.377 seconds, mono AAC at 48 kHz, 59,096,828 bytes. Raw audio, transcripts,
and evaluation JSON remain outside Git. Local inventory: `/private/tmp/sumbee-fixture-inventory.json`.
Hardware actually tested: Apple M4, 32 GB RAM, macOS 15.7.9. The M1/16 GB reference target
has not been measured. Separate meetings and microphone conditions are not yet available. At the user's direction, the single recording is split into non-overlapping local clips for initial enrollment/development/evaluation tests.

## Verified foundation

- FluidAudio v0.12.4 and its complete runtime dependency graph resolve from local source.
  An empty-cache debug build under `sandbox-exec` with `(deny network*)` passed in 31.71 s,
  with no Swift/C++ compiler warnings but one package warning about four unused license files.
  The runtime manifest now explicitly excludes that license directory from compilation while
  preserving its files. A subsequent empty-cache, network-denied build passed in 25.53 s
  with zero warnings (`/private/tmp/sumbee-audit-offline-build.log`).
- All 42 model assets (486,012,664 bytes) were checked against the pinned manifest before loading.
- The real recording completed with networking denied. First run: 98.35 s. Repeat run:
  86.40 s, process peak resident memory 828,571,648 bytes (Darwin `getrusage`). The repeat ran
  alongside a build, so this is an observed run, not a controlled hardware benchmark.
- Output: 15,251 subword tokens, 219 speaker intervals, three clusters, 86 assembled turns.
  Assembly retained the recognized text exactly. Three clusters is an observation, not a
  claim that all speaker labels are correct.
- Repeat inference log: `/private/tmp/sumbee-real-meeting-verified.log`.
- Catalog tests cover distinct people sharing a name, merge redirects, rename resolution,
  deletion, invalid names, and preserving a corrupt catalog. Matching tests cover unknown
  and ambiguous voices, multiple profiles per person, attendee restrictions, and invalid vectors.

## Feasibility checkpoint and remaining gates

The actual local SDK path is feasible for continuing UI integration: the hour-long fixture
completed offline within the memory target. This is a documented checkpoint refinement:
UI work may proceed from measured runtime/memory and representative output; quality gates
remain open and must pass before the feature is called complete.

WER and DER are **unmeasured**: no independently annotated reference transcript or speaker
timeline has been supplied or created. Use quickstart.md's scoring conventions (word alignment,
speaker permutation, 250 ms collar, and stated overlap treatment) when recording those results.
Clean, in-room, and overlap fixture comparisons remain pending.

Identity matching currently uses provisional internal cosine threshold 0.75 and distinct-person
margin 0.12. These are not calibrated accuracy claims. Freeze a per-fingerprint policy using
separate development recordings, then measure precision/coverage on held-out meetings including
unfamiliar voices and changed microphones. Do not score enrollment audio as held-out evidence.

Cancellation latency, relocation, and immutable summary request capture have since passed
the checks recorded below. Full native accessibility coverage and real Meeting Notes quality
evaluation remain pending. No API request was made for the local transcription evaluation.

## Same-meeting split fixtures

Generated on request, preserving the original. All clips are mono 16 kHz, 16-bit PCM WAV,
stored outside Git in the sibling `summarizer-sample/meeting-transcription-fixtures` folder.
These test disjoint audio sections, not generalization to another meeting or microphone.

| Role | Source start (s) | Duration (s) | SHA-256 |
|---|---:|---:|---|
| enrollment | 0 | 600.000 | `3055569277a4bab59cfdc5572bf9ade161b4d3ef401c43d589683c0437b68bb9` |
| development-01 | 600 | 600.000 | `af35bc53707401ca4053c20a580dad31f92ad3f0335f1d0ea9b7a42e8f012a1f` |
| development-02 | 1200 | 600.000 | `b294bd6dfcb7b99c69cbe1312a9436347cb434a86cb3f07d34e20b92c97cc6e9` |
| evaluation-01 | 1800 | 600.000 | `0474abb6fabdb58ac9ca0e6bbbcaf9e245e9fc1dbbb98db86f56a6ab1fb94856` |
| evaluation-02 | 2400 | 600.000 | `573d784965c745cd36dff133e2ce3364aeea05ba5b6013f52d8da99fabacc716` |
| evaluation-03 | 3000 | 622.374 | `b43cb6e6ad34e1bb2422a64e9f08e85b519da0de229c62f5feba43c323b4ff59` |

## Split-clip smoke results

All six clips passed real local inference with networking denied in 67.67 seconds total.
Recognized text survived transcript assembly exactly in every clip. With provisional threshold
0.75 and margin 0.12, candidate coverage on the five non-enrollment clips was 4/10 clusters.
The enrollment clip self-matches are excluded from that figure. This is coverage, not identity
precision: no human reference identity labels were used.

| Clip | Runtime (s) | Clusters | Suggested | Turns |
|---|---:|---:|---:|---:|
| Enrollment | 11.18 | 2 | excluded | 12 |
| Development 1 | 11.22 | 2 | 1 | 7 |
| Development 2 | 11.02 | 2 | 1 | 13 |
| Evaluation 1 | 11.28 | 2 | 1 | 13 |
| Evaluation 2 | 11.18 | 3 | 1 | 21 |
| Evaluation 3 | 11.54 | 1 | 0 | 3 |

The final clip produced one cluster with similar moderate similarity to both enrollment voices
(0.667 versus 0.604); matching correctly abstained under the configured margin. Other low-score
clusters also abstained. This result does not establish that every diarization cluster is a
single voice. Listen and correct before confirming/enrolling; do not lower thresholds merely
to improve coverage on this evaluation set. Logs/results remain in `/private/tmp/sumbee-split-*`.

## Import regression and initial UI check

The real M4A import exposed a codec boundary error missed by short WAV fixtures. A small
AVAudioFile probe showed a read beyond the known frame count throws `nilError`; querying
framePosition can also raise an Objective-C exception in the restricted environment. Import
now counts decoded frames and bounds reads to the remaining length. The real-file
import/save/reopen/export check then passed with networking denied (1.36 s).

The locally signed app passed strict codesign verification and launched to Meetings without
an API key. A native dark-mode empty-state screenshot confirmed the 486 MB manifest loads
from the app resource bundle. Review/playback/catalog interaction results follow below.

Native interaction check: timestamp seeking advanced local playback to the selected time and
Pause stopped it. Creating/confirming a test participant in the isolated library left zero
voice profiles; pressing Remember this voice created exactly one persisted profile. The
review showed very long paragraphs, so assembly now breaks continuous speech into reviewable
paragraphs without changing recognized text. A regression covers that boundary. The updated
remember action reports Voice remembered; sample playback and catalog empty-state guidance
passed the subsequent native check recorded below.

Earlier deterministic suite: 129 tests, 3 opt-in evaluations skipped, zero failures
(`/private/tmp/sumbee-review-refinement-tests.log`). The opt-in original-file persistence and
six-clip inference runs passed separately. Two release bundles retain the same designated
requirement under the existing local signing identity; strict verification passed.

## Persistence and model-boundary audit

An additional empty-cache build with networking denied passed in 25.53 seconds with zero
warnings (`/private/tmp/sumbee-audit-offline-build.log`). Runtime source and model assets
remain separate. Model/software notices are now bundled with the app.

Filesystem tests exposed and fixed optional-field decoding and a macOS symlink resolution
edge case for new catalog files. The passing suite now covers whole-library relocation,
retained audio/export references, abandoned import staging, cancelled imports, cyclic catalog
redirects, future schemas, and isolation of a corrupt meeting from healthy job recovery.

Digital-silence checks (0.25 s and 2 s) pass with networking denied. A short-input SDK error
was fixed by detecting digital silence before inference; very short non-silent input is
padded for ASR and retains unknown speaker attribution. This is not a claim about noisy
non-speech recordings.

Real inference cancellation on a ten-minute clip was acknowledged in 0.0023 seconds and
released the queue in 0.138 seconds, with no late ready transcript. Log:
`/private/tmp/sumbee-real-cancellation.log`. Existing controlled-SDK tests separately prove
that another queued job cannot overlap an uncancellable call.

Matching policy `same-meeting-smoke-v1` is recorded in the model manifest at 0.75 minimum
cosine and 0.12 distinct-person margin, bound to the exact embedding fingerprint. A
mismatched policy disables suggestions. Its calibration status remains provisional; no
independent identity accuracy is claimed.

## Installer, queue, and native review verification

The app's real URLSession installer downloaded, hash-checked, activated, and reopened all
42 assets (486,012,664 bytes) in 282.03 s using an isolated cache. This exercised the actual
explicit downloader, separately from injected downloader tests. No recording was transmitted.
Log: `/private/tmp/sumbee-live-installer.log`.

The latest deterministic suite passed: 145 tests, six opt-in tests skipped, zero failures and
zero build warnings (`/private/tmp/sumbee-queue-controls-green.log`). Added coverage proves
that a saved awaiting-models recording can start after restart with installed models, a
pending recording exposes cancellation, and cancelling it never starts a second SDK call.
The UI now shows Start for available saved work and Cancel for scheduled work. A summary
regeneration regression also rejects resolving an old library's summary against a different
library, even if a same-named source file exists there.

The latest release bundle built in 14.88 s without warnings and passed strict signing
verification (`/private/tmp/sumbee-final-queue-bundle.log`). The signed app recognized the
real installed model cache and opened Meetings with no API key. A fresh real-M4A
import/save/reopen/export check passed with networking denied in 1.38 s, then that isolated
library was used for native review (`/private/tmp/sumbee-final-ui-seed.log`).

Native dark-mode checks confirmed 171 reviewable paragraphs from the unchanged recognition
output, visible timestamp controls, and an accessible Recording position slider. Creating
and confirming a test participant persisted zero profiles; Remember this voice persisted
exactly one and changed to disabled Voice remembered. Listen to a sample started local
playback; Escape returned to review with the position advancing, and Pause stopped it.
Editing and saving the first paragraph persisted the correction and incremented only the
review revision. These are isolated test-library edits, not corrections to the original
recording or independent accuracy annotations.

The bundled model/software notices sheet also opened and rendered successfully. Escape
closed both review and notices sheets; the isolated verification app then quit normally.
Git ignore checks exclude audio, retained meeting data, build products, and the local signing
identity while preserving the source model manifest.

Still open: full light/dark and keyboard/VoiceOver interaction coverage, all supported-format
end-to-end checks, reference-hardware measurements, independently annotated WER/DER,
cross-meeting identity precision/coverage, and real summary-output quality.

## Supported formats and review controls

Thirty-second speech clips encoded as WAV, MP3, and M4A passed real local transcription,
paragraph correction, save/reopen, retained-audio decoding, and immutable export checks with
networking denied. Original and retained hashes matched. Runtime for all three was 3.58 s;
durations were 30.000, 30.096, and 30.000 s respectively. MP3 encoder padding accounts for
the duration difference. Log: `/private/tmp/sumbee-supported-formats.log`. This verifies
codec/service persistence; native MP3 playback remains to be checked separately.

A half-second speech excerpt completed ASR and retained words with no speaker intervals or
embeddings. Initially running the full-meeting evaluator failed its expected-speaker assertion;
that assertion remains intact. A dedicated short-speech evaluator verifies the intended
unknown-attribution behavior and passed in 0.67 s with networking denied
(`/private/tmp/sumbee-short-speech-fixed-test.log`).

Attendee selection now applies one participant change atomically to the stored meeting,
preventing rapid toggles from replacing another selection with a stale UI snapshot. A
concurrent-selection regression preserves both people, independent removal, transcript text,
and revisions. Latest full suite: 148 tests, eight opt-in skips, zero failures
(`/private/tmp/sumbee-short-test-build.log`).

Native checks on the signed build verified Tab into the paragraph editor, Command-S save,
and Listen/Stop sample controls; stopping returned to review with paused playback. Light
appearance was verified using a process-only smoke override. Import/list, review, and speaker
assignment rendered correctly in light appearance. The native New speaker action reassigned
the selected paragraph; merging it back retained all 171 paragraphs and advanced attribution
revision. The corrected group disabled Remember this voice and displayed the reason with
guidance to use another recording. Restart retained the earlier correction and catalog name.
Build/signing log: `/private/tmp/sumbee-appearance-bundle.log` (13.53 s, zero warnings, strict
signature verification passed).

Remaining empirical gates still include independent annotated recordings and identities,
reference M1 hardware, and real summary-output evaluation. Remaining UI checks include
catalog edge cases, the no-key summary action, native MP3 playback, and broader keyboard flow.

## Catalog, batch, and review completion checks

The signed native app imported the MP3 through its file picker, displayed loading progress,
and produced a ready transcript. Playback advanced past 13 seconds and Pause stopped it.
Adding the optional Meeting Notes style made it available in review. Summarize displayed
the text-only confirmation, then opened API-key Settings in the no-key verification instance.
Closing Settings returned to the locally saved meetings. No transcript was sent to the API.

Catalog checks created two participants with the same name and distinct IDs, renamed the
second, filtered it by search, and cancelled its delete confirmation. Both the catalog and
speaker picker now show the most recent confirmed meeting context, including participants
without a voice profile. Service regressions separately verify deletion, merge, profile
removal, rejection, restart, and preservation of frozen summary sources.

The batch regression imports valid/unreadable/valid recordings while switching libraries:
the two valid recordings complete in order in their captured library, the unreadable file
creates no durable record, and the newly selected library remains empty. A real-recording
cancellation test observed the staged audio before cancelling, then verified zero staging
files/jobs and an unchanged source hash (0.058 s, `/private/tmp/sumbee-live-import-cancellation.log`).

### Standards review

Reviewed tracked and untracked implementation against HEAD
`231aaf7ce0732e2623286490b742f66061faf75a`, CLAUDE.md, the macOS learnings, and constitution.
One P2 finding violated the self-contained-library requirement: importing an audio symlink
copied the link rather than its bytes. The regression reproduced missing retained audio
after removing the original. Import now resolves the source link before copying; the test
verifies identical retained bytes, a regular file, and successful audio decoding after source
removal. The standards reviewer confirmed the fix; no remaining findings from that review.

### Spec review

Two P2 findings were reproduced and resolved:

- FR-004 requires imports to queue in order. Model setup resumed the displayed newest-first
  list, reversing waiting recordings. Resume now sorts by import time and captures the library
  root before awaiting; the regression proves oldest-first execution.
- US3.5 requires uncertain reuse to be withheld for insufficient clear or overlapping speech.
  Source profiles were checked, but new query clusters were not. Enrollment and queries now
  share the unchanged-cluster, usable-vector, ten-second non-overlapping-speech check. A
  regression proves short and fully overlapping queries abstain while a clean query still
  produces a suggestion; none is automatically confirmed or enrolled.

The spec reviewer confirmed both fixes. Review totals: one standards finding and two spec
findings, all resolved. Before/after logs: `/private/tmp/sumbee-review-regressions-{red,green}.log`.
Latest suite: 155 tests, nine opt-in skips, zero failures and warnings
(`/private/tmp/sumbee-query-quality-tests.log`).

### Revised same-meeting smoke policy

Policy `same-meeting-smoke-v2` retains the 0.75 cosine minimum and 0.12 distinct-person margin,
and applies the shared clear-speech check to enrollment and queries. The six-clip evaluator
now uses that same check. A fresh network-denied run passed in 66.46 s
(`/private/tmp/sumbee-split-v2-evaluation.log`):

| Clip | Runtime (s) | Clusters | Usable clusters | Suggestions | Review paragraphs |
|---|---:|---:|---:|---:|---:|
| Enrollment | 11.19 | 2 | 1 | self-match excluded | 28 |
| Development 1 | 10.81 | 2 | 2 | 1 | 24 |
| Development 2 | 10.99 | 2 | 2 | 1 | 28 |
| Evaluation 1 | 10.94 | 2 | 2 | 1 | 28 |
| Evaluation 2 | 10.87 | 3 | 2 | 1 | 32 |
| Evaluation 3 | 11.37 | 1 | 1 | 0 | 21 |

Only one enrollment cluster qualifies under the clear-speech check. Four suggestions are
offered across the ten later clusters; these counts are not identity precision or SC-004
person/meeting coverage. Independent annotations and recordings are still required.

The latest release compile passed in 13.94 s without warnings. After the user approved the
macOS Keychain prompt, signing completed and strict verification passed: the bundle is valid
on disk and satisfies its designated requirement (`/private/tmp/sumbee-reviewed-bundle.log`).
Verification needs access to the system trust store; a restricted sandbox trust error does
not reproduce when verification runs with that access.

The GUI automation connection recovered. The native WAV re-import check now covers rejecting
the suggestion, selecting the expected attendee, and confirming the resulting suggestion.
The saved meeting has one confirmed participant, no pending suggestion, and one expected
attendee. The catalog still has two profiles: confirmation did not enroll another voice.
The speaker sheet displays the confirmed name and a separate enabled **Remember this voice**
action. Escape dismissed both sheets and Command-Q closed the isolated test app.

These checks supplement the earlier keyboard, accessibility-label, playback, and light/dark
checks. T039 remains open for full accessibility interaction coverage; the empirical accuracy,
independent-meeting, reference-hardware, and real-summary gates also remain open.

## Escape cancellation verification

The native keyboard audit reproduced Escape dismissing the entire review while a paragraph
was being edited. Review and participant catalog now assign Escape to the inline Cancel
action during editing, and restore the sheet's Done shortcut afterward. This implements the
existing keyboard behavior specified in ui-design.md.

The updated release build passed in 14.25 s with zero warnings, followed by successful local
signing and strict verification (`/private/tmp/sumbee-escape-bundle.log`). In the signed app,
replacing a paragraph with temporary text and pressing Escape restored its original text
while keeping review open. A second Escape closed review. Replacing a participant name and
pressing Escape likewise restored the original name while keeping the catalog open; a second
Escape closed it. Before/after SHA-256 hashes of both saved JSON files were identical.
No service behavior changed; native interaction directly verified this keyboard-only fix.

Accessibility inspection exposes names and roles for the paragraph editor, recording slider,
timestamp playback, participant search/name fields, and confirmation controls. Full VoiceOver
navigation has not yet been exercised; label inspection alone does not prove that interaction.

## Visual edge-state verification

Three explicitly synthetic records in `/private/tmp/sumbee-edge-ui-library` exercised UI
states without changing the real transcription results. The signed app rendered them in
light appearance at the review sheet's 780-point minimum width:

- A 120-character participant name wrapped in the transcript row and speaker sheet without
  covering Edit, Assign turn, Clear name, or confirmation controls. The speaker rail scrolled
  horizontally. The long meeting title wrapped to two lines beside Done.
- An untimed paragraph displayed **Untimed**, with accessibility label **Play nearby audio for
  untimed paragraph** and a help message explaining the absence of an exact timestamp. Its
  playback action started at the fallback position; playback advanced past seven seconds and
  Pause stopped it.
- A failed record displayed its recovery message in full, with Retry on the meeting list.
  A no-speech record displayed playback guidance. Neither review offered summarization.
- The speaker sheet explained why Remember this voice was unavailable. Tab moved from search
  to the new-name field and Shift-Tab returned to search; Escape dismissed nested sheets.

These are rendering/interaction checks, not accuracy measurements or new model evaluations.
VoiceOver testing awaits the requested approval to temporarily enable the macOS feature.

## Three-voice collapse investigation (second recording)

The user supplied a second mono AAC/48 kHz recording and reported three distinct voices.
Duration: 2026.016333 s; size: 33,053,871 bytes; SHA-256:
`04f48fca196bc1ed6873028f9af04fbdb2904731676c36046f20fffa36cf1fdb`.
Audio and intermediate voice samples remain outside Git. No audio or transcript was sent to
an external service; model runs used a sandbox denying network access.

Baseline reproduction ran the actual adapter twice: 41.79 s and 41.16 s, both returning one
speaker for all speech. AHC supplied a single initial cluster, so transcript assembly was
not the origin of the collapse. Logs: `/private/tmp/sumbee-marketing-{baseline,capture}.log`.
The former hour-long smoke tests established execution, not satisfactory diarization quality;
this recording demonstrates why that distinction matters.

Five deterministic regressions in `DiarizationClusteringTests.swift` exposed:

1. An intended Euclidean threshold of 0.6 was converted from cosine similarity, yielding a
   distance limit of about 0.8944 and reversing threshold behavior.
2. Centroid-linkage inversions let a later, smaller merge distance hide an earlier merge
   above the limit. Distance cuts now use the maximum merge distance of each subtree.
3. Soft powerset marginals gave inactive speakers nonzero activity. Extraction now uses
   the selected powerset class, preserving explicit overlap states and empty states.
4. The vDSP transpose passed frames as columns and speakers as rows, scrambling speaker
   timelines. A four-frame/three-speaker regression reproduced the corruption; corrected
   dimensions preserve each speaker's exact mask.
5. Clustering accepted every finite sample, including insufficient and overlapping speech.
   It now trains on windows with at least 20% single-speaker activity, assigning remaining
   samples afterward. If no window qualifies, one finite seed preserves reviewable speech
   without inferring several supported identities.

Each regression failed before its corresponding correction and passed afterward. Logs:
`/private/tmp/sumbee-diar-{distance,inversion,mask-callsite,transpose,training}-red.log`.
The final normal suite passed: 160 tests, nine opt-in skips, zero failures and warnings
(`/private/tmp/sumbee-diar-final-tests.log`). Temporary capture instrumentation was removed.

Full-recording comparisons, without forcing the output speaker count:

| Pipeline | Speaker groups | Runtime (s) |
|---|---:|---:|
| Original | 1 | 41.79 |
| Corrected threshold and tree cut | 5 | 41.87 |
| Also corrected powerset masks | 4 | 44.52 |
| Also corrected transpose | 5 | 34.23 |
| Also filtered clustering training samples | 4 | 33.76 |

The last run has three substantial groups (1020.1, 731.6, and 103.2 seconds) and one extra
label spanning 5.8 seconds across 06:32.70–06:33.79, 28:53.01–28:54.01, and
33:42.00–33:45.74. Its strict expected-count assertion **still fails: four versus three**.
The original all-in-one collapse is removed, but this is not a claim of fully correct speaker
attribution. The user subsequently supplied examples for each voice; see the sparse reference
checks below.
Do not tune thresholds or discard brief speakers simply to pass the count assertion.
ASR text and token timings are identical between baseline and corrected runs.

The model asset hashes and download size are unchanged. The pipeline/model identifier is
now `parakeet-v2-offline-20260910-r2`, and the embedding fingerprint ends in
`offline-vbx-hardmask-ahc-v2`. Existing reviewed meetings stay intact; re-import to obtain
new diarization. Earlier voice profiles cannot match new recordings and require explicit
fresh enrollment. Identity thresholds remain provisional and uncalibrated for the corrected
pipeline. Source references and patch provenance are recorded in `Vendor/README.md`.

Compatibility verification on the final source and fingerprint passed with networking denied: the original hour-long recording produced two groups in 58.17 s, retaining 15,251 ASR tokens (peak resident memory 784,678,912 bytes). The WAV/MP3/M4A import/review/reopen checks also passed; both opt-in tests completed in 61.51 s. Log: `/private/tmp/sumbee-diar-compatibility.log`. Speaker counts alone are not reference-labelled accuracy scores.

The corrected release bundle compiled in 34.76 s with zero warnings and passed strict local signature verification (`/private/tmp/sumbee-diar-corrected-bundle.log`). Its bundled manifest matches the tested source. The remaining three-voice count failure is not waived by successful packaging.

## User-labelled speaker examples (2026-09-10)

For the second recording above, the user identified six ranges belonging to three people.
Replaying the baseline result fails the distinct-identity assertion: all six ranges map to
S1. Replaying the corrected result passes every range, including stable identity across
separate examples and distinct identities between people:

| Reference person | Range (seconds) | Corrected group | Detected speech (seconds) |
|---|---|---|---:|
| 1 | 70–90 | S1 | 20.000 |
| 1 | 151–170 | S1 | 19.000 |
| 2 | 106–113 | S2 | 6.139 |
| 2 | 120–130 | S2 | 10.000 |
| 2 | 340–355 | S2 | 14.796 |
| 3 | 1948–1956 | S3 | 8.000 |

Every detected interval within these examples has the expected identity. The small gaps
are unlabelled time, not another speaker; these approximate ranges do not provide precise
speech/silence boundaries. The regression permits pauses (at least 80% range coverage),
requires one attribution for detected speech, and learns group labels from the result
rather than assuming S1/S2/S3 numbering. The recording hash guards against using references
on another source. Audio, transcript, embeddings, and replay results remain outside Git.

`MeetingModelEvaluationTests/testAnnotatedSpeakerRangesFromSavedResult` replays saved
results; `testLocalRecording` applies the same checks when
`SUMBEE_MEETING_REFERENCE=marketing`. Neither passes references or a speaker-count hint
into inference. Logs: `/private/tmp/sumbee-speaker-anchors-{red,green}.log`.

This validates only 77.935 seconds of detected speech within 79 seconds of user-labelled
ranges. Full-meeting WER/DER, cross-meeting recognition, and the extra S4 label remain
unresolved. The user subsequently confirmed that 2022–2026 seconds, the longest S4 passage,
contains all three people talking over one another, not a fourth person (see below).

A fresh full-recording inference with networking denied passed the six reference checks
in 58.73 seconds, retaining 10,227 tokens and four groups. Text, token timings, and speaker
intervals exactly match the previously captured corrected result. This run enabled sparse
reference checks; it does not supersede the separate failing three-speaker-count assertion.
Log: `/private/tmp/sumbee-marketing-annotated.log`; result:
`/private/tmp/sumbee-marketing-annotated.json`.

A temporary observation compared reconstruction before and after overlap exclusion around
the three S4 fragments. Their boundaries persist with exclusion disabled, ruling out that
trimming step as the source. At the first two fragments, S4 wins the segmentation-window
votes using samples with only 0.56–1.31 seconds of clean activity and weak cosine matches
(0.14–0.45) to its centroid. Those samples are assigned after clustering, not used to train
it. At the ending, two samples with 2.53 and 3.12 seconds of clean activity strongly match
S4 (about 0.96) and have negative similarity to all three main centroids. This distinguishes
the short-fragment problem from simply merging two similar main groups; it does not
establish the ending's actual identity; the subsequent user annotation resolves it as
three-person overlap. No threshold or group-count change was made.
Observation: `/private/tmp/sumbee-marketing-fragments.json`. Temporary instrumentation
was removed; only tests and validation documentation were added in this follow-up.

The final suite with the saved-result reference check enabled passed 161 tests, nine
opt-in skips, zero failures, and zero build warnings
(`/private/tmp/sumbee-speaker-anchors-suite.log`). That reference-only follow-up changed no
shipped behavior; the subsequent overlap fix below does require a new bundle.

## Confirmed three-person overlap and identity safeguard (2026-09-10)

The user clarified that 2022–2026 seconds contains the three people talking over one another.
S4 is therefore a false additional identity, not a fourth participant. The sparse reference
test now checks that this range introduces no identity beyond the three established by the
clean examples; unknown attribution is permitted. It fails on the previous result in 0.32 s
(`/private/tmp/sumbee-overlap-red.log`), and a fresh network-denied run reproduces the failure
(`/private/tmp/sumbee-overlap-probe.log`).

Observation found exactly two S4 training samples, both in the same 2020–2030 s window
(actual recording ends at 2026 s), in local speaker slots 1 and 2. Their mutual cosine is
0.853, yet their masks claim simultaneous distinct voices for 0.136 s. Both misleadingly
pass the clean-duration filter (3.124 and 2.530 s). In contrast, S1/S2/S3 have training
support from 585/425/95 distinct windows. Core ML segmentation output is contiguous
float32, shape `[32,589,7]`, strides `[4123,7,1]`; this probe found no output-layout defect.
Local training metadata: `/private/tmp/sumbee-overlap-training.json`.
The seven output classes map to silence, three individual speakers, and three speaker
pairs; this model output has no explicit three-speaker overlap state.

The conservative fix rejects training pairs that contradict themselves: simultaneous local
speakers whose normalized embeddings would merge under the existing AHC distance limit.
It does not change that limit, require repeated-window support, set a speaker count, or
discard clusters by their total duration. Centroid fallback cannot reintroduce rejected
samples. Queries with no positive cosine support remain unassigned; reconstruction ranks
only clusters with positive activity, preserving unknown attribution instead of inventing
a fallback speaker. This is a Sumbee policy extension, not an upstream-equivalence claim.

Three new deterministic regressions failed before these changes and passed afterward:
conflicting overlap cannot train an identity (distinct simultaneous and similar sequential
voices remain eligible); unsupported queries stay unassigned; reconstruction cannot assign
zero-activity clusters. Logs: `/private/tmp/sumbee-overlap-unit-{red,green}.log`.

The full second recording now passes all six clean references, the annotated overlap check,
and the strict three-group assertion, with no count hint supplied to inference. Runtime
96.07 s; 10,227 tokens; three groups; 133 review paragraphs; peak resident memory
1,054,064,640 bytes. Recognized text and token timestamps exactly match the previous result.
Log/result: `/private/tmp/sumbee-overlap-fixed.log`,
`/private/tmp/sumbee-marketing-overlap-fixed.json`.

This removes the phantom identity, not all overlap ambiguity. Within 2022–2026 s the result
attributes approximately 2.075 s to S1 and 1.528 s to S2, leaving 0.397 s without attribution.
It does not reconstruct all three simultaneous speech tracks. The two earlier S4 fragments
are now partly S2/unknown and S3 respectively; those particular fragments have no individual
human identity references and are not claimed correct.

A local 35-second control concatenates the user's clean ranges 70–90, 106–113, and
1948–1956 s, with no added audio (`/private/tmp/sumbee-three-voice-control.wav`). It produces
three groups in 1.76 s but **fails identity attribution**: the second person's interior
range maps to S1 and the third is split between S2/S3. Disabling only the new contradictory
training filter yields byte-equivalent decoded recognition fields, including centroids and
intervals. Thus this short-input limitation is not introduced by that filter and remains
open under the broader quality gate. Do not describe the three-group count as a passing
identity test. Logs: `/private/tmp/sumbee-overlap-control{,-before}.log`.

The final suite, with annotated-result replay enabled, passes 164 tests with nine opt-in
skips, zero failures, and zero warnings (`/private/tmp/sumbee-overlap-final-suite.log`).
All temporary probe code was removed. The manifest now identifies
`parakeet-v2-offline-20260910-r3`, fingerprint `offline-vbx-overlap-abstention-v3`, with an
explicitly provisional matching policy. Model assets/downloads are unchanged. Earlier
profiles require fresh explicit enrollment; saved reviews remain intact.

Compatibility on the final source and r3 manifest also passes with networking denied:
the original hour-long recording retains two groups, 15,251 tokens and 190 review paragraphs,
with unchanged recognized text/token times (156.80 s; peak resident memory 1,191,411,712 bytes).
WAV/MP3/M4A import/review/reopen checks pass. Both tests completed in 163.87 s
(`/private/tmp/sumbee-overlap-compatibility.log`). These are compatibility measurements,
not reference-labelled accuracy scores or controlled performance comparisons.

The release build completed in 69.74 s with zero warnings, and the existing local signing
identity passed strict signature verification. Bundled model metadata exactly matches the
r3 source manifest (`/private/tmp/sumbee-overlap-bundle.log`). Reopen `dist/Sumbee.app` and
re-import to obtain the corrected diarization; previously saved reviews are unchanged.

## Audio-only deletion (2026-09-12)

The user requested deletion of only the retained audio file. **Delete audio…** is visible
in the meeting list and review header, with confirmation specifying that the transcript,
participant names, remembered voices, models, exports, summaries and original input remain.
The review stays open; playback stops and becomes unavailable. Reopening derives audio
availability from the filesystem without changing the meeting schema or record. Editing,
exporting, summary preparation and compatible voice reuse continue to work without audio.

Deletion is blocked for scheduled/active/still-cancelling jobs and while enqueueing; retry
cannot restart a job whose audio is gone. Confirmation is bound to its library root.
The store removes only the expected regular audio file and rejects redirected paths and
directories. It never deletes the meeting folder or reads/writes the participant catalog.

Six added tests verify original/meeting/export preservation; refusal to follow redirected
folders or recursively remove a directory; unchanged catalog, usable remembered voices,
models and summaries; edit/export/summary preparation after reopening; independence from
a corrupt catalog; queue/cancellation protection and stale-library confirmation rejection.
The final suite passes 170 tests with ten opt-in skips, zero failures and zero warnings
(`/private/tmp/sumbee-delete-audio-final-tests.log`). No model inference was changed.

The release build completed in 48.24 s and passed strict local signature verification
(`/private/tmp/sumbee-delete-audio-bundle.log`). A signed-app smoke run against a disposable
synthetic library visually confirmed the meeting row and visible **Delete audio…** control
(`/private/tmp/sumbee-delete-audio-ui.png`). Storage/state behavior is covered by the tests;
the native confirmation dialog was not clicked in this smoke run. No user recording was
deleted or modified during verification.
The fixture process was stopped after capture; automatic smoke-process exit was not verified.
