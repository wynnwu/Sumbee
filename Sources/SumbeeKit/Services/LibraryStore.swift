import Foundation

/// Scans the library root into the styles + asset groups the UI renders.
public protocol LibraryStoring: Sendable {
    func scan(root: URL) throws -> Library
    func assets(in folder: URL, styleName: String) -> [Asset]
}

public struct LibraryStore: LibraryStoring {
    private var fm: FileManager { .default }
    private let styleStore = StyleStore()
    public init() {}

    public func scan(root: URL) throws -> Library {
        let styles = (try? styleStore.loadStyles(root: root)) ?? []

        var groups: [StyleGroup] = []
        let entries = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let name = entry.lastPathComponent
            let isSource = (name == StyleStore.sourceFolderName)
            // A folder is listed if it's a style or the source archive.
            guard isSource || StyleStore.isStyleFolder(entry) else { continue }
            let items = assets(in: entry, styleName: name)
            groups.append(StyleGroup(name: name, folderURL: entry, assets: items, isSourceFolder: isSource))
        }

        // Order: styles by their style order, source last.
        let styleOrder = Dictionary(uniqueKeysWithValues: styles.map { ($0.name, $0.order) })
        groups.sort { a, b in
            if a.isSourceFolder != b.isSourceFolder { return !a.isSourceFolder }
            let oa = styleOrder[a.name] ?? Int.max
            let ob = styleOrder[b.name] ?? Int.max
            if oa != ob { return oa < ob }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return Library(styles: styles, groups: groups)
    }

    public func assets(in folder: URL, styleName: String) -> [Asset] {
        let entries = (try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []

        var assets: [Asset] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }                       // skip style-definition/ etc.
            let ext = url.pathExtension.lowercased()
            let isSource = (styleName == StyleStore.sourceFolderName)
            if !isSource && !(ext == "md" || ext == "html") { continue }
            assets.append(makeAsset(url: url, styleName: styleName))
        }

        assets.sort { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        return assets
    }

    private func makeAsset(url: URL, styleName: String) -> Asset {
        let ext = url.pathExtension.lowercased()
        let format: OutputFormat = (ext == "html") ? .html : .markdown
        let filename = url.deletingPathExtension().lastPathComponent

        var title: String
        var created: Date?
        if let (date, rest) = Self.archivePrefix(filename) {
            // Datetime-prefixed archived source: "yyyy-MM-dd_HHmmss__name" (FR-026).
            title = rest
            created = date
        } else {
            title = filenameTitle(filename)
            created = Self.dateFromFilename(filename)
        }
        var source: String?

        if ext == "md", let content = try? String(contentsOf: url, encoding: .utf8) {
            let doc = FrontmatterCodec.parse(content)
            if let t = doc.frontmatter["title"], !t.isEmpty { title = t }
            if let c = doc.frontmatter["created"], let d = Self.iso.date(from: c) { created = d }
            source = doc.frontmatter["source"]
        } else if ext == "html", let content = try? String(contentsOf: url, encoding: .utf8) {
            if let t = Self.htmlMeta(content, name: "title") { title = t }
            if let c = Self.htmlMeta(content, name: "created"), let d = Self.iso.date(from: c) { created = d }
            source = Self.htmlMeta(content, name: "source")
        }

        if created == nil {
            created = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }

        return Asset(url: url, title: title, styleName: styleName,
                     created: created, sourceRef: source, format: format)
    }

    /// Strip a leading "YYYY-MM-DD HHmm — " prefix for a friendlier display title.
    private func filenameTitle(_ filename: String) -> String {
        if let range = filename.range(of: "— ") {
            let after = String(filename[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { return after }
        }
        return filename
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse a datetime-prefixed archived-source filename: "yyyy-MM-dd_HHmmss__name".
    static func archivePrefix(_ filename: String) -> (Date, String)? {
        guard let r = filename.range(of: "__") else { return nil }
        let prefix = String(filename[..<r.lowerBound])
        let rest = String(filename[r.upperBound...])
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        guard let date = f.date(from: prefix) else { return nil }
        return (date, rest.isEmpty ? filename : rest)
    }

    static func dateFromFilename(_ filename: String) -> Date? {
        // Expect prefix "YYYY-MM-DD HHmm"
        let parts = filename.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let candidate = "\(parts[0]) \(parts[1])"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f.date(from: candidate)
    }

    static func htmlMeta(_ html: String, name: String) -> String? {
        // Find <meta name="<name>" content="...">
        guard let nameRange = html.range(of: "name=\"\(name)\"", options: .caseInsensitive) else { return nil }
        guard let contentRange = html.range(of: "content=\"", range: nameRange.upperBound..<html.endIndex),
              let endQuote = html.range(of: "\"", range: contentRange.upperBound..<html.endIndex) else {
            return nil
        }
        // Reverse the HTML-entity escaping applied by HTMLMetaCodec.embed on write.
        return HTMLMetaCodec.decode(String(html[contentRange.upperBound..<endQuote.lowerBound]))
    }
}
