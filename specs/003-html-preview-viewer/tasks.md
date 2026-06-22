# Tasks: In-app HTML preview viewer

**Input**: `spec.md`, `research.md`, `plan.md`
**Tests**: Detector is unit-tested (deterministic); the `WKWebView` view is reviewed, not unit-tested.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency)
- **[Story]**: US1 (in-app render), US2 (View-in-Browser escape), US3 (privacy/safety)

---

## Phase 1: Detection (foundational, pure logic)

- [x] T001 [P] [US2] `Services/HTMLFeatureScanner.swift` - pure `scan(_:) -> Result{hasAdvancedFeatures, features}`;
      case-insensitive triggers per research D-D; anchors never contribute.
- [x] T002 [P] [US2] `Tests/SumbeeKitTests/HTMLFeatureScannerTests.swift` - plain styled HTML →
      not advanced; script/iframe/video/canvas/form/onclick → advanced w/ correct labels;
      **anchor-only + source-link footer → not advanced**; labels deduped/stable.

## Phase 2: Viewer

- [x] T003 [US1][US3] `Views/AssetBrowser/HTMLWebView.swift` - `NSViewRepresentable` over `WKWebView`:
      JS off, `.nonPersistent()` store, `^https?://` content-rule-list block (best-effort),
      `loadHTMLString(_, baseURL: nil)`, `pageZoom` from `baseSize`, navigation delegate routes
      `.linkActivated` to `NSWorkspace` and cancels stray navigations.

## Phase 3: Integration

- [x] T004 [US1] `Views/AssetBrowser/MarkdownPreview.swift` - `PreviewPane.load()` stores raw HTML +
      `HTMLFeatureScanner` result for `.html`; `body` renders `HTMLWebView` for `.html` (non-streaming);
      Markdown path unchanged.
- [x] T005 [US2] `Views/AssetBrowser/MarkdownPreview.swift` - add the top-right, labeled
      **"View in Browser"** toolbar button, shown only when `.html` && advanced; keep font +/- enabled
      for HTML.

## Phase 4: Verify & document

- [x] T006 `swift build` clean (0 warnings) + `swift test` green (incl. new detector tests);
      confirm no new dependency in `Package.swift`.
- [x] T007 [P] Update `CHANGELOG.md` (next/Unreleased) and the `README.md` HTML-preview feature
      bullet. (Release/tag is a separate, user-initiated step.)
- [x] T008 Push branch `003-html-preview-viewer`, open PR for user validation.

---

**Checkpoint**: HTML summaries render styled in-app; advanced docs show "View in Browser"; build +
tests green; PR open.
