import Foundation

/// Detects "advanced" constructs in a saved HTML summary that the in-app, static, JavaScript-free
/// preview won't execute (FR-050). When any are present, the UI offers a "View in Browser" escape
/// hatch (FR-051) so the user gets the full experience in their real browser.
///
/// The scan is intentionally a cheap, case-insensitive text match on the raw document, not a full
/// HTML parse: deciding "is there a `<script>`/`<iframe>`/…" does not require a DOM. Plain anchor
/// links (`<a href>`) are normal content and never count - notably the centered grey source link
/// the app stamps into YouTube HTML (`HTMLMetaCodec.insertSourceLink`) must not trip the detector.
public enum HTMLFeatureScanner {
    public struct Result: Equatable {
        /// True when at least one advanced construct was found.
        public let hasAdvancedFeatures: Bool
        /// Friendly, deduped, stable-ordered labels (e.g. ["JavaScript", "Media"]) for tooltips.
        public let features: [String]

        public init(hasAdvancedFeatures: Bool, features: [String]) {
            self.hasAdvancedFeatures = hasAdvancedFeatures
            self.features = features
        }
    }

    /// One detectable category: a friendly label plus the lowercased tokens that imply it.
    private struct Category {
        let label: String
        let tokens: [String]
    }

    // Order here is the stable order of `features` in the result.
    private static let categories: [Category] = [
        Category(label: "JavaScript", tokens: ["<script"]),
        Category(label: "Embedded content", tokens: ["<iframe", "<embed", "<object"]),
        Category(label: "Media", tokens: ["<video", "<audio"]),
        Category(label: "Graphics", tokens: ["<canvas"]),
        Category(label: "Interactive controls",
                 tokens: ["<form", "<input", "<button", "<select", "<textarea"]),
    ]

    /// Matches an inline event handler attribute (`onclick=`, `onload=`, …). The leading boundary
    /// (whitespace, quote, or `<`/tag char) keeps it from matching words that merely contain "on".
    private static let eventHandler = try! NSRegularExpression(
        pattern: "[\\s\"'/]on[a-z]+\\s*=", options: [.caseInsensitive])

    public static func scan(_ html: String) -> Result {
        let lower = html.lowercased()
        var found: [String] = []

        for category in categories where category.tokens.contains(where: { lower.contains($0) }) {
            found.append(category.label)
        }

        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        if eventHandler.firstMatch(in: lower, options: [], range: range) != nil {
            found.append("Scripted handlers")
        }

        return Result(hasAdvancedFeatures: !found.isEmpty, features: found)
    }
}
