# Contract — Local Files and Recovery

All paths below are relative to the selected library unless marked otherwise.

```text
<library>/
  .meetings/
    participants.json
    <meeting-uuid>/
      audio.<original-extension>
      meeting.json
  source/
    YYYY-MM-DD HHmm - <title> - <meeting-uuid> - <export-uuid>.md
  <summary-style>/
    <existing-summary-filename>.md or .html
~/Library/Application Support/Sumbee/models/
  <verified-model-set>/
```

`.meetings` is hidden from the existing asset browser, which exposes nonhidden files in
`source/`. It remains plain user-owned files and is discoverable through a Meetings
“Reveal files” action. Model caches are reinstallable; the whole library, including hidden
`.meetings`, contains durable meeting/catalog data and can be backed up or moved together.

## Atomic ownership

- Copy the input into an app-owned staging directory, verify its bytes/hash and decoded
  readability, and write initial meeting.json there. Atomically publish the directory only
  after both succeed. Before publication there is no persistent job. On failure/cancellation,
  remove staging files and offer normal re-import; discard abandoned staging on restart.
  Never delete or mutate the user-selected original.
- Replace each JSON document atomically after validation. Catalog mutations (including
  profile moves/removals and redirects) commit in a single `participants.json` replacement.
- Profile eligibility checks the source meeting attribution revision every time candidates
  are loaded. Stale cross-file state therefore abstains even after an interrupted correction.
- Each explicit export/new summary resolves the latest confirmed participant names and
  atomically saves a new Markdown file with a unique export ID before registering its path
  or enqueueing. No name-history tracking or revision change is needed for catalog renames.
  Retries/regeneration of an existing summary reuse its saved file without resolving names
  again. Metadata includes meeting ID, review revision, export ID, and source type.
- Snapshots contain names resolved at export (saved assignment names for deleted people,
  generic labels for unconfirmed speakers), turn IDs, text, and available timestamps.
  Embed no audio, voice vectors, filesystem paths, or profile scores in API-bound content.
- If a write fails, keep the last committed record and report retry. Unsupported schemas
  and corrupt data are preserved for repair, never replaced with empty defaults.

## Library changes and deletion

Capture a library root per local job. Changing the selected library switches the visible
catalog; it does not move or merge catalogs. Active jobs finish against their captured root,
or fail recoverably if it disappears. Relative paths allow moving the entire library and
selecting its new location without rewriting meetings or summary source references.

Participant deletion removes profiles and records a tombstone; historical meeting text and
summary snapshots remain intact. Merge redirects keep saved identities resolvable without
rewriting every meeting. Deleting an exported source/summary in the existing asset browser
remains a file operation, not an implicit deletion of a meeting or participant. If a referenced
snapshot is manually removed, regeneration reports the existing source-missing error.
A full meeting deletion/retention UI is deferred; Reveal files exposes local storage ownership.

## Reopening

Load the selected library's catalog and meeting index off the main actor. Mark interrupted
processing jobs with retained audio for retry and keep ready meetings immediately usable.
Discard abandoned app-owned import staging directories; they are not recoverable jobs. Model fingerprints and
source revision checks run before suggestions; an unavailable/moved source never causes a
stale profile to be used. Persisted JSON envelopes are schema-versioned as specified in C03.
