import Foundation

/// A generated summary on disk plus light metadata derived from its path/frontmatter.
public struct Asset: Identifiable, Equatable, Hashable, Sendable {
    public var id: URL { url }
    public var url: URL
    public var title: String
    public var styleName: String
    public var created: Date?
    /// Archived source path (relative to library root) or a YouTube URL.
    public var sourceRef: String?
    public var format: OutputFormat

    public init(url: URL,
                title: String,
                styleName: String,
                created: Date? = nil,
                sourceRef: String? = nil,
                format: OutputFormat) {
        self.url = url
        self.title = title
        self.styleName = styleName
        self.created = created
        self.sourceRef = sourceRef
        self.format = format
    }
}

/// A folder of assets for one style, plus the style itself when present.
public struct StyleGroup: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var folderURL: URL
    public var assets: [Asset]
    /// True for the special `source/` archive folder (not a real style).
    public var isSourceFolder: Bool

    public init(name: String, folderURL: URL, assets: [Asset], isSourceFolder: Bool = false) {
        self.name = name
        self.folderURL = folderURL
        self.assets = assets
        self.isSourceFolder = isSourceFolder
    }
}

/// The scanned library: discovered styles and the asset groups (style folders + source).
public struct Library: Equatable, Sendable {
    public var styles: [SummaryStyle]
    public var groups: [StyleGroup]

    public init(styles: [SummaryStyle] = [], groups: [StyleGroup] = []) {
        self.styles = styles
        self.groups = groups
    }

    public static let empty = Library()
}
