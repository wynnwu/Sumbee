# Contract — Processing, Review, and Participant Actions

These are application interfaces, not new HTTP endpoints. All work is local until an explicit
summary request. Persisted validation rules are in [data-model.md](../data-model.md).

## Services

| Boundary | Input -> output | Required behavior |
|---|---|---|
| MeetingTranscribing | Retained audio URL + verified model handles -> recognized text/timings, speaker intervals, cluster embeddings | No network; SDK types do not escape; throwing failures/cancellation |
| MeetingModelManager | Explicit install request -> verified local model set | Only downloader in this module; immutable manifest, hash verification, atomic activation |
| TranscriptAssembler | Recognized words/segments + intervals -> turns and meeting speakers | Pure deterministic mapping; no text loss; unknown/untimed outputs supported |
| MeetingStore | Audio import and review mutations -> durable meeting/revision URLs | Transactional audio copy; atomic documents; immutable exports; root captured per job |
| ParticipantStore | Catalog mutation and confirmed enrollment -> durable catalog | One atomic catalog write; validate source attribution version before reuse |
| ParticipantMatcher | Meeting clusters + eligible profiles + optional attendee set -> suggestions | Compatibility filter, threshold + margin, no mutation; unknown is valid |
| MeetingSummaryInputBuilder | Ready meeting + saved revision -> prepared summary text/sourceRef | Snapshot must exist before enqueue; exclude unconfirmed names and private metadata |

The local processing queue owns one inference task. It publishes state on the main actor;
models, disk I/O, decoding, and inference run off it. On cancel, publish acknowledgement
immediately, cancel at supported boundaries, and reject any result from the cancelled task ID.
If an SDK call is not interruptible, keep the queue occupied until it returns; show “Stopping”.

Model loading and installation are different calls. Inference receives locally loaded models;
it cannot call a convenience downloader or replace corrupt models silently. Use stage labels
rather than a made-up percentage during opaque SDK inference.

## User actions

- **Import audio:** Available in Meetings through a picker and drop area without an API key.
  Audio dropped onto existing transcript tiles routes to local Meetings; ordinary documents
  retain their current flow. Mixed batches classify each file; a missing API key blocks only
  text summarization jobs, not audio imports.
- **Select attendees:** Optional catalog multi-select; narrows suggestions but cannot force
  recognition or prevent adding an unfamiliar participant after processing.
- **Play/review:** A turn seeks retained audio to its timestamp; provide text editing,
  reassignment to an existing/new meeting speaker, and merge labels. Untimed turns identify
  the limitation and offer nearby playback without inventing precise evidence.
- **Assign participant:** Select or create a catalog person and explicitly confirm the link.
  Display suggestions distinctly; exports use generic labels until confirmed.
- **Remember voice:** Separate action on an eligible whole cluster. A preview excerpt helps
  confirmation but does not change the averaged embedding. Mixed/corrected/short clusters
  show a reason enrollment is unavailable and retain manual naming.
- **Manage participants:** Search, add, rename, merge, delete, and remove voice profiles.
  Show future-recognition impact while preserving existing saved transcript wording.
- **Summarize:** Select style/model, freeze the reviewed revision, preview the exact prompt
  if geek mode is enabled, then enqueue. No automatic API call on import/review/enrollment.

## Summary contract

Use a new meeting preparation entry point in `SummarizationEngine` or an equivalent builder
feeding its existing `finish` path. `PreparedInput` carries a default-compatible input policy.
Capture the meeting library root with prepared input and preserve it for retries/save;
if the selected root changes before execution, require reselecting the source library
rather than resolving its snapshot under another root.
Meeting requests and regeneration reject oversized input before the API call; show the limit
and let the user choose a larger-context model. Extract budget calculation into shared code so
preview, actual sending, and retries agree. General file/YouTube behavior remains unchanged.

The Meeting Notes style requests decisions and action items with task, established owner,
established due date, and evidence timestamps. Unknown facts remain unspecified. General
meeting prompt context also explains confirmed/generic speakers and timestamp syntax. Apply
that context identically during preview, execution, retries, and regeneration. Existing edited
styles are never overwritten by default-style installation.

Model output remains a draft. Automated summary fixtures evaluate supported owners/dates and
valid evidence times; the UI never claims an unverified suggestion is a confirmed identity.
