# Revision 7 — Implementation Guide

Covers **FR-037..FR-044**: Regenerate, per-style overrides UI, Geek mode (prompt preview + token
estimate), streaming preview, library search, drag-out & Quick Look, richer preview, keyboard
shortcuts. Read alongside `../spec.md` (requirements) and `../research.md` (D16, decisions).

**Guiding principle:** deepen the core, add no surface area. Several features reuse existing
machinery — the archived `source/` (Regenerate), the SSE stream (Streaming), `SummaryStyle.
modelOverride` (overrides). Prefer wiring over new subsystems.

## Recommended build order

1. **Foundations** — `AppSettings.geekMode`; `AppState.streamingText`/`streamingJobID`.
2. **Streaming preview (FR-040)** — small, validates the foundation.
3. **Library search + ⌘F + ⌘N (FR-041/044)** — self-contained.
4. **Drag-out & Quick Look (FR-042)** — self-contained.
5. **Richer preview: tables + links (FR-043)** — isolated to `MarkdownText`.
6. **Per-style overrides UI (FR-038)** — style editor only.
7. **Regenerate (FR-037)** — engine `prepareFromArchive` + a picker.
8. **Geek mode preview + token estimate (FR-039)** — depends on a prompt-assembly helper; touches the enqueue path; do last.

Build + `swift test` after each group. Keep the dev-only screenshot hooks (`SUMBEE_OPEN_SETTINGS`,
`SUMBEE_SETTINGS_SECTION`, `SUMBEE_EDIT_FIRST_STYLE`) for verification.

---

## 0. Foundations

**`Models/AppSettings.swift`**
- Add `public var geekMode: Bool` (default `false`). Add to `init`, to `CodingKeys`, and to the
  field-tolerant `init(from:)` (`decodeIfPresent ?? d.geekMode`). (Decoding is already tolerant —
  D15 — so this won't reset configs.)

**`State/AppState.swift`**
- Add `@Published public var streamingText: String = ""` and `@Published public var streamingJobID: UUID?`.
- These are cleared when no job is streaming (see FR-040).

---

## 1. Streaming preview (FR-040)

**Goal:** the right-hand preview pane shows the summary as it streams, then settles on the saved file.

**`State/AppState+Jobs.swift`**
- In `apply(_:to:)` `.streamDelta`: in addition to the existing 320-char `job.preview`, set
  `streamingJobID = id` and append the delta to `streamingText`.
- At the start of `runJob` (just before `finish`): reset `streamingText = ""`, `streamingJobID = job.id`.
- On terminal outcomes (`done`, `failed`, `cancelled`) for the streaming job: clear
  `streamingText = ""`, `streamingJobID = nil`. On success the library reloads and `selectedAsset`
  is set to the new file, so the pane naturally shows the saved result.

**`Views/AssetBrowser/MarkdownPreview.swift`** (`PreviewPane`)
- When `state.streamingJobID != nil` (a job is generating), show a "Generating…" header + a live
  `MarkdownText(raw: state.streamingText, baseSize: state.settings.previewFontSize)` in a ScrollView
  (auto-scroll to bottom is a nice-to-have), instead of the selected-asset content.
- Otherwise render as today.

**Edge cases:** streaming text can be partial Markdown (unterminated `**`, half a table) — the
renderer must not crash (the AttributedString inline parser already fails soft to plain text).

**Acceptance:** drop a file → the pane fills with text as it arrives → on completion shows the
saved summary.

---

## 2. Library search + ⌘F + ⌘N (FR-041, FR-044)

**`Views/AssetBrowser/AssetBrowserView.swift`**
- Add `@State private var query = ""` and `@FocusState private var searchFocused: Bool`.
- Add a search `TextField` in the header row (magnifyingglass icon, `.textFieldStyle(.plain)`,
  clear button when non-empty), `.focused($searchFocused)`.
- Filter `visibleGroups`: keep assets whose `title` contains `query` (case-insensitive,
  diacritic-insensitive: `localizedCaseInsensitiveContains`); drop groups left empty. Empty query →
  unchanged.
- Listen for a focus request: add `@Published var focusSearch = false` on AppState toggled by ⌘F, or
  use a `NotificationCenter`/`@FocusState` binding. Simplest: an AppState `func requestSearchFocus()`
  that flips a published `searchFocusToken` the view observes via `.onChange` → sets `searchFocused = true`.

**Commands (⌘F, ⌘N):** in `App/SumbeeApp.swift` `.commands { CommandGroup(...) }`:
- `Button("Find") { state.requestSearchFocus() }.keyboardShortcut("f")`.
- `Button("New Style…") { state.requestNewStyle() }.keyboardShortcut("n")` →
  `requestNewStyle()` sets `showSettings = true` and a published `pendingNewStyle = true`;
  `StylesCRUDSection` observes it on appear and sets `creating = true` (and selects the Styles
  section — set `SettingsView`'s section via an AppState-published `settingsSection`).
- Keep existing ⌘, for Settings.

**Acceptance:** typing filters the list instantly; ⌘F focuses the field; ⌘N opens Settings ▸ Styles
in the new-style editor.

---

## 3. Drag out & Quick Look (FR-042)

**Drag-out** — `Views/AssetBrowser/AssetBrowserView.swift` (`AssetRowView`) and the preview:
- Add `.onDrag { NSItemProvider(object: asset.url as NSURL) }` to the row and to the preview body.
  This lets the user drag the actual file to Finder/Mail/Obsidian. (Drag the URL, not the text.)

**Quick Look** — spacebar on the selected summary:
- Add a small `QLPreviewPanel` bridge. Simplest robust approach: a hidden AppKit responder, OR
  `NSWorkspace`-free QL via `QLPreviewPanel.shared()`. Implement a `QuickLookController`
  (`NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate`) holding the current URL.
- Wire a `.keyboardShortcut(.space, modifiers: [])` command, or capture space in the list via an
  `NSViewRepresentable` key monitor, that toggles the panel for `state.selectedAsset?.url`.
- Acceptance: select a summary, press space → Quick Look opens; space/esc closes.

**Note:** if a clean spacebar capture proves fiddly in SwiftUI, ship drag-out first and add a
"Quick Look" toolbar button as the guaranteed path, with spacebar as the enhancement.

---

## 4. Richer preview: tables + links (FR-043)

**`Views/AssetBrowser/MarkdownPreview.swift`** (`MarkdownText`)
- **Links:** already mostly free — `AttributedString(markdown:)` parses `[text](url)`. Ensure the
  inline path keeps link attributes (use `.inlineOnlyPreservingWhitespace`) and add
  `.tint(Theme.accent)` + `.environment(\.openURL, ...)` so links are clickable. Verify `Text`
  renders the link run as tappable (SwiftUI does for AttributedString link runs).
- **Tables:** detect a GitHub table block — a header line `| a | b |`, a separator line
  `| --- | --- |`, then rows. Parse contiguous table lines into columns and render with a `Grid`
  (macOS 13+) or nested `HStack`s, scaled by `baseSize`. Keep it minimal: left-aligned cells,
  hairline dividers, header row bold. Non-table lines render as today.
- Implement by pre-scanning `lines` into "blocks" (paragraph / table) before the `ForEach`, so a
  table consumes several lines as one unit.

**Acceptance:** a summary containing a Markdown table renders as a grid; `[link](https://…)` is
clickable.

---

## 5. Per-style model/format overrides UI (FR-038)

**`Views/Settings/StylesCRUDSection.swift`** (`StyleEditorInline`)
- `SummaryStyle.modelOverride` is `ModelOverride?` with optional `model`, `outputFormat`,
  `maxOutputTokens` (confirm exact shape in `Models/SummaryStyle.swift`).
- Add a collapsible "Advanced — model & format override" disclosure under the prompt editor:
  - A toggle "Override global model/format for this style".
  - When on: a model picker (reuse `state.modelsForPicker` + "Custom…"), an output-format picker
    (Markdown/HTML), and an optional max-tokens stepper. Unset = inherit global.
- Persist via the existing `state.saveStyle(original:edited:)` path (set/clear `edited.modelOverride`).
- The engine already honors `style.modelOverride` in `finish` (model/format/maxTokens) — no engine
  change needed. Verify and keep it.

**Acceptance:** set a style to HTML + Haiku; summaries from that style use those regardless of
global settings; clearing the override reverts to global.

---

## 6. Regenerate (FR-037)

**Engine — `Services/SummarizationEngine.swift`**
- Add `func prepareFromArchive(summaryURL: URL, root: URL) throws -> PreparedInput`:
  1. Read the summary file; `FrontmatterCodec.parse` → front-matter dict. Read `source`.
  2. If `source` is a URL (`http…`): `return try await prepareYouTube(url, …)` (re-fetch). *(Or, if
     an archived transcript is discoverable, read it to avoid network — optional optimization.)*
  3. Else treat `source` as a path under `root` (e.g. `source/<name>`); resolve to an absolute URL.
     If missing, `throw RegenerateError.sourceMissing`.
  4. Extract text from the archived file via `TextExtractor` (same as `prepareFile`) but **do not
     re-archive** — reuse the existing `sourceRef`. Build `PreparedInput(transcript:, sourceRef:
     <existing>, fallbackTitle: <from archived name or summary title>, videoMeta: nil)`.
- Reuse existing `finish(prepared, style:, settings:, apiKey:, progress:)` unchanged.

**State — `State/AppState+Jobs.swift`**
- Add `func regenerate(_ asset: Asset, style: SummaryStyle, modelOverride: ...)`:
  - Build a `Job` whose input is a new case `.regenerate(summaryURL: URL)` (extend the `Job.Input`
    enum), carrying the chosen style + optional model/format overrides.
  - In `runJob`, the `.regenerate` case calls `engine.prepareFromArchive(...)` instead of
    prepare{File,YouTube}; then `finish` with the chosen style/settings (apply overrides by passing
    a tweaked `settings` copy, or via a transient `modelOverride`).
  - Result is a NEW summary (saved into the chosen style's folder). Original untouched.

**UI — `Views/AssetBrowser/MarkdownPreview.swift`**
- Add a "Regenerate" toolbar button (e.g. `arrow.triangle.2.circlepath`) → a popover/sheet with:
  - Style picker (default: the summary's current style, matched by name/`style:` front-matter).
  - Optional model picker + format picker (default: inherit).
  - "Regenerate" button → `state.regenerate(...)`.
- Disable if the source can't be located (check front-matter `source` resolves).

**Edge cases:** missing/renamed source → disable + tooltip; YouTube re-fetch needs network/yt-dlp
(surface the same errors as a normal YouTube job, via the retry queue).

**Acceptance:** select a summary → Regenerate → pick a different style/model → a new summary appears
in that style's folder; the original remains.

---

## 7. Geek mode: prompt preview + token estimate (FR-039)

**Settings:** `AppSettings.geekMode` (foundations).

**Bottom bar — `Views/BottomBar/BottomBarView.swift`**
- Add a compact toggle (terminal/`chevron.left.forwardslash.chevron.right` icon, label "Geek")
  bound to `state.settings.geekMode`; persist via `scheduleSave()` on change.

**Token estimate — new `Services/TokenEstimator.swift`**
- `static func estimate(_ text: String) -> Int { Int(ceil(Double(text.count) / 3.7)) }`. Pure,
  testable, offline. Label results with "~" in the UI.

**Prompt assembly helper — `Services/PromptBuilder.swift`**
- Add `static func assemble(style:format:htmlStylingPrompt:globalPrompt:transcript:videoMeta:) ->
  (system: String, user: String)` reusing `systemPrompt(...)` and `userMessage(...)`, so the preview
  shows exactly what the engine sends. (Engine should call the same helper to avoid drift.)

**Gate on enqueue — `State/AppState+Jobs.swift`**
- For **single-input** actions (one file in `enqueueFiles`, `enqueueYouTube`, `regenerate`) when
  `settings.geekMode`: instead of enqueuing immediately, prepare the input enough to assemble the
  prompt, then publish a `pendingPreview` (struct: system, user, est. tokens, and a continuation to
  actually enqueue). A `PromptPreview` sheet shows it with Send / Cancel.
  - For a dropped file, this means running `prepare` (extract + archive) before preview so the real
    transcript is shown. That's acceptable for single files. (Archiving before a possible Cancel is
    fine — the source archive is harmless; or defer archive until Send if you prefer.)
- For **multi-file batch** drops: skip the per-file gate (FR-039); enqueue as today.

**Sheet — new `Views/PromptPreviewSheet.swift`**
- Two sections (System / User message), monospaced, scrollable (reuse a read-only `BigPromptEditor`
  style), a header "~N input tokens (estimate) · model X", and Send / Cancel.

**Acceptance:** geek mode ON → drop one file → sheet shows the exact assembled prompt + ~token count
→ Send enqueues, Cancel discards. Geek mode OFF → unchanged. Batch drop of many files → no per-file
sheet.

---

## Tests (add to `Tests/SumbeeKitTests/`)
- `TokenEstimatorTests`: monotonic, ~chars/3.7, empty → 0.
- `PromptBuilderTests`: `assemble` returns system containing global+style+convention and user
  containing the transcript (and video meta when present).
- `AppSettingsTests`: `geekMode` round-trips and defaults to false when absent.
- Regenerate logic where unit-testable (front-matter `source` resolution → archive path vs URL),
  factored into a pure helper so it can be tested without the network.

## Verification
- `swift build` (0 warnings) + `swift test` after each group.
- Headless screenshots via the existing hooks for: streaming preview, geek-mode sheet (add a
  `SUMBEE_*` hook if useful), the style override disclosure, and the regenerate popover.

## Out of scope (keep it minimal)
Editing summaries in-app, tag/index systems, multi-provider config, a media player for Regenerate,
count-tokens API calls for the estimate (heuristic is sufficient for an inspect mode).
