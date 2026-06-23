# Research & Decisions: In-app HTML preview viewer

Decisions are lettered `D-A…` to stay distinct from `001`'s `D1–D16`.

## D-A. Render engine: `WKWebView` (WebKit)

- **Decision**: Render the saved HTML in a `WKWebView` wrapped as an `NSViewRepresentable`.
- **Alternatives rejected**:
  - *Reuse `MarkdownText`*: cannot honor the document's own CSS; the whole point of HTML output is
    custom styling.
  - *`NSAttributedString(html:)`*: lossy and slow for full documents; ignores most CSS; deprecated
    threading caveats. Not faithful.
  - *Hand-rolled HTML→SwiftUI renderer*: large surface, perpetual fidelity gap, not "lightweight".
- **Dependency note**: WebKit is an Apple **system framework** (`import WebKit`), linked
  automatically. This does **not** violate the "zero third-party runtime deps" rule (it is the same
  category as AppKit / PDFKit / Quartz already used).

## D-B. Static & private by default (the "basic viewer" posture)

The viewer is deliberately *not* a browser. Three guards, each cheap:

1. **JavaScript off** - `configuration.defaultWebpagePreferences.allowsContentJavaScript = false`.
   The static styled document renders; scripts simply don't run. This is what makes the in-app view
   "basic" and is why script-bearing docs get the "View in Browser" escape (D-E).
2. **No remote network egress** - a `WKContentRuleList` blocking `^https?://` loads, so remote
   images/fonts/trackers are not auto-fetched. Scoped to `http(s)` only, so the in-memory document
   (`about:blank` / `data:`) is never matched and never blanked. Best-effort: if the rule list fails
   to compile, the viewer still renders (JS is still off). Honors the local-first promise (`001`).
3. **No on-disk state** - `configuration.websiteDataStore = .nonPersistent()` (no cookies/cache).

Link clicks are routed out: the `WKNavigationDelegate` cancels `.linkActivated` navigations and
hands the URL to `NSWorkspace.shared.open`, and cancels any other main-frame navigation after the
initial programmatic load. So the pane only ever shows the one summary.

**Main-thread loading (and the gate).** Every `WKWebView`/`WKUserContentController` mutation,
`loadHTMLString` included, runs on the main thread. The async rule-list compile completion is **not
guaranteed** to be on main, so it hops via `DispatchQueue.main.async` before installing the rule and
resuming the (gated) first load. The first paint stays gated behind rule installation so a document
is never shown before remote loads are blocked. (A first cut loaded from the off-main compile
completion and rendered the first document blank; a naive "load eagerly, ungated" fix then
reintroduced a remote-load privacy hole. See learnings #18.)

- **Load method**: `loadHTMLString(html, baseURL: nil)`. Keeping `baseURL` nil means relative paths
  don't resolve - acceptable because model output is self-contained, and it reinforces "no remote
  fetch by surprise". (In-document `#anchor` jumps may be inert; minor, acceptable for a basic
  viewer.)

## D-C. Zoom reuses the existing `previewFontSize`

`WKWebView.pageZoom` maps cleanly from the existing preview base size: `zoom = baseSize / 16`,
clamped to `[0.6, 2.0]`. The existing toolbar +/- buttons therefore work for HTML with no new
setting and the size persists exactly as it does for Markdown (`001` FR-036).

## D-D. Advanced-feature detection - a deterministic, testable scan

A pure function `HTMLFeatureScanner.scan(_:) -> Result` flags constructs the static viewer won't
execute, grouped into friendly labels for tooltips:

| Label                | Triggers (case-insensitive)                                  |
|----------------------|--------------------------------------------------------------|
| JavaScript           | `<script`                                                    |
| Embedded content     | `<iframe`, `<embed`, `<object`                               |
| Media                | `<video`, `<audio`                                           |
| Graphics             | `<canvas`                                                    |
| Interactive controls | `<form`, `<input`, `<button`, `<select`, `<textarea`         |
| Scripted handlers    | inline `on<event>=` attributes (regex ` on[a-z]+\s*=`)       |

- **False-positive guard (the key correctness point)**: plain `<a href="…">` anchor links - notably
  the centered grey **source link** the app stamps into YouTube HTML (`HTMLMetaCodec.insertSourceLink`)
  - MUST NOT trigger detection. Anchors are normal content and are handled by link-routing (D-B).
  This is asserted directly in tests.
- **Robustness**: substring/regex matching on the raw text is sufficient and cheap; we do not need a
  full HTML parser to decide "is there a `<script>`". `<details>`/`<summary>` (native, JS-free) are
  intentionally **not** flagged.

## D-E. "View in Browser" affordance

- Shown only for `.html` assets where `HTMLFeatureScanner` reports advanced features, as a **labeled**
  button (globe icon + "View in Browser") at the **top-right** of the preview toolbar (per the
  explicit request). It calls the same open path as the existing "Open" action
  (`NSWorkspace.shared.open(asset.url)`).
- The existing generic Open / Quick Look / Reveal actions remain for both formats; the new button is
  an additional, prominent, conditional escape hatch.

## D-F. Streaming unchanged

Live generation keeps streaming as text into the pane (existing behavior). Re-loading a `WKWebView`
per streamed token is wasteful and flickery; the styled web view applies to the finished, selected
summary. Noted as out of scope in the spec.

## Risks

- **Cannot launch locally to eyeball** (ad-hoc signing → Keychain prompt; see learnings #3/#4). We
  verify via `swift build` + `swift test` (detector is fully unit-tested) and a careful read of the
  WebKit wiring; the user validates the rendered output from the PR build.
- **Content-rule-list scope**: limited strictly to `^https?://` so it cannot blank the local
  document; failure to compile is non-fatal (JS-off still holds).
