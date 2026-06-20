import Foundation

public enum StyleStoreError: Error, CustomStringConvertible {
    case folderExists(String)
    case writeFailed(String)
    public var description: String {
        switch self {
        case .folderExists(let n): return "A style folder named “\(n)” already exists."
        case .writeFailed(let m): return m
        }
    }
}

/// Reads/writes style definitions on disk. The library is the source of truth (spec §8.5).
public protocol StyleStoring: Sendable {
    func loadStyles(root: URL) throws -> [SummaryStyle]
    func create(_ style: SummaryStyle, root: URL) throws
    func update(_ style: SummaryStyle, root: URL) throws
    func rename(_ style: SummaryStyle, to newName: String, root: URL) throws
    func delete(_ style: SummaryStyle, root: URL) throws
    func seedDefaults(root: URL) throws
}

public struct StyleStore: StyleStoring {
    static let defFolder = "style-definition"
    static let defFile = "style-definition.md"
    public static let sourceFolderName = "source"

    private var fm: FileManager { .default }
    public init() {}

    // MARK: Paths

    func styleFolder(root: URL, name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }
    func definitionURL(root: URL, name: String) -> URL {
        styleFolder(root: root, name: name)
            .appendingPathComponent(Self.defFolder, isDirectory: true)
            .appendingPathComponent(Self.defFile)
    }
    /// Whether a folder is a style (contains a style definition).
    public static func isStyleFolder(_ folder: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(defFolder).appendingPathComponent(defFile).path)
    }

    // MARK: Load

    public func loadStyles(root: URL) throws -> [SummaryStyle] {
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }

        var styles: [SummaryStyle] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            if entry.lastPathComponent == Self.sourceFolderName { continue }
            guard Self.isStyleFolder(entry) else { continue }
            if let style = try? parse(folder: entry, root: root) {
                styles.append(style)
            }
        }
        return styles.sorted { $0.order < $1.order }
    }

    private func parse(folder: URL, root: URL) throws -> SummaryStyle {
        let name = folder.lastPathComponent
        let url = definitionURL(root: root, name: name)
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let doc = FrontmatterCodec.parse(content)
        let fm = doc.frontmatter

        let id = fm["id"].flatMap(UUID.init(uuidString:)) ?? UUID()
        let channel = StyleChannel(rawValue: fm["channel"] ?? "file") ?? .file
        let order = fm.int("order") ?? 0
        let enabled = fm.bool("enabled") ?? true

        let ov = ModelOverride(
            model: fm["model"],
            temperature: fm.double("temperature"),
            effort: fm["effort"],
            maxOutputTokens: fm.int("maxOutputTokens"),
            outputFormat: fm["format"].flatMap(OutputFormat.init(rawValue:))
        )
        let resolvedOverride: ModelOverride? = ov.isEmpty ? nil : ov

        return SummaryStyle(id: id, name: name, channel: channel,
                            prompt: doc.body.trimmingCharacters(in: .whitespacesAndNewlines),
                            order: order, enabled: enabled, modelOverride: resolvedOverride)
    }

    // MARK: Write

    private func definitionDocument(for style: SummaryStyle) -> String {
        var fmatter = Frontmatter()
        fmatter["id"] = style.id.uuidString
        fmatter["channel"] = style.channel.rawValue
        fmatter["order"] = String(style.order)
        fmatter["enabled"] = style.enabled ? "true" : "false"
        if let o = style.modelOverride {
            if let m = o.model { fmatter["model"] = m }
            if let t = o.temperature { fmatter["temperature"] = String(t) }
            if let e = o.effort { fmatter["effort"] = e }
            if let mt = o.maxOutputTokens { fmatter["maxOutputTokens"] = String(mt) }
            if let f = o.outputFormat { fmatter["format"] = f.rawValue }
        }
        return FrontmatterCodec.serialize(.init(frontmatter: fmatter, body: style.prompt))
    }

    private func writeDefinition(_ style: SummaryStyle, root: URL) throws {
        let defDir = styleFolder(root: root, name: style.name)
            .appendingPathComponent(Self.defFolder, isDirectory: true)
        do {
            try fm.createDirectory(at: defDir, withIntermediateDirectories: true)
            let url = defDir.appendingPathComponent(Self.defFile)
            try definitionDocument(for: style).data(using: .utf8)!.write(to: url, options: .atomic)
        } catch {
            throw StyleStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func create(_ style: SummaryStyle, root: URL) throws {
        let folder = styleFolder(root: root, name: style.name)
        if Self.isStyleFolder(folder) { throw StyleStoreError.folderExists(style.name) }
        try writeDefinition(style, root: root)
    }

    public func update(_ style: SummaryStyle, root: URL) throws {
        try writeDefinition(style, root: root)
    }

    public func rename(_ style: SummaryStyle, to newName: String, root: URL) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != style.name else { return }
        let from = styleFolder(root: root, name: style.name)
        let to = styleFolder(root: root, name: trimmed)
        if fm.fileExists(atPath: to.path) { throw StyleStoreError.folderExists(trimmed) }
        do {
            try fm.moveItem(at: from, to: to)
        } catch {
            throw StyleStoreError.writeFailed(error.localizedDescription)
        }
        // Definition body/metadata are name-independent; nothing else to rewrite.
    }

    public func delete(_ style: SummaryStyle, root: URL) throws {
        // Remove only the definition folder; keep the style folder and its assets.
        let defDir = styleFolder(root: root, name: style.name)
            .appendingPathComponent(Self.defFolder, isDirectory: true)
        if fm.fileExists(atPath: defDir.path) {
            try fm.removeItem(at: defDir)
        }
    }

    public func seedDefaults(root: URL) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for style in DefaultStyles.make() {
            let folder = styleFolder(root: root, name: style.name)
            if Self.isStyleFolder(folder) { continue }
            try writeDefinition(style, root: root)
        }
    }
}
