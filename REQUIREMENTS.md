# Sumbee — Requirements Specification

**Status:** Draft v1 · **Date:** 2026-06-20 · **Platform:** macOS (desktop)

A minimal macOS app for turning meeting transcripts, interview transcripts, and YouTube
videos into clean, saved-to-disk summaries. Each summary "style" is just a configurable
prompt. Inputs are dropped as text files (or pasted as a YouTube URL); outputs are
Markdown files organized into a local folder the user controls.

---

## 1. Goals & Non-Goals

### Goals

- Drag-and-drop a transcript file onto a style → get a saved Markdown summary.
- Paste a YouTube URL → pick a style → get a saved Markdown summary from the video's captions.
- Summary styles are user-editable prompts (full CRUD in Settings).
- All outputs live in a plain folder on disk, organized by style, so the library is just
  files the user owns — usable in Finder, Obsidian, git, etc.
- Original dropped files are archived into the project so the user can delete the source
  and lose nothing.
- API key stored securely; the app refuses to run until a key is set.

### Non-Goals (v1)

- **No audio/video transcription.** Inputs are already text. (YouTube uses existing captions
  via yt-dlp; see §6.) Audio/video transcription is explicitly out of scope and noted as a
  future option in §15.
- No cloud sync, accounts, or multi-user features. Everything is local except calls to the
  Anthropic API.
- No Windows/Linux build in v1 (architecture should not preclude it later).
- No rich text editor for outputs — summaries are Markdown (default) or HTML files opened in
  the user's editor/browser of choice. A read-only in-app preview is a "should have," not
  "must have."

---

## 2. Tech Stack & Architecture

### 2.1 Stack

| Concern | Choice | Notes |
|---|---|---|
| Shell | **Electron** | Chosen for the richest ecosystem for DOCX/PDF/RTF parsing, the official Anthropic SDK, and easy yt-dlp invocation. |
| Renderer (UI) | **React + TypeScript + Vite** | Light, maintainable. Swappable for Svelte/vanilla if preferred — UI is simple. |
| Styling | Plain CSS or Tailwind | Keep minimal; native-feeling macOS look (system font, vibrancy optional). |
| Main process | Node (TypeScript) | Owns filesystem, Keychain, yt-dlp, and **all** Anthropic API calls. |
| Packaging | **electron-builder** | Universal (arm64 + x64) `.dmg`, code-signed + notarized. |

### 2.2 Process model & security boundary

- `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true` where feasible.
- A typed **preload** bridge exposes a narrow IPC surface (e.g. `window.api.summarizeFile`,
  `window.api.summarizeYouTube`, `window.api.listAssets`, `window.api.getSettings`, …).
- **The Anthropic API key never reaches the renderer.** The renderer asks the main process to
  run a job; the main process reads the key from secure storage, calls the API, and returns
  results/progress over IPC.
- yt-dlp is invoked only from the main process via `child_process` with argument arrays (no
  shell string interpolation of user input).

### 2.3 High-level flow

```
Renderer (UI)
  │  drop file / paste URL + choose style
  ▼
Preload (typed IPC)
  ▼
Main process
  ├─ extract text (file parser  OR  yt-dlp captions)
  ├─ archive source → /source
  ├─ build prompt (style prompt + transcript) → Anthropic API (streamed)
  ├─ parse title from response → write asset .md to style folder
  └─ emit progress + completion events back to renderer
```

---

## 3. Domain Model

### 3.1 Summary Style

The core configurable object. A style is essentially a named prompt.

| Field | Type | Description |
|---|---|---|
| `id` | string (uuid) | Stable identifier. |
| `name` | string | Display name + **folder name** in the library (e.g. "Meetings — General"). |
| `channel` | `"file"` \| `"youtube"` | `file` styles render as **drop zones**; `youtube` styles render as **buttons** under the URL box. |
| `prompt` | string | The instruction text sent to the model (see §10 for defaults). |
| `order` | number | Sort order in the UI. |
| `modelOverride` | object \| null | Optional per-style overrides for model/temperature/etc. (nice-to-have; global defaults otherwise). |
| `enabled` | boolean | Hide a style without deleting it. |

> A style's `channel` determines where it appears. Default seeds: 4 `file` styles + 1
> `youtube` style (§10). The UI supports any number of each.

> **Persistence.** Each style is stored on disk inside its own library folder at
> `<Style Name>/style-definition/style-definition.md` — the prompt is the file body, the other
> fields are YAML frontmatter (see §8.5). The **library folder, not `config.json`, is the
> source of truth for styles**, so the full set of styles travels with the library and
> survives folder renames.

### 3.2 Asset (a generated summary)

A Markdown (default) or HTML file on disk plus light metadata derived from its
path/frontmatter (or, for HTML, embedded `<meta>`/comment metadata — see §8.2).

| Field | Source |
|---|---|
| Title | First H1 of the file (model-generated; see §7.4). |
| Style | Parent folder. |
| Created | Date-time prefix in filename + `created:` frontmatter. |
| Source ref | `source:` frontmatter pointing at the archived original (or YouTube URL). |

### 3.3 Source (archived input)

The original dropped file (or fetched YouTube transcript), copied into `/source` with a
date-time appended to its name so the user can delete the original safely.

---

## 4. Interface

Single main window. Three regions: **Main Panel** (left), **Asset Browser** (right), and a
**thin bottom bar**. Settings opens as a full-window panel/overlay from the gear icon.

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   MAIN PANEL (left)              │   ASSET BROWSER (right)    │
│   ┌───────────────────────────┐  │   ▸ Meetings — General    │
│   │ FILE STYLES (drop zones)  │  │     2026-06-20 1432 — …   │
│   │  [ Meetings — General  ]  │  │     2026-06-19 0915 — …   │
│   │  [ Product Review      ]  │  │   ▸ Product Review        │
│   │  [ Interview — Short   ]  │  │   ▸ Interview — Short     │
│   │  [ Interview — Long    ]  │  │   ▸ Interview — Long      │
│   ├───────────────────────────┤  │   ▸ YouTube               │
│   │ YOUTUBE                   │  │   ▸ source                │
│   │  URL: [______________]    │  │                           │
│   │  [Summary] [⋯ styles]     │  │                           │
│   └───────────────────────────┘  │                           │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ ⚙                                              (status / job) │  ← thin bottom bar
└──────────────────────────────────────────────────────────────┘
```

### 4.1 Main Panel (left)

Two stacked sections.

**Top — File styles (drop zones).** One drop zone per `file`-channel style, generated
dynamically from configured styles (so adding a style in Settings adds a drop zone). Each
zone:

- Accepts `.md`, `.docx`, `.pdf`, `.txt`, `.rtf`.
- Highlights on drag-over; rejects unsupported types with an inline message.
- Accepts **multiple files** at once → each file becomes its own job/asset (queued).
- Shows per-job state (parsing → summarizing → done / error) with a cancel control.
- Clicking a zone opens a normal file picker as an alternative to dragging.

**Bottom — YouTube.** A URL text field + one button per `youtube`-channel style. Pressing a
style button validates the URL, fetches captions via yt-dlp, summarizes with that style, and
saves the asset. Invalid/empty URL disables the buttons with a hint.

### 4.2 Asset Browser (right)

- A file tree of the **library root** (§8). Top level = one folder per style + a `source`
  folder.
- Items are summary files named `YYYY-MM-DD HHmm — <Title>.md`, sorted newest-first.
- Click an asset → read-only Markdown preview (should-have) and/or actions: **Reveal in
  Finder**, **Open in default editor**, **Copy**, **Delete**.
- Live-refreshes when new assets are written (watch the directory).
- Because assets are just files, anything the user does in Finder is reflected here.

### 4.3 Bottom bar

- Thin strip across the bottom. **Gear icon bottom-left** → opens Settings.
- Right side shows current job status / progress (e.g. "Summarizing 1 of 2…") and surfaces
  errors as dismissible toasts.

### 4.4 Settings panel

Opens from the gear. Sections detailed in §9. Includes the **API-key gate** (§11): if no key
is stored, the app opens to Settings on launch and disables summarization until a key is
saved (and ideally validated).

---

## 5. Functional Requirements — File Summarization

- **FR-1 Accept drops.** Each file drop zone accepts `.md`, `.docx`, `.pdf`, `.txt`, `.rtf`
  (single or multiple). Unsupported extensions are rejected with a clear message.
- **FR-2 Extract text.** The main process extracts plain text per format:
  - `.txt` / `.md` — read UTF-8 directly (Markdown passed through as-is).
  - `.docx` — `mammoth` (clean text/Markdown extraction).
  - `.pdf` — `pdf-parse` (fallback `pdfjs-dist` for tricky PDFs). Image-only/scanned PDFs
    have no text layer → surface a clear "no extractable text (scanned?)" error. OCR is out
    of scope.
  - `.rtf` — a JS RTF-to-text library (e.g. `rtf-parser` / `node-rtf`) to avoid system deps.
- **FR-3 Archive source.** Before/after extraction, copy the original into
  `/<root>/source/` renamed `<originalname>__YYYY-MM-DD_HHmmss.<ext>` (§8.3). Never move the
  user's original out of its location — copy only.
- **FR-4 Summarize.** Send `style.prompt` + extracted transcript to the Anthropic API
  (§7). Stream output; show progress; allow cancel.
- **FR-5 Save asset.** Write the result to the style's folder using the naming scheme in
  §8.2, in the configured **output format** (Markdown default, or HTML — §9.6), with metadata
  linking back to the archived source (YAML frontmatter for `.md`; `<meta>`/comment block for
  `.html`).
- **FR-6 Batch.** Multiple dropped files are queued and processed sequentially (configurable
  small concurrency later); each produces its own asset and source archive. One failure does
  not abort the batch.
- **FR-7 Empty/oversized input.** Empty extraction → error, no API call. Inputs exceeding the
  model context window → warn; v1 may truncate with an explicit notice; chunked map-reduce
  summarization is a documented future enhancement (§15).

---

## 6. Functional Requirements — YouTube (via yt-dlp)

- **FR-8 URL input.** Validate that the pasted string is a recognizable YouTube URL (watch,
  youtu.be, shorts). Show a hint on invalid input.
- **FR-9 Fetch captions with yt-dlp.** The main process shells out to a **bundled `yt-dlp`
  binary** to retrieve the caption/subtitle track without downloading video, e.g.:

  ```
  yt-dlp --skip-download \
         --write-subs --write-auto-subs \
         --sub-langs "en.*" --sub-format vtt \
         --convert-subs vtt \
         -o "<tmpdir>/%(id)s.%(ext)s" <URL>
  ```

  - Also capture metadata for the title/context via `--print "%(title)s"` /
    `--dump-json` (title, channel, duration, upload date).
  - Prefer human-authored subs; fall back to auto-generated. Allow a configurable language
    (default English) in Settings.
- **FR-10 Parse captions to transcript.** Convert the `.vtt` to clean text: strip cue
  numbers/timestamps and de-duplicate the rolling/overlapping lines auto-captions produce.
  Optionally retain coarse timestamps (e.g. every ~30s) so styles can cite them — the
  YouTube default prompt is timestamp-aware (§10.5).
- **FR-11 Archive transcript.** Save the cleaned transcript to `/source` as
  `<video-id>__YYYY-MM-DD_HHmmss.txt`, and record the original URL in the asset frontmatter.
- **FR-12 Summarize + save.** Same pipeline as files (FR-4/FR-5), into the chosen YouTube
  style's folder.
- **FR-13 Failure modes.** Handle and clearly message: no captions available (suggest a
  different video; note transcription is a future feature), age/region restriction, private/
  deleted video, live stream, network failure, and **yt-dlp missing or outdated** (offer to
  update — see §13.2).

---

## 7. Anthropic API Integration

- **FR-14 SDK & location.** Use `@anthropic-ai/sdk` in the **main process only**. The key is
  read from secure storage per request and never persisted in logs or the renderer.
- **FR-15 Request shape.** A single Messages request: a system prompt assembled from the
  style prompt + global output conventions (§7.4), and a user message containing the
  transcript (and, for YouTube, light metadata + optional timestamps).
- **FR-16 Parameters (from Settings, §9.2).**
  - **Model** — selectable; ship current model identifiers as presets:
    `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`. Allow a custom
    string for forward-compatibility. (Verify/update the list against the API at build time.)
  - **Temperature** — 0–1 slider (default 0.3 for faithful summaries).
  - **Max output tokens** — numeric (sensible default, e.g. 4096; raise for long-interview
    style).
  - **Effort / extended thinking** — expose whatever the selected model supports for
    reasoning effort (e.g. an extended-thinking toggle + token budget). Treat this as a
    forward-compatible setting: render the control only when the chosen model supports it,
    and pass the corresponding API parameter. Do not hard-code an "effort" value that the API
    may not accept.
- **FR-17 Streaming & cancel.** Stream responses; relay incremental progress to the UI; let
  the user cancel an in-flight job (abort the request).
- **FR-18 Error handling.** Map API errors to friendly messages and behavior:
  - `401` invalid key → prompt to fix the key in Settings (re-gate).
  - `429` rate limit / `529` overloaded → backoff + retry with notice.
  - Network/timeouts → retry option; never silently fail.
- **FR-19 Privacy notice.** Settings clearly states that transcript text is sent to the
  Anthropic API for summarization; everything else stays local.

### 7.4 Output convention (enables auto-titling)

Every style prompt ends with a shared instruction (injected by the app, not stored per style)
requiring the model to **begin its response with a single top-level title heading**
(a `# <concise 4–8 word title>` H1 in Markdown, or `<h1>…</h1>` in HTML) followed by the
body. The app parses that title to build the filename (§8.2) and stores the full document as
the asset. If no title heading is found, fall back to the source filename / video title.

This shared convention is **format-aware** and is what makes the per-style prompts in §10
format-agnostic: those prompts only describe the *structure* (sections/content). When the
configured **output format** (§9.6) is:

- **Markdown** — the app instructs the model to emit Markdown (sections as `##` headings, the
  default).
- **HTML** — the app instructs the model to emit a complete, self-contained HTML document and
  appends the optional global **HTML styling prompt** (§9.6) so colors, fonts, and CSS are
  consistent across every HTML summary. The same section structure maps onto HTML headings.

Optionally, for stronger determinism, the app may instead wrap the model's HTML *body* in a
fixed CSS template/stylesheet rather than relying solely on the styling prompt; the prompt-
based approach is the default per this spec.

---

## 8. Data & File Layout

### 8.1 Library root

A single user-chosen folder (Settings, §9.3). Default suggestion: `~/Documents/Summaries`.
The app creates style folders and `source/` on demand.

```
<root>/
├── Meetings — General/
│   ├── style-definition/
│   │   └── style-definition.md          # this style's prompt + metadata (§8.5)
│   └── 2026-06-20 1432 — Q2 Roadmap Sync.md
├── Meetings — Product Review/
│   └── style-definition/style-definition.md
├── Interviews — Short/
│   └── style-definition/style-definition.md
├── Interviews — Long/
│   └── style-definition/style-definition.md
├── YouTube/
│   ├── style-definition/style-definition.md
│   └── 2026-06-20 1455 — How Transformers Work.md
└── source/
    ├── q2-sync-transcript__2026-06-20_143205.docx
    └── dQw4w9WgXcQ__2026-06-20_145511.txt
```

- One folder **per style**, named by the style's display name, each containing a
  `style-definition/style-definition.md` (§8.5) that holds its prompt + metadata — so styles
  are self-describing and rename-safe.
- `source/` holds every archived input (§8.3); it has no `style-definition/`, so the app does
  not treat it as a style.

### 8.2 Asset filename scheme

```
YYYY-MM-DD HHmm — <Sanitized Title>.md      # or .html when HTML output is selected (§9.6)
```

- Extension is `.md` by default, `.html` when the output format (§9.6) is HTML.
- Date-time = job completion (local time), zero-padded, filesystem-safe (no `:`).
- Title = model-generated title heading (§7.4), sanitized: strip/replace `/ \ : * ? " < > |`,
  collapse whitespace, trim length (~80 chars).
- **Collisions:** append ` (2)`, ` (3)`, … before the extension.
- **Metadata.** For Markdown, YAML frontmatter at the top of the file:

  ```yaml
  ---
  title: Q2 Roadmap Sync
  style: Meetings — General
  created: 2026-06-20T14:32:05-07:00
  source: source/q2-sync-transcript__2026-06-20_143205.docx   # or a YouTube URL
  model: claude-sonnet-4-6
  ---
  ```

  For HTML, the same fields are embedded as `<meta name="…">` tags in `<head>` (plus an
  optional leading `<!-- … -->` comment), since YAML frontmatter would render as visible text
  in a browser.

### 8.3 Source archive scheme

```
<original-basename>__YYYY-MM-DD_HHmmss.<ext>
```

- Files are **copied** (never moved) into `source/`. For YouTube, the cleaned transcript is
  written as `<video-id>__<datetime>.txt`.
- Guarantees the brief's requirement: the user can delete their original and the project still
  contains everything.

### 8.4 App configuration storage

- App settings (model params, library path, caption language, output format + HTML styling
  prompt, window state) in a JSON file under Electron `app.getPath('userData')` (e.g.
  `config.json`).
- **Style definitions are NOT stored here.** Each style lives in its own library folder at
  `<Style Name>/style-definition/style-definition.md` (§8.5); the library is the source of
  truth for styles. `config.json` may cache a lightweight index for fast startup, but the
  on-disk definitions win on conflict.
- **The API key is NOT stored here** — see §11.
- Config schema is versioned for safe migrations.

### 8.5 Style definition files (on-disk styles)

Each style is **self-contained in its own folder**, so the library fully describes itself and
survives being moved or renamed in Finder:

```
<root>/Meetings — General/
├── style-definition/
│   └── style-definition.md        ← this style's prompt + metadata
├── 2026-06-20 1432 — Q2 Roadmap Sync.md
└── …more assets…
```

- **Discovery.** On launch (and via directory watch), the app scans the library root and
  treats any folder containing `style-definition/style-definition.md` as a style. Folders
  without it (e.g. `source/`) are ignored as styles. The `style-definition/` subfolder is
  excluded from the asset browser's file listing.
- **Format.** `style-definition.md` stores metadata as YAML frontmatter and the **prompt as
  the Markdown body**:

  ```yaml
  ---
  id: 6f1c0b2a-…           # stable UUID; survives folder renames
  channel: file            # file | youtube
  order: 1
  enabled: true
  # optional per-style overrides:
  # model: claude-opus-4-8
  # temperature: 0.2
  ---
  ```
  *(the prompt text follows as the document body — e.g. the §10.1 prompt)*

- **Display name = folder name.** The name shown in the UI is the style's folder name.
- **What happens when the folder name changes?** Because the prompt lives *inside* the folder,
  renaming the folder — in the app **or** directly in Finder — keeps the prompt attached and
  simply updates the display name. The stable `id` lets the app keep tracking the same style
  across renames; existing assets stay where they are.
- These are plain Markdown files, so a user may also edit a prompt directly on disk; the app
  picks up the change on its next scan. The app remains the primary writer during CRUD (§9.4).

---

## 9. Settings

### 9.1 API key (required, gated)

- Field to enter/update the Anthropic API key, stored securely (§11).
- **Save & Validate** button does a cheap test call; show success/failure.
- The app blocks summarization until a valid key is stored (§11 gate).

### 9.2 Model & generation options

- Model picker (presets + custom string).
- Temperature, max output tokens.
- Effort / extended-thinking control, shown only when the selected model supports it (§7.4
  / FR-16).
- (Nice-to-have) per-style overrides.

### 9.3 Library directory

- Folder picker for the library root (§8.1). Changing it does not move existing files; show
  the active path and a "Reveal in Finder" action. Validate writability.

### 9.4 Summary styles (CRUD)

- List all styles with `channel` (file/youtube), name, enabled toggle, drag-to-reorder.
- **Create / Read / Update / Delete** styles; edit `name`, `channel`, and `prompt` in a
  multi-line editor. Edits are written to the style's on-disk `style-definition.md` (§8.5):
  creating scaffolds the folder + definition; renaming the name renames the folder (assets
  move with it); editing the prompt/metadata rewrites the definition.
- "Reset to defaults" restores the seeded styles (§10).
- Deleting a style removes its `style-definition/` so it no longer appears as a style, but
  **keeps the folder and its asset files** (warn first); the user's summaries are never
  deleted.

### 9.5 YouTube / yt-dlp

- Caption language preference (default `en`).
- yt-dlp status + **Update yt-dlp** action (§13.2).

### 9.6 Output format & HTML styling

- **Output format** — choose how summaries are saved: **Markdown (`.md`, default)** or
  **HTML (`.html`)**. Global default; optional per-style override (consistent with the
  per-style model override in §3.1 / §9.2).
- **HTML styling prompt (optional)** — a single, shared, free-text prompt applied to **all**
  HTML output. It is appended to the style prompt (via the format-aware convention in §7.4)
  whenever HTML is produced, so every HTML summary shares consistent styling — colors, fonts,
  spacing, and CSS. Example guidance a user might put here: brand palette, light/dark
  preference, "use a single inline `<style>` block, system font stack, max-width 720px,
  accessible contrast." Leaving it empty yields clean, unstyled semantic HTML.
- Because this styling prompt is global (not per-style), all HTML summaries look consistent
  regardless of which style generated them. (See §7.4 for the optional CSS-template
  alternative if fully deterministic styling is needed later.)

---

## 10. Default Summarization Styles (seeded prompts)

Seeded on first run; fully editable in Settings. Each prompt below is the per-style body; the
app appends the shared output convention from §7.4 (begin with an H1 title). Channels: §10.1–4
are `file`; §10.5 is `youtube`.

### 10.1 Meetings — General  *(channel: file)*

```
You are summarizing a general meeting transcript. Produce a clear, faithful summary that
someone who missed the meeting could read in two minutes and know what happened and what
to do next. Do not invent information; if something is unclear, say so.

Use these sections:

## TL;DR
3–5 sentences capturing the purpose and outcome of the meeting.

## Key Discussion Points
Bulleted topics discussed, each with a one–two sentence summary of what was said and any
differing views.

## Decisions
Each decision made, stated plainly. If no decisions were made, write "None recorded."

## Action Items
A checklist. For each item: the task, the owner (name) if stated, and a due date if stated.
Format: "- [ ] <task> — <owner> (due <date>)". Omit owner/date if not mentioned rather than
guessing.

## Open Questions / Parking Lot
Unresolved questions or items deferred for later.

## Next Steps
What happens next and when the group reconvenes, if mentioned.
```

### 10.2 Meetings — Product Review (Definitive To-Dos)  *(channel: file)*

```
You are summarizing a product review meeting. The single most important output is a list of
DEFINITIVE, actionable to-dos — specific enough that an owner could pick one up and start
without re-watching the meeting. Be precise and concrete. Never produce vague to-dos like
"improve onboarding"; instead capture the specific change, scope, and acceptance criteria
discussed. Do not invent owners, dates, or decisions.

Use these sections:

## TL;DR
3–4 sentences: what was reviewed and the headline outcome.

## What Was Reviewed
The feature/product/release under review and its current state/goal.

## Decisions
Each decision made during the review, stated unambiguously (ship / hold / change direction /
needs more data, etc.).

## Definitive To-Dos
A checklist of concrete, owned actions. For each:
"- [ ] <specific action with enough scope to act on> — <owner if stated> (due <date if
stated>) — Acceptance: <how we'll know it's done, if discussed>"
Split compound items into separate to-dos. Flag any to-do that lacks an owner as
"(owner: UNASSIGNED)".

## Risks, Concerns & Open Questions
Risks raised, blockers, and questions that must be answered, with who/what they depend on.

## Follow-ups
Next review checkpoint, demos owed, or stakeholders to update.
```

### 10.3 Interviews — Short  *(channel: file)*

```
You are summarizing a job interview transcript into a concise scorecard a hiring manager can
read in about a minute. Be fair, evidence-based, and concise. Base every judgment on what was
actually said; do not speculate about the candidate beyond the transcript.

Use these sections:

## Snapshot
Role, candidate (first name/initials if present), interview type, and your one-line
read.

## Strengths
3–5 bullets, each tied to a specific moment or answer from the interview.

## Concerns
2–4 bullets of weaknesses, gaps, or risks, each grounded in the transcript.

## Notable Answers
1–3 brief highlights (a strong/weak/illustrative response), paraphrased.

## Recommendation
One of: Strong Hire / Hire / Lean Hire / Lean No / No Hire — with a one–two sentence
rationale and your confidence (low/medium/high). Note this is decision support, not a final
verdict.
```

### 10.4 Interviews — Long  *(channel: file)*

```
You are producing a thorough interview debrief from a long interview transcript. Be
structured, fair, and evidence-based, citing specific moments. Distinguish clearly between
what the candidate demonstrated and your inference. Do not fabricate.

Use these sections:

## Overview
Role, candidate, interview type/format, and a 3–4 sentence executive summary.

## Background & Experience
Relevant experience surfaced in the conversation.

## Competency Assessment
Sub-bullets rating and evidencing each relevant area discussed, e.g.:
- Technical / domain depth
- Problem-solving & reasoning
- Communication & collaboration
- Ownership & impact
- Role/culture fit
For each: a short evidenced assessment (strong / mixed / weak + why).

## Detailed Highlights
The most informative exchanges, paraphrased, in rough order, with what each revealed.

## Strengths
Bulleted, evidence-linked.

## Concerns & Risks
Bulleted, evidence-linked, including anything to probe further.

## Questions for the Next Round
Specific follow-ups a later interviewer should pursue.

## Overall Recommendation
Strong Hire / Hire / Lean Hire / Lean No / No Hire, with rationale and confidence
(low/medium/high). Frame as decision support.
```

### 10.5 YouTube — Summary  *(channel: youtube)*

```
You are summarizing a YouTube video from its transcript. The transcript may include rough
timestamps; when present, cite them as (mm:ss) so the reader can jump to the relevant part.
Auto-generated captions can be messy or mis-transcribe names/terms — infer sensible meaning
but do not invent facts. If the video's topic or structure is unclear, say so.

Use these sections:

## TL;DR
3–5 sentences: what the video is about and its core message or conclusion.

## Key Takeaways
5–8 bullets of the most important points, insights, or claims.

## Detailed Notes
The substance of the video in order, grouped by topic/segment, with (mm:ss) timestamps where
available. Capture the reasoning, examples, and any steps or arguments — enough that the
reader gets the value without watching.

## Notable Quotes
0–3 short, verbatim-as-possible quotes worth remembering (with timestamps if available).

## Resources & Mentions
Tools, people, links, books, or references mentioned in the video.

## Actionable Insights
What a viewer could actually do with this — concrete takeaways or next steps. Omit if not
applicable.
```

> The brief lists exactly these five styles. The UI supports adding more `youtube` styles
> (e.g. "YouTube — Quick TL;DR") which would each appear as another button under the URL box.

---

## 11. Security — API Key

- **Storage:** Use Electron's built-in **`safeStorage`** API to encrypt the key
  (Keychain-backed on macOS) and store only the ciphertext in `userData` (or store via
  `keytar` in the system Keychain as an alternative). Prefer `safeStorage` to avoid native
  module/build friction.
- **Never** write the key to plaintext config, logs, crash reports, or the renderer.
- **Required-before-use gate:** On launch, if no key is stored, the app opens to Settings and
  disables all summarization (drop zones + YouTube buttons show a "Set your API key to begin"
  state). Re-gate automatically on a `401`.
- Provide a "Remove key" action that clears it from secure storage.

---

## 12. Non-Functional Requirements

- **Privacy:** Only transcript text + prompts go to Anthropic; YouTube fetching goes to
  YouTube via yt-dlp. No other telemetry by default. State this in Settings.
- **Offline behavior:** Browsing/opening existing assets works offline. Summarization and
  YouTube fetching require network; fail gracefully with clear messaging.
- **Performance:** UI stays responsive during jobs (work in main process / off the UI
  thread); stream output; show progress; allow cancel.
- **Reliability:** A single file or API failure must not crash the app or abort a batch.
- **Compatibility:** Universal build (Apple Silicon + Intel). Minimum macOS = **Sequoia
  (macOS 15)**.
- **Accessibility:** Keyboard-operable, sensible focus order, respects system Dark Mode.

---

## 13. Dependencies & Tooling

### 13.1 npm (indicative)

| Purpose | Package |
|---|---|
| App shell | `electron`, `electron-builder`, `vite`, `react`, `typescript` |
| Anthropic | `@anthropic-ai/sdk` |
| DOCX | `mammoth` |
| PDF | `pdf-parse` (+ `pdfjs-dist` fallback) |
| RTF | `rtf-parser` / `node-rtf` (pure-JS preferred) |
| yt-dlp wrapper | `yt-dlp-wrap` or direct `child_process` |
| Secure key | Electron `safeStorage` (built-in) or `keytar` |

### 13.2 Bundled binaries

- **yt-dlp:** Bundle the binary for arm64 and x64 (resolve at runtime by arch). Provide an
  **Update yt-dlp** action in Settings (download latest release) since YouTube changes often.
- **ffmpeg:** Not required for v1 (captions-only; no audio download). If audio transcription
  is added later (§15), ffmpeg would need bundling.

---

## 14. Packaging & Distribution

- **v1:** `electron-builder` produces a **local/dev unsigned** universal (arm64 + x64) build
  for personal use on macOS Sequoia — no Apple Developer ID, signing, or notarization
  required. (Gatekeeper may require a right-click → Open on first launch; acceptable for
  local/dev use.)
- **For public distribution (deferred):** sign + **notarize** the universal `.dmg` with an
  Apple Developer ID so Gatekeeper allows it without warnings.
- Bundle yt-dlp and set the hardened-runtime entitlements needed to execute a bundled binary
  and make network requests (required once signing/notarizing).
- (Future) `electron-updater` auto-update channel.

---

## 15. Future / Out of Scope (documented, not v1)

- **Audio/video transcription** (drop `.mp3/.m4a/.mp4/.wav`; YouTube without captions) via
  Whisper or a transcription API — would add ffmpeg + a transcription step.
- **Chunked map-reduce** summarization for transcripts exceeding the context window.
- In-app Markdown editing of assets; export to PDF/DOCX.
- Per-style model overrides UI.
- Search across the asset library; tags.
- Windows/Linux builds; auto-update.

---

## 16. Open Questions / Assumptions

Assumptions made for this draft — **all resolved per review** (kept here as a decision log):

1. **Output format = Markdown (`.md`) default, with optional HTML (`.html`).** Resolved per
   review: HTML is a selectable output format, plus a shared, optional **HTML-styling prompt**
   for consistent CSS/colors/fonts across all HTML summaries (§9.6, §7.4). Direct
   `.docx`/`.pdf` export remains future scope (§15).
2. **Folder = style name; prompt lives in the folder.** Resolved per review: the folder is
   named by the style's display name, and each style's prompt + metadata is stored inside it at
   `style-definition/style-definition.md` (§8.5). Renaming the folder (app or Finder) keeps the
   prompt attached and just updates the display name; a stable `id` in the definition tracks
   the style across renames. Existing assets stay where they are.
3. **Caption language default = English; human subs preferred over auto.** Resolved per
   review: confirmed. (Configurable in Settings §9.5.)
4. **Title source = model H1.** The app instructs the model to emit an H1 title used for the
   filename. Resolved per review: confirmed.
5. **Batch concurrency = sequential** in v1 (simplest, kindest to rate limits). Resolved per
   review: confirmed.
6. **Minimum macOS version = Sequoia (macOS 15).** Resolved per review. **v1 ships as a
   local/dev unsigned build** — no signing or notarization required; a notarized, signed
   universal build (§14) is deferred until public distribution.

---

*End of specification v1.*
