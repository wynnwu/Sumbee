import Foundation

/// Embeds asset metadata into an HTML document as `<meta name="…">` tags in `<head>`
/// (plus a leading comment), since YAML frontmatter would render as visible text (spec §8.2).
public enum HTMLMetaCodec {
    public static func embed(_ pairs: [(key: String, value: String)], into html: String) -> String {
        let metaTags = pairs.map { "    <meta name=\"\($0.key)\" content=\"\(escape($0.value))\">" }
            .joined(separator: "\n")
        let comment = "<!-- summarizer-metadata\n"
            + pairs.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
            + "\n-->\n"

        // Insert meta tags right after the opening <head ...> if present.
        if let headRange = html.range(of: "<head", options: .caseInsensitive),
           let headClose = html.range(of: ">", range: headRange.upperBound..<html.endIndex) {
            var result = html
            result.insert(contentsOf: "\n" + metaTags, at: headClose.upperBound)
            return comment + result
        }

        // Otherwise, inject a <head> right after <html ...> if present.
        if let htmlRange = html.range(of: "<html", options: .caseInsensitive),
           let htmlClose = html.range(of: ">", range: htmlRange.upperBound..<html.endIndex) {
            var result = html
            result.insert(contentsOf: "\n<head>\n\(metaTags)\n</head>", at: htmlClose.upperBound)
            return comment + result
        }

        // Fallback: just prepend the comment block.
        return comment + html
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Insert a small, centered, grey, underlined source link just before the closing `</body>`
    /// (or append it if there's no body tag). Used to stamp the original YouTube URL into the
    /// HTML programmatically, so the link never travels through the model.
    public static func insertSourceLink(_ url: String, into html: String) -> String {
        let safe = escape(url)
        let snippet = "\n<p style=\"text-align:center;margin:2.5em 0 1em\">"
            + "<a href=\"\(safe)\" style=\"color:#888;font-size:0.85em;text-decoration:underline\">\(safe)</a></p>\n"
        if let r = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            var result = html
            result.insert(contentsOf: snippet, at: r.lowerBound)
            return result
        }
        return html + snippet
    }

    /// Read back a `<meta name="…" content="…">` value embedded by `embed` (FR-037 regenerate).
    public static func readMeta(_ html: String, name: String) -> String? {
        guard let nameRange = html.range(of: "name=\"\(name)\"") else { return nil }
        guard let contentOpen = html.range(of: "content=\"",
                                           range: nameRange.upperBound..<html.endIndex) else { return nil }
        guard let contentClose = html.range(of: "\"",
                                            range: contentOpen.upperBound..<html.endIndex) else { return nil }
        return decode(String(html[contentOpen.upperBound..<contentClose.lowerBound]))
    }

    /// Reverse of `escape`: decode the four entities (`&amp;` LAST to avoid double-decoding).
    public static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&amp;", with: "&")
    }
}
