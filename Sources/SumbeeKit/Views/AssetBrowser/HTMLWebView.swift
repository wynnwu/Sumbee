import SwiftUI
import WebKit
import AppKit

/// A basic, read-only, *static* in-app viewer for an HTML summary (FR-047).
///
/// It renders the model's self-contained HTML with its own styling, but deliberately is **not** a
/// browser (FR-048): JavaScript is disabled, remote network loads are blocked, nothing is persisted
/// to disk, and link clicks open in the user's real browser. Documents that need more (scripts,
/// embeds, media, forms) are flagged by `HTMLFeatureScanner` so the UI can offer "View in Browser".
///
/// Threading note (this was a real "first HTML renders blank" bug): every `WKWebView` /
/// `WKUserContentController` mutation, `loadHTMLString` included, MUST happen on the main thread. The
/// remote-load rule list compiles asynchronously and its completion handler is not guaranteed to run
/// on main, so we hop to main before installing the rule and issuing the load. The load stays gated
/// behind rule installation, so the document is never painted before the remote-load block is active.
struct HTMLWebView: NSViewRepresentable {
    let html: String
    /// The preview toolbar's base font size; mapped to page zoom (16pt == 1.0). (FR-049)
    var baseSize: Double

    private var zoom: CGFloat { max(0.6, min(2.0, CGFloat(baseSize / 16.0))) }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        // Keep a strong reference to the content controller we create: `WKWebView.configuration`
        // returns a *copy*, so a rule list added to it post-init wouldn't reach the live view.
        let controller = WKUserContentController()

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .nonPersistent()                        // no cookies/cache on disk
        config.defaultWebpagePreferences.allowsContentJavaScript = false  // static, JS-free render

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.pageZoom = zoom

        context.coordinator.controller = controller
        context.coordinator.render(html, on: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoom
        context.coordinator.render(html, on: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var currentHTML = ""
        private var loadedHTML: String?
        var controller: WKUserContentController?
        private var didInitialLoad = false
        private var ruleState: RuleState = .pending

        private enum RuleState { case pending, installing, ready }

        /// Record the latest requested document and, once the remote-load block is installed on this
        /// controller, load it. The load is always issued on the main thread (callers are the SwiftUI
        /// make/update cycle; the install completion hops to main), which fixes the blank-first-render
        /// bug, and stays gated behind installation so nothing paints before remote loads are blocked.
        func render(_ html: String, on webView: WKWebView) {
            currentHTML = html
            switch ruleState {
            case .ready:
                loadIfNeeded(into: webView)
            case .installing:
                break                                   // the install completion loads the latest doc
            case .pending:
                ruleState = .installing
                guard let controller else { ruleState = .ready; loadIfNeeded(into: webView); return }
                RemoteResourceBlock.install(on: controller) { [weak self, weak webView] in
                    guard let self, let webView else { return }   // always invoked on the main thread
                    self.ruleState = .ready
                    self.loadIfNeeded(into: webView)
                }
            }
        }

        /// Load the current document once per distinct, non-empty value: skips the transient "" that
        /// appears while the file is read, and avoids reloading the same doc on a zoom change.
        private func loadIfNeeded(into webView: WKWebView) {
            let html = currentHTML
            guard !html.isEmpty, html != loadedHTML else { return }
            loadedHTML = html
            didInitialLoad = false
            // baseURL nil: model HTML is self-contained; no surprise relative/remote resolution.
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // A clicked hyperlink opens in the user's browser; the in-app pane never navigates away.
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url,
                   let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" || scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)                // (in-doc about:blank#anchor clicks just no-op)
                return
            }
            // Allow exactly the first programmatic document load; cancel any later navigation.
            if didInitialLoad {
                decisionHandler(.cancel)
            } else {
                didInitialLoad = true
                decisionHandler(.allow)
            }
        }
    }
}

/// Best-effort `WKContentRuleList` that blocks remote (`http`/`https`) loads so the static preview
/// never auto-fetches remote images/fonts/trackers (FR-048, privacy). The filter is scoped to
/// `http(s)` so the in-memory document (`about:blank`/`data:`) is never matched and never blanked.
/// JavaScript is disabled regardless, so a compile failure degrades safely. Compiled once, cached.
///
/// All state here is read/written on the main thread only: `install` is called from the SwiftUI
/// make/update cycle, and the (possibly off-main) compile completion hops to main before touching
/// `cached` or the controller. `completion` is therefore always invoked on the main thread.
private enum RemoteResourceBlock {
    private static let identifier = "sumbee.preview.block-remote.v1"
    private static let encodedRules =
        #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
    private static var cached: WKContentRuleList?

    static func install(on controller: WKUserContentController, completion: @escaping () -> Void) {
        if let cached {
            controller.add(cached)
            completion()
            return
        }
        guard let store = WKContentRuleListStore.default() else { completion(); return }
        store.compileContentRuleList(forIdentifier: identifier,
                                     encodedContentRuleList: encodedRules) { [weak controller] list, _ in
            // The compile completion thread is not guaranteed to be main; hop before any WebKit
            // mutation or the gated content load. This is the core fix for the blank-first-render bug.
            DispatchQueue.main.async {
                if let list {
                    cached = list
                    controller?.add(list)
                }
                completion()   // best-effort: render even if the rule list failed to compile
            }
        }
    }
}
