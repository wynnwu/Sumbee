# Phase 1 Data Model

Domain entities and their on-disk representations. Swift types live in
`Sources/SumbeeKit/Models/`.

## SummaryStyle

The core configurable object — a named prompt that also names a library folder.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Stable; survives folder renames. |
| `name` | `String` | Display name **and** folder name (e.g. "Meetings — General"). |
| `channel` | `Channel` (`.file` / `.youtube`) | `.file` → drop zone; `.youtube` → URL button. |
| `prompt` | `String` | The per-style instruction body. |
| `order` | `Int` | Sort order in UI. |
| `enabled` | `Bool` | Hide without deleting. |
| `modelOverride` | `ModelOverride?` | Optional per-style model/temperature/effort/format. |

**On disk**: `<root>/<Name>/style-definition/style-definition.md` — YAML frontmatter
(`id`, `channel`, `order`, `enabled`, optional overrides) + the prompt as the Markdown
body. The library folder, not config, is the source of truth (source §3.1, §8.5).

## Asset (generated summary)

| Field | Source |
|---|---|
| `url` | File location. |
| `title` | First `#`/`<h1>` (model-generated) or `title:` frontmatter. |
| `styleName` | Parent folder name. |
| `created` | Date-time prefix in filename + `created:` metadata. |
| `sourceRef` | `source:` metadata → archived original path or YouTube URL. |
| `format` | `.markdown` / `.html` from extension. |

**On disk**: `<root>/<Style>/YYYY-MM-DD HHmm — <Sanitized Title>.md` (or `.html`).
Markdown carries YAML frontmatter; HTML carries `<meta name="…">` tags + a leading
comment (source §8.2).

## SourceRef (archived input)

A date-stamped **copy** (never a move) of the original under `<root>/source/`:
`<original-basename>__YYYY-MM-DD_HHmmss.<ext>`. For YouTube, the cleaned transcript is
`<video-id>__<datetime>.txt` (source §8.3).

## AppSettings (versioned)

| Field | Default |
|---|---|
| `schemaVersion` | `2` |
| `libraryRoot` | `~/Sumbee Summaries` (NOT `~/Documents/…` — that's TCC-protected and blocks Reveal in Finder; a one-time migration moves legacy installs here) |
| `model` | `claude-opus-4-8` |
| `maxOutputTokens` | `8192` (headroom for HTML output) |
| `temperature` | `0.3` (sent only to models that accept it) |
| `effort` | `nil` (shown/sent only where supported) |
| `extendedThinking` | `false` |
| `captionLanguage` | `en` |
| `outputFormat` | `.markdown` |
| `htmlStylingPrompt` | `""` |
| `systemPrompt` | `""` (prepended in front of every style prompt — FR-034) |
| `previewFontSize` | `16` (sticky preview base font — FR-036) |
| `ytDlpPath` | `nil` (auto-discover) |
| `windowState` | last frame |

Stored as JSON at `~/Library/Application Support/Sumbee/config.json`. **Excludes**
styles (on-disk library) and the API key (Keychain). Versioned for migration (§8.4).
Decoding is **field-tolerant** (`decodeIfPresent` with defaults), so adding a new field never
resets an existing config.

## ModelCatalog & ModelCapabilities (forward-compatible request shaping)

`ModelCatalog` lists presets and maps each id → `ModelCapabilities`:

| Capability | Opus 4.8 / 4.7 | Sonnet 4.6 | Haiku 4.5 | Unknown (custom) |
|---|---|---|---|---|
| `supportsTemperature` | false | true | true | true (conservative) |
| `supportsEffort` | true | true | false | false |
| `effortLevels` | low…xhigh,max | low…max | — | — |
| `supportsAdaptiveThinking` | true | true | false | false |
| `maxOutputCeiling` | 128000 | 64000 | 64000 | 8192 |

Presets: `claude-opus-4-8` (default), `claude-sonnet-4-6`, `claude-haiku-4-5`, plus a
free-text custom id. The request builder reads these flags so a parameter is never sent
to a model that would reject it (SC-010, FR-013).

## Job (transient, not persisted)

| Field | Notes |
|---|---|
| `id` | `UUID`. |
| `displayName` | source filename / video title. |
| `styleId` | target style. |
| `phase` | `.queued/.extracting/.fetching/.summarizing/.saving/.done/.failed/.cancelled`. |
| `progressText` | streamed-output preview / status line. |
| `error` | friendly message on failure. |

Lives only in `AppState`; drives the bottom-bar status and per-zone state.
