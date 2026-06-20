import Foundation
import UniformTypeIdentifiers

public enum ExtractionError: Error, Equatable {
    case unsupported(String)
    case noText
    case readFailed(String)

    public var userMessage: String {
        switch self {
        case .unsupported(let ext): return "Unsupported file type: .\(ext)"
        case .noText: return "No extractable text found (is this a scanned/image-only file?)."
        case .readFailed(let m): return "Couldn’t read the file: \(m)"
        }
    }
}

/// Extracts plain text from one supported input file.
protocol FileTextExtractor {
    func extract(from url: URL) throws -> String
}

/// Dispatches extraction by file extension to the right native extractor.
public struct TextExtractor {
    public static let supportedExtensions: Set<String> = ["txt", "md", "markdown", "pdf", "docx", "rtf"]

    private let plain = PlainTextExtractor()
    private let pdf = PDFExtractor()
    private let rtf = RTFExtractor()
    private let docx = DocxExtractor()

    public init() {}

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Returns trimmed extracted text, or throws `ExtractionError.noText` if empty.
    public func extract(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let extractor: FileTextExtractor
        switch ext {
        case "txt", "md", "markdown": extractor = plain
        case "pdf": extractor = pdf
        case "rtf": extractor = rtf
        case "docx": extractor = docx
        default: throw ExtractionError.unsupported(ext)
        }
        let text = try extractor.extract(from: url)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExtractionError.noText }
        return trimmed
    }
}
