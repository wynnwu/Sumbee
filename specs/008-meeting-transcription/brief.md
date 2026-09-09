# Brief — Local meeting transcription & participant catalog

**Status:** Approved direction, carried forward from module 002 on 2026-09-09.
The current requirements are in [spec.md](spec.md), with implementation details in
[plan.md](plan.md) and [tasks.md](tasks.md). This brief preserves the original scope.

## Outcome and scope

Drop a meeting recording into Sumbee, transcribe it on-device, review who said what,
and generate notes, decisions, and action items through the existing summary styles.
Ship audio-file import first on macOS 15+ / Apple Silicon. English is the initial
quality target; occasional Chinese/Cantonese is best-effort, not a release requirement.
Live microphone/system recording, streaming transcripts, and licensing are deferred.

## User experience

1. **Import:** Drop or choose an `.m4a`, `.mp3`, or `.wav`; optionally select expected
   attendees from the participant catalog. Show model setup, processing progress,
   cancellation, and recoverable errors.
2. **Review:** Show a timestamped transcript and detected speakers with playable audio
   excerpts. Name each speaker by selecting an existing participant or creating one.
   Allow correcting individual turns and merging duplicate speaker labels without
   losing text. Unknown speakers remain usable without naming.
3. **Remember:** Offer “Remember this voice” after a speaker assignment is confirmed.
   A Participants screen supports searching, adding, renaming, and merging people,
   removing saved voice profiles, and deleting catalog entries.
4. **Reuse:** In later meetings, compare detected voices with compatible saved profiles
   locally and suggest participant names. Let users confirm or correct suggestions;
   leave ambiguous matches unknown. Only confirmed assignments update voice profiles.
5. **Summarize:** Save the reviewed transcript and choose a summary style. Action items
   include an owner, due date when stated, and supporting transcript timestamps;
   unspecified owners/dates remain unspecified.

## Technical direction

Use [FluidAudio](https://github.com/FluidInference/FluidAudio): **Parakeet TDT 0.6B v2**
for English ASR and **OfflineDiarizerManager** for batch speaker diarization. Wrap the
SDK behind a small transcription interface returning timed words/turns and meeting
speaker IDs. Match words to speaker intervals; keep participant matching separate
from diarization and summarization. Use the existing SDK pipeline for clustering.

A **Participant** has a persistent ID and editable name; a **Meeting Speaker** has an
ID local to one meeting and an optional confirmed participant link. **Voice Profiles**
hold confirmed voice embeddings, their source references, and embedding-model version.
Compare compatible versions only; model changes may require rebuilding profiles.
Catalog deletion removes recognition data while preserving historical transcript text.

Store the catalog and transcript metadata as versioned local JSON, with readable
Markdown transcripts in the existing library. Preserve imported audio locally for
playback and corrections. Audio and voice profiles stay on-device; only transcript
text and prompts go to the selected summarization LLM when the user requests it.

## Delivery and validation

1. **Prove the pipeline:** Process a clean call, an in-room meeting, and overlapping
   speech, including a 60-minute recording. Measure transcription errors, speaker
   attribution, runtime, and memory; verify offline operation after model setup.
2. **Ship import and review:** Add the file workflow, local persistence, speaker
   correction, and existing summarizer integration.
3. **Ship participant reuse:** Add catalog management, confirmed voice enrollment,
   and suggested matches. Verify recognition across separate meetings, rejection of
   unfamiliar voices, correction persistence, and profile removal after app restart.

**Constitution check:** FluidAudio is the scoped dependency exception; pin and vendor
its required runtime dependencies for offline builds. Download and verify model assets
through explicit setup, then load locally. This replaces the earlier whisper.cpp /
custom-clustering exception; the constitution records the dependency and setup changes.
