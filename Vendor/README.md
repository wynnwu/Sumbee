# Vendored audio dependencies

These runtime source subsets preserve upstream licenses and notices. Exact commits are recorded in
`revisions.json`. FluidAudio is Apache-2.0; swift-transformers and swift-jinja are Apache-2.0;
swift-collections is Apache-2.0 with Runtime Library Exception. Consult each LICENSE/NOTICE.

Local changes: Package.swift manifests contain only the required runtime products/targets
and use sibling local paths. Upstream tests, examples, CLI, CI, editor settings, media,
documentation, unused collection types, and source-generation templates are omitted. No model weights or private recordings are included.
The full runtime graph resolves locally: FluidAudio -> Tokenizers/Hub -> Jinja/OrderedCollections.

The ASR and offline diarization adapters use public model constructors with verified local
Core ML handles. SDK download/load convenience functions are deliberately not used for inference.
Model versions, file hashes and model attribution live in Resources/Models/meeting-models.json.

Compatibility edits for the installed Swift 6 / macOS 26 SDK: enable Accelerate's current
LP64 CBLAS declarations; correct the Clang pragma diagnostic name; use pointer update and
UTF-8 decoding APIs; handle MLMultiArray int8; remove unused locals/results and redundant
availability checks. These edits retain the algorithms and numerical precision.

Diarization correctness patches (2026-09-10) additionally correct the offline speaker-mask
transpose dimensions, decode the winning powerset class into binary activity, use the
documented Euclidean AHC threshold, respect child merge distances when cutting a centroid
linkage tree, and filter clustering training samples to windows with at least 20% clear
single-speaker activity. With no qualifying samples, one finite seed preserves reviewable
speech without claiming several supported identities. These are algorithm changes, covered
by `DiarizationClusteringTests` and local real-recording evaluations in feature 008's
`validation-results.md`. They change the embedding fingerprint; old voice profiles are not
reused for new recordings. Model files and download requirements are unchanged.

The overlap follow-up rejects contradictory training evidence: concurrent local speakers
whose normalized embeddings fall within the existing AHC same-voice distance cannot both
teach an identity. This conservative application policy adds no speaker-count constraint
or short-cluster cutoff. Centroid fallback uses only eligible training samples; samples
with no positive cosine match remain unassigned, and reconstruction never fills missing
assignments with zero-activity clusters. Unattributed recognized words remain reviewable.
This policy is a Sumbee extension, not a claim of upstream pyannote behavior.

Reference semantics: [pyannote clustering](https://github.com/pyannote/pyannote-audio/blob/main/src/pyannote/audio/pipelines/clustering.py),
[powerset decoding](https://github.com/pyannote/pyannote-audio/blob/main/src/pyannote/audio/utils/powerset.py),
and the installed Accelerate `vDSP.h` definition of `vDSP_mtrans` (`A[N][M]` to `C[M][N]`).
