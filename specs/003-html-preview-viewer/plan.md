# Implementation Plan: In-app HTML preview viewer

**Spec**: `spec.md`  ·  **Decisions**: `research.md`  ·  **Tasks**: `tasks.md`

## Summary

Replace the plain-text HTML fallback in the preview pane with a basic, static, private `WKWebView`
viewer, add a deterministic advanced-feature scan, and surface a top-right **"View in Browser"**
button when advanced features are present. No new dependency (WebKit is an Apple framework).

## Architecture & touch points

```
Sources/SumbeeKit/
  Services/
    HTMLFeatureScanner.swift        # NEW  pure, testable: scan(html) -> Result{advanced, labels}
  Views/AssetBrowser/
    HTMLWebView.swift               # NEW  NSViewRepresentable around WKWebView (JS off, no remote,
                                    #      nonPersistent store, link clicks -> browser, pageZoom)
    MarkdownPreview.swift           # EDIT PreviewPane: branch .html -> HTMLWebView; toolbar gains a
                                    #      conditional top-right "View in Browser" button
Tests/SumbeeKitTests/
    HTMLFeatureScannerTests.swift   # NEW  detector unit tests incl. anchor-link false-positive guard
```

Everything else (AppState, LibraryStore, Asset model, streaming, settings) is untouched. The
viewer reads the file the same way `load()` already does.

## Component contracts

### `HTMLFeatureScanner` (Services)

```swift
public enum HTMLFeatureScanner {
    public struct Result: Equatable {
        public let hasAdvancedFeatures: Bool
        public let features: [String]      // friendly labels, deduped, stable order
    }
    public static func scan(_ html: String) -> Result
}
```

- Pure, synchronous, no I/O. Case-insensitive. Anchor `<a>` never contributes.
- `features` drives the button's help/tooltip text; `hasAdvancedFeatures == !features.isEmpty`.

### `HTMLWebView` (Views)

```swift
struct HTMLWebView: NSViewRepresentable {   // NSViewRepresentable
    let html: String
    var baseSize: Double                      // -> pageZoom = clamp(baseSize/16, 0.6...2.0)
}
```

- `makeNSView`: build `WKWebViewConfiguration` (JS off, `.nonPersistent()` store), attach the
  cached/compiled `WKContentRuleList` blocking `^https?://` (best-effort), set `navigationDelegate`,
  `loadHTMLString(html, baseURL: nil)`.
- `updateNSView`: apply `pageZoom`; reload only if `html` changed.
- `Coordinator: WKNavigationDelegate`: allow the first programmatic load; `.linkActivated` →
  `NSWorkspace.shared.open(url)` + `.cancel`; any later main-frame navigation → `.cancel`.

### `PreviewPane` (edits)

- `load()`: for `.html`, store the **raw** file text (for the web view) and compute
  `HTMLFeatureScanner.scan(...)`; for `.markdown`, unchanged.
- `body`: when `asset.format == .html` and not streaming, show `HTMLWebView(html:baseSize:)` inside
  the existing scroll area instead of `MarkdownText`. Markdown path unchanged.
- `toolbar`: after the title `Spacer()`, add a labeled "View in Browser" button **only** when
  `asset.format == .html && htmlFeatures.hasAdvancedFeatures`. Existing icon buttons remain.
- Font +/- buttons stay enabled for HTML (they now drive `pageZoom`).

## Security / privacy checklist (maps to FR-048 / US3)

- [ ] `allowsContentJavaScript = false`
- [ ] `websiteDataStore = .nonPersistent()`
- [ ] content rule list blocks `^https?://` (best-effort, scoped so the local doc never matches)
- [ ] link clicks + stray navigations cancelled; links open via `NSWorkspace`
- [ ] `baseURL: nil` (no implicit relative/remote resolution)

## Testing

- **Unit (added)**: `HTMLFeatureScannerTests` - plain styled HTML → not advanced; `<script>`,
  `<iframe>`, `<video>`, `<canvas>`, `<form>`/`<input>`, inline `onclick` → advanced with the right
  labels; **anchor-only / source-link footer → not advanced** (false-positive guard); labels are
  deduped/stable.
- **Build/verify**: `swift build` (0 warnings), `swift test` (all green). No app launch (Keychain;
  learnings #3/#4) - user validates render from the PR build.
- The `WKWebView` wiring is not unit-tested (UI/system view); it is kept small and reviewed against
  `research.md` D-B.

## Risks & mitigations

- *No local visual check*: detector is fully unit-tested; web-view code minimized and documented.
- *Content rule list*: scoped to `http(s)`, compile failure is non-fatal (JS-off remains).
- *Dark mode*: model HTML carries its own background; a light document on a dark app is expected
  (same as Quick Look / a browser). Not forced.

## Rollback

Self-contained: deleting `HTMLWebView.swift` + `HTMLFeatureScanner.swift` and reverting the
`MarkdownPreview.swift` edit restores the plain-text fallback. No persistence/format changes.

## Docs to update on completion

- `CHANGELOG.md` (Unreleased / next version - release is a separate, user-initiated step).
- `README.md` features bullet for HTML preview (the Markdown-preview bullet currently implies HTML
  is browser-only).
- `specs/003-html-preview-viewer/*` kept current (this set).
