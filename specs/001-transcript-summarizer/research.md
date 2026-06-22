# Phase 0 Research & Decisions

Decisions that shape the plan, each with rationale and the alternatives rejected.

## D1. Native SwiftUI vs. Electron (the source's table picked Electron)

**Decision**: Native SwiftUI/AppKit.

**Rationale**: The user's top priorities are an elegant glass, futuristic, native-feeling
UI and a real built `.app`. Native materials/vibrancy *are* the glass aesthetic; light/
dark is automatic; the binary is tiny. The source picked Electron for parsing/SDK
ecosystem, but on native that rationale dissolves (see D3). Confirmed with the user.

**Rejected**: Electron (≈200 MB Chromium; "glass" and native feel are emulated, not real).

## D2. Build system: SwiftPM + `.app` bundler (no `.xcodeproj`, no XcodeGen)

**Decision**: One SwiftPM package: `SumbeeKit` (library, all logic + views) +
`Sumbee` (thin executable, `@main` shell) + `SumbeeKitTests`. A `scripts/
bundle.sh` runs `swift build -c release`, assembles `Sumbee.app/Contents/{MacOS,
Resources}` with a generated `Info.plist`, and ad-hoc-signs it.

**Rationale**: Reproducible, contributor-friendly, **no build-time network**, no
hand-maintained `pbxproj`. The library/executable split lets `swift test` import logic.

**Rejected**: hand-written `.xcodeproj` (fragile); XcodeGen/Tuist (extra tool); bare SPM
binary without a bundle (no proper dock icon / menubar / activation).

## D3. Zero-dependency parsing & integrations

| Concern | Native/system answer |
|---|---|
| `.txt` / `.md` | `String(contentsOf:encoding:)` |
| `.rtf` | `NSAttributedString(url:options:[.documentType:.rtf])` → `.string` |
| `.pdf` | PDFKit `PDFDocument(url:)?.string`; empty ⇒ "no extractable text (scanned?)" |
| `.docx` | `/usr/bin/unzip -p <f> word/document.xml` → `XMLParser` over `w:t`/`w:p`/`w:tab`/`w:br` |
| YouTube captions | `Process` → `yt-dlp` (VTT) → in-house `VTTParser` |
| API | `URLSession.bytes(for:)` SSE parse (no SDK) |
| Secret storage | Security framework Keychain (`SecItem*`), the native `safeStorage` equivalent |
| Live library refresh | CoreServices FSEvents (`FSEventStreamCreate`) |

**Rationale**: Eliminates all third-party packages and any build-time network; uses
the most robust, OS-maintained code paths. DOCX is the only gap and is solved with a
system binary + Foundation XML.

**Rejected**: ZIPFoundation/mammoth/pdf-parse/rtf-parser/@anthropic-ai/sdk (all add a
dependency and, for SPM, build-time network).

## D4. Capability-aware Anthropic client (forward compatible)

**Decision**: A `ModelCatalog` maps each known model id to a `ModelCapabilities`
record (`supportsTemperature`, `supportsEffort`, `effortLevels`, `supportsThinking`,
`maxOutputCeiling`). The request builder consults capabilities and **only sends
parameters the chosen model accepts**.

**Rationale (grounded in the current API)**: Opus 4.8/4.7 reject `temperature` and
`budget_tokens` (HTTP 400) and use `output_config.effort` + adaptive thinking; Sonnet
4.6 / Haiku 4.5 accept `temperature`; Haiku 4.5 does not support `effort`. Hard-coding
one request shape would 400 on some models. Treating capabilities as data satisfies the
source's "forward-compatible" requirement (FR-16) and SC-010. Default model is
`claude-opus-4-8` (latest, most capable). A custom model id is allowed; unknown ids get
a conservative capability default (no effort; temperature allowed) and the user can
adjust.

**Summarization defaults**: stream on; faithful mode (thinking off by default) with a
"begin directly, no preamble/meta-commentary" line in the global output convention so
Opus 4.8 with thinking disabled does not leak reasoning into the summary; `temperature
0.3` sent only to models that accept it; `max_tokens` default 4096 (raise per style);
`anthropic-version: 2023-06-01`.

## D5. Secret storage: Keychain generic password

**Decision**: Store the key as a `kSecClassGenericPassword` item (service
`com.sumbee.app`, account `anthropic-api-key`). Read on demand at request time;
never persisted elsewhere.

**Rationale**: Native, encrypted at rest, equivalent to/stronger than Electron
`safeStorage`. Ad-hoc signing may re-prompt across rebuilds in dev, acceptable for v1.

## D6. yt-dlp strategy (no build-time binary)

**Decision**: Discover `yt-dlp` at runtime in common locations (`/opt/homebrew/bin`,
`/usr/local/bin`, `$PATH`) and a user-set custom path in Settings; offer a "Download/
Update yt-dlp" action that fetches the latest release at runtime into Application
Support. If absent, the YouTube section shows the FR-013 "tool missing" state; the rest
of the app is fully functional.

**Rationale**: Bundling a binary would require build-time network and complicate the
universal build; runtime discovery/installation satisfies §13.2 cleanly and keeps the
build pure.

**Rejected**: bundling a checked-in `yt-dlp` binary (build-time network, bloat, staleness).

## D7. Concurrency posture

**Decision**: Swift language mode v5 for v1; `AppState` is `@MainActor`; services use
`async`/`await` and run off the main actor; streaming deltas are hopped back to the main
actor for UI updates. Sequential `JobQueue` for batches.

**Rationale**: Guarantees a smooth first build while keeping modern async structure;
strict-concurrency (v6) migration is a clean, isolated later step (recorded as future
work), not a rewrite. Honors the responsiveness NFR and source §16.5 (sequential batch).

## D8. Output convention & titling

**Decision**: The app appends a shared, format-aware instruction to every style prompt
requiring the model to begin with a single top-level title (`#` for Markdown, `<h1>`
for HTML) then the body; the app parses that title for the filename and falls back to
the source name if absent. HTML output appends the optional global HTML-styling prompt.

**Rationale**: Directly implements source §7.4 and keeps per-style prompts format-
agnostic; enables automatic, collision-safe filenames (D in file-layout contract).

## D9. Job-level retry queue (Revision 2, FR-021)

**Decision**: Retry at the **job** level, not inside the API client. A job caches its
extracted text + archived `source` ref after the first successful prepare; on a transient
failure it is re-queued (never re-extracting/re-archiving) with exponential backoff
(`5, 15, 30, 60, 120, 300`s, capped at 5 min, 6 auto-attempts) then left as a retryable
failure. A 1 s ticker promotes due jobs back to `queued`; a manual "Run queue" requeues
all waiting/failed jobs immediately and resets their backoff. Retryable = network,
overload, rate limit, and `403/404` (model unavailable / region-blocked, covers the
"VPN wrong country" case); non-retryable = bad/empty file, no captions, invalid key.

**Rationale**: Job-level retry covers environment failures (offline, VPN/region, model
not found), survives the whole 5-min window without blocking on a sleeping network call,
and integrates cleanly with a manual trigger. Splitting `prepare`/`finish` avoids
duplicate `source` archives on retry. **Rejected**: client-internal retry (couldn't
express the manual button or the prepare-once guarantee).

## D10. Square drop tiles with valid-type hover (Revision 2, FR-022)

**Decision**: File styles render in a `LazyVGrid` of square tiles. Each uses a custom
`DropDelegate` whose `validateDrop`/`dropEntered` calls `info.hasItemsConforming(to:)`
against the accepted UTTypes, so the orange-solid-border + outer-glow + lift only triggers
for a *valid* file type (a dragged `.png` does not light the tile). Drop still rejects
unsupported types with a message (defense in depth).

**Rationale**: `DropDelegate` is the only SwiftUI drop API that can inspect dragged item
types during hover; `.onDrop(isTargeted:)` cannot distinguish file kinds.

## D11. Live model list from Anthropic (Revision 2, FR-023)

**Decision**: `AnthropicClient.listModels(apiKey)` calls `GET /v1/models` and returns
`(id, displayName)`. `AppState.availableModels` defaults to the presets and is replaced
with the live list (mapped to `ModelPreset` via `ModelCatalog.capabilities(for:)`) after a
successful fetch on Settings open / key save. Capabilities still come from our catalog +
family heuristic, so a never-before-seen live id is gated correctly.

**Rationale**: Shows exactly what the account can use; degrades gracefully offline. We keep
capability data local (the request-shaping invariant) rather than trusting per-model
capability JSON we don't need.

## D12. Shared font system, sized large by default (Revision 4, FR-027)

**Decision**: Define a small set of named font tokens (`Font.uiTitle/uiHeadline/uiBody/
uiCallout/uiCaption`, design `.rounded`) in `Theme` and use them everywhere instead of
hard-coding sizes per view. Sizes start deliberately large (body ≈ 16pt) because macOS's
default text styles render small.

**Rationale**: One place to tune scale; consistent typography; avoids the drift this version
had before (scattered `.caption`/`.callout` literals). **Rejected**: `dynamicTypeSize`. On
macOS it barely scales the built-in text styles, so it cannot deliver an app-wide bump.
Fixed `.system(size:)` literals remain only for a few large display elements (icons, the drop
tile name) where an exact size is intentional.

## D13. Programmatic source link + HTML-aware token preset (Revision 4, FR-029/030)

**Decision**: The original source URL is never placed in the prompt (so the model can't alter
it); `PromptBuilder` sends only title/channel/duration. The app stamps the URL itself: the
Markdown `source:` front-matter, and for HTML a small centered grey underlined `<a>` injected
just before `</body>`. The default `maxOutputTokens` is 8192 (was 4096) because an HTML
document of the same summary is ~1.5–2× the tokens; a `schemaVersion` 1→2 migration adopts it
for installs still on the old default.

**Rationale**: Guarantees link fidelity and keeps the visible artifact self-describing;
prevents silent truncation of longer HTML summaries.

## D14. Default library lives outside ~/Documents (Revision 5, FR-031)

**Decision**: The default library is `~/Sumbee Summaries`, not `~/Documents/Summaries`. A one-time
migration (`AppState.migrateLibraryOutOfDocumentsIfNeeded`) moves legacy installs still on the
old default; custom locations and the `SUMBEE_LIBRARY` test override are left untouched.

**Rationale**: `~/Documents` (like `~/Desktop`/`~/Downloads`) is **TCC-protected**. Direct file
I/O works once the app has the Documents grant, but asking Finder to *open/reveal* a path inside
it is a stricter, separate operation that macOS silently refuses for apps it can't stably
identify, and an **ad-hoc-signed** dev build has no stable identity, so every rebuild looks like
a new app. The result was the long-running "Reveal in Finder just opens Home" bug (no error, no
second window). Verified empirically: revealing a non-protected folder (`~/Library/Application
Support/Sumbee`) worked while the `~/Documents` path silently fell back to Home. A plain
home-level folder has no TCC gate, so reveal works in dev and shipped builds with zero prompts.
**Rejected**: a guided Full Disk Access grant. It only sticks for a stable (signed) identity, so
ad-hoc dev builds would need re-granting on every rebuild, and FDA's coverage of the reveal path
was uncertain. Relocating is the guaranteed, prompt-free fix.

## D15. Shared system prompt, unified editor, sticky preview font (Revision 6, FR-034/035/036)

**Decision**: (a) Add `AppSettings.systemPrompt`, prepended by `PromptBuilder` in front of every
style prompt → assembled order is `[systemPrompt, stylePrompt, convention]`; empty by default so
it's a no-op until set. (b) Replace the stacked style-editor **sheet** with an inline, full-height
editor in the Settings detail pane, and route the system prompt, style prompts, and HTML-styling
prompt through one reusable `BigPromptEditor` (a tall monospaced `TextEditor`). The Settings panel
is enlarged so editors show many lines. (c) Add `AppSettings.previewFontSize` (default 16) with
+/- controls in the preview toolbar; `MarkdownText` scales body and headings proportionally.

**Rationale**: One place for shared instructions (no duplication across styles); a non-modal,
roomy editor is far better for writing/reading long prompts than a small floating sheet; readable
preview is a stated priority and the size must stick. **Decoding made field-tolerant**
(`decodeIfPresent` + defaults) so adding `systemPrompt`/`previewFontSize` never resets a config:
the prior synthesized `Codable` would have failed to decode older files and silently reset them.

## D16. Regenerate, geek mode, streaming, power-user touches (Revision 7, FR-037..044)

**Decisions & rationale**:
- **Regenerate (FR-037)** reuses the archived `source/` copy: the engine gains
  `prepareFromArchive(summaryURL:)` that reads the summary's front-matter `source`, then either
  re-extracts the archived file or re-fetches the YouTube URL, producing a `PreparedInput` WITHOUT
  re-archiving. `finish(...)` then runs with the chosen style/model/format and writes a **new**
  file. Non-destructive by design (re-running is exploratory; never clobber a kept result).
- **Geek mode (FR-039)** is a confirmation gate, not a new pipeline: when on, single-input actions
  route through a `PromptPreview` sheet (assembled `system` + `user` message from `PromptBuilder`)
  with a token estimate, then enqueue on Send. Token estimate uses a **local heuristic**
  (`ceil(chars / 3.7)`, labelled "~") rather than the count-tokens API, so it's instant and offline
  (accuracy beyond an order-of-magnitude isn't the point of an inspect mode). Batches skip the
  per-item gate to avoid N modal prompts.
- **Streaming preview (FR-040)** adds `AppState.streamingText`/`streamingJobID`, appended on
  `.streamDelta` (full text, not just the bottom-bar's 320-char tail). The preview pane shows the
  live text while a job runs, then falls back to the selected asset. One surface, no new window.
- **Per-style overrides (FR-038)** surface existing `SummaryStyle.modelOverride` in the editor;
  no model change.
- **Touches**: library search is a local title filter (NOT a tag/index system; folders stay the
  organizing model); drag-out exposes the file URL via `.onDrag`; Quick Look uses `QLPreviewPanel`;
  table/link rendering is a small extension to the existing `MarkdownText` (no CommonMark dep);
  ⌘F/⌘N via SwiftUI `commands`/`focused` state. All chosen to add capability without surface area.
