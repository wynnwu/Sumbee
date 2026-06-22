# Feature Specification: In-app HTML preview viewer

**Feature Branch**: `003-html-preview-viewer`

**Created**: 2026-06-22

**Status**: Draft

**Input**: User description: "Improve the HTML preview. It should have a basic viewer. Balance
the decision between simple and light-weight vs. having some small, nice features for a richer
interactive interface. When more advanced features are detected, put a button in the top right
to say 'View in Browser'."

## Background

Sumbee can write each summary as Markdown or as a complete, self-contained HTML document
(`<!DOCTYPE html>` … `</html>`, styling inline via the optional HTML-styling prompt; see
`001` FR-013 and `PromptBuilder.convention`). Markdown summaries get a pleasant in-app render
(`MarkdownText`). HTML summaries, however, currently degrade to a **plain-text fallback** in the
preview pane:

> "HTML summary. Use **Open** to view it styled in your browser." + tag-stripped text.

So the one format the user explicitly chose for *visual* output is the one format they cannot see
styled without leaving the app. This feature gives HTML summaries a real in-app viewer.

## Clarifications

### Session 2026-06-22

- Q: Render engine for in-app HTML? → A: **WebKit (`WKWebView`)**. It is an Apple system
  framework (no third-party dependency added; the "zero runtime deps" rule holds) and is the only
  way to render arbitrary model-authored HTML+CSS faithfully. Hand-rolling an HTML renderer or
  reusing the Markdown renderer cannot honor the document's own styling.
- Q: How "rich" should the in-app viewer be? → A: **A basic, safe, static viewer with a few small
  niceties**, not a browser. It renders the document's HTML+CSS, supports the existing font-size
  controls (as page zoom), and opens link clicks in the user's real browser. It deliberately does
  **not** run the document's JavaScript or auto-load remote resources (privacy + lightweight).
- Q: What does "more advanced features detected" mean for the "View in Browser" button? → A: The
  saved HTML contains genuinely interactive/dynamic constructs the static viewer won't execute -
  scripts, embedded frames/objects, video/audio, canvas, or form controls / inline event handlers.
  When any are present, the in-app render may be incomplete, so the app surfaces a prominent
  **"View in Browser"** button (top-right of the preview toolbar) for the full experience.
- Q: Should a plain footer link (e.g. the YouTube source URL the app stamps in) count as
  "advanced"? → A: **No.** Anchor links are normal content; they must not trip the detector
  (link clicks already open in the browser on demand). Only auto-executing/auto-loading
  constructs count.

## User Scenarios & Testing

### User Story 1 - See an HTML summary styled, in-app (Priority: P1)

A user whose default (or per-style) output format is HTML selects a summary in the library.

**Why this priority**: This is the core gap. Without it the HTML format is effectively
"export-only" inside the app.

**Acceptance**:
1. **Given** a selected `.html` summary, **when** the preview pane shows it, **then** the document
   renders with its own styling (headings, colors, layout), read-only, not as plain text.
2. **Given** the rendered HTML, **when** the user clicks a hyperlink in it, **then** the link opens
   in the user's default browser (the in-app view does not navigate away).
3. **Given** the rendered HTML, **when** the user presses the font-size +/- controls, **then** the
   content scales and the chosen size persists across sessions (shared with the Markdown preview).

### User Story 2 - Escape hatch for interactive HTML (Priority: P1)

A user selects an HTML summary whose document uses interactive features (e.g. a `<script>`-driven
collapsible outline, an embedded chart, or a `<video>`).

**Why this priority**: The lightweight viewer intentionally won't run those; the user still needs a
one-click path to the real thing. Pairs directly with US1.

**Acceptance**:
1. **Given** an HTML summary containing advanced features, **when** it is previewed, **then** a
   labeled **"View in Browser"** button is visible in the **top-right** of the preview toolbar.
2. **Given** that button, **when** the user clicks it, **then** the `.html` file opens in the
   default browser.
3. **Given** an HTML summary with **no** advanced features (plain styled prose/tables/lists),
   **when** it is previewed, **then** the "View in Browser" button is **absent** (the in-app view
   is sufficient); a plain footer source-link must not, by itself, make it appear.

### User Story 3 - Privacy & safety preserved (Priority: P2)

Sumbee's promise is local-first: the only network calls are the summarize request and YouTube
caption fetch.

**Why this priority**: Rendering arbitrary HTML must not quietly become a third network egress
(remote images, trackers, fonts) or run untrusted scripts.

**Acceptance**:
1. **Given** an HTML document that references remote resources, **when** it renders in-app, **then**
   those remote loads are blocked (nothing is auto-fetched from the network by the preview).
2. **Given** any HTML document, **when** it renders in-app, **then** its JavaScript does not run,
   and no cookies/cache are persisted to disk by the viewer.
3. The Markdown preview, library, search, regenerate, Quick Look, drag-export, and existing
   "Open"/"Reveal" actions are unchanged.

### Edge Cases

- Malformed / partial HTML → the viewer shows whatever WebKit can parse; it never crashes the app.
- Very large HTML → renders within the existing scrollable pane (WebKit scrolls internally).
- Switching rapidly between a Markdown and an HTML summary → the correct renderer is shown for the
  current selection with no stale content.
- An HTML doc that is *only* a footer source link plus styled prose → not "advanced".
- Streaming: live generation continues to stream as text (unchanged); the styled web view applies
  to the saved, selected summary. (HTML live-render is out of scope; see below.)

## Requirements

### Functional Requirements

- **FR-047**: HTML summaries MUST render with their own styling inside the preview pane (a basic,
  read-only in-app viewer), replacing the previous plain-text fallback.
- **FR-048**: The in-app viewer MUST be static and private: it MUST NOT execute the document's
  JavaScript, MUST block remote network resource loads, and MUST NOT persist cookies/cache to disk.
  Hyperlink clicks MUST open in the user's default browser rather than navigating the in-app view.
- **FR-049**: The existing preview font-size controls MUST scale the HTML render (via page zoom),
  reusing and persisting the same `previewFontSize` setting as the Markdown preview.
- **FR-050**: The app MUST detect "advanced" features in a saved HTML summary - scripts, embedded
  frames/objects (`iframe`/`embed`/`object`), media (`video`/`audio`), `canvas`, and form controls
  / inline event handlers - via a deterministic, unit-tested scan. Plain anchor links MUST NOT be
  treated as advanced.
- **FR-051**: When advanced features are detected, a labeled **"View in Browser"** button MUST
  appear in the top-right of the preview toolbar and open the `.html` file in the default browser.
  When none are detected, the button MUST be absent.
- **FR-052**: No new third-party runtime dependency may be introduced (WebKit is an Apple system
  framework). The Markdown path and all other preview actions MUST be unaffected.

### Out of scope (this feature)

- Live, styled HTML rendering *during* streaming generation (still streams as text).
- Editing HTML in-app, printing, or an in-app "reader mode" reflow.
- A user setting to opt back into JavaScript / remote loads inside the app (browser is the path
  for that).

## Success Criteria

- **SC-001**: Selecting an HTML summary shows it styled in-app (no plain-text fallback) for 100% of
  well-formed model-authored HTML.
- **SC-002**: For HTML containing any advanced construct, the "View in Browser" button appears and
  opens the file in the browser; for plain styled HTML it does not appear. Verified by unit tests
  over the detector and by manual validation of the toolbar.
- **SC-003**: `swift build` is clean (0 warnings) and `swift test` is green, including new detector
  tests. No new SPM dependency in `Package.swift`.
- **SC-004**: No regression in the Markdown preview or other library actions.
