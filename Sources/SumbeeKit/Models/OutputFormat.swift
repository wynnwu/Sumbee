import Foundation

/// How a summary is written to disk.
public enum OutputFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case markdown
    case html

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        }
    }

    public var displayName: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .html: return "HTML (.html)"
        }
    }
}
