import Foundation

/// Ordered, flat key/value frontmatter (a deliberately small subset of YAML: `key: value`
/// pairs with optional double-quoting). Sufficient for style definitions and asset metadata.
public struct Frontmatter: Equatable {
    public private(set) var pairs: [(key: String, value: String)]

    public init(_ pairs: [(key: String, value: String)] = []) {
        self.pairs = pairs
    }

    public subscript(_ key: String) -> String? {
        get { pairs.first(where: { $0.key == key })?.value }
        set {
            if let newValue {
                if let idx = pairs.firstIndex(where: { $0.key == key }) {
                    pairs[idx].value = newValue
                } else {
                    pairs.append((key, newValue))
                }
            } else {
                pairs.removeAll { $0.key == key }
            }
        }
    }

    public func int(_ key: String) -> Int? { self[key].flatMap { Int($0) } }
    public func bool(_ key: String) -> Bool? {
        guard let v = self[key]?.lowercased() else { return nil }
        if ["true", "yes", "1"].contains(v) { return true }
        if ["false", "no", "0"].contains(v) { return false }
        return nil
    }
    public func double(_ key: String) -> Double? { self[key].flatMap { Double($0) } }

    public static func == (lhs: Frontmatter, rhs: Frontmatter) -> Bool {
        lhs.pairs.count == rhs.pairs.count &&
        zip(lhs.pairs, rhs.pairs).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }
}

/// Reads and writes documents of the form:
///
/// ```
/// ---
/// key: value
/// ---
///
/// <body>
/// ```
public enum FrontmatterCodec {
    public struct Document: Equatable {
        public var frontmatter: Frontmatter
        public var body: String
        public init(frontmatter: Frontmatter, body: String) {
            self.frontmatter = frontmatter
            self.body = body
        }
    }

    /// Parse a document. If there is no leading `---` block, the whole content is the body.
    public static func parse(_ content: String) -> Document {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        // Find the opening delimiter (first non-empty line must be "---").
        var idx = 0
        // Tolerate a leading BOM / blank lines? Require first line to be "---".
        guard idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces) == "---" else {
            return Document(frontmatter: Frontmatter(), body: content)
        }
        idx += 1

        var pairs: [(String, String)] = []
        var foundClose = false
        while idx < lines.count {
            let line = lines[idx]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                foundClose = true
                idx += 1
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip blank lines and comments inside frontmatter.
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                if let colon = line.firstIndex(of: ":") {
                    let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                    var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    value = unquote(value)
                    if !key.isEmpty { pairs.append((key, value)) }
                }
            }
            idx += 1
        }

        guard foundClose else {
            // Malformed: no closing delimiter — treat entire content as body.
            return Document(frontmatter: Frontmatter(), body: content)
        }

        // Body is everything after the closing delimiter, with one leading blank line trimmed.
        var bodyLines = Array(lines[idx...])
        if bodyLines.first == "" { bodyLines.removeFirst() }
        let body = bodyLines.joined(separator: "\n")
        return Document(frontmatter: Frontmatter(pairs), body: body)
    }

    /// Serialize a document back to the `--- … --- \n\n body` form.
    public static func serialize(_ document: Document) -> String {
        var out = "---\n"
        for (key, value) in document.frontmatter.pairs {
            out += "\(key): \(quoteIfNeeded(value))\n"
        }
        out += "---\n\n"
        out += document.body
        return out
    }

    // MARK: - Quoting

    static func quoteIfNeeded(_ value: String) -> String {
        let needsQuote = value.isEmpty
            || value.first == " " || value.last == " "
            || value.first == "\"" || value.first == "'"
            || value.contains(":") || value.contains("#")
            || value.first == "-" || value.first == "["
        if needsQuote {
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        let inner = String(value.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
