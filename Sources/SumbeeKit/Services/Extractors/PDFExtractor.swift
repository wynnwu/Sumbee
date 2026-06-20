import Foundation
import PDFKit

/// `.pdf` — text layer via PDFKit. Image-only/scanned PDFs yield no text → `.noText`.
struct PDFExtractor: FileTextExtractor {
    func extract(from url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw ExtractionError.readFailed("Not a readable PDF")
        }
        // `doc.string` concatenates all pages; may be nil/empty for scanned PDFs.
        if let whole = doc.string, !whole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return whole
        }
        // Fall back to per-page extraction.
        var pieces: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string { pieces.append(s) }
        }
        let joined = pieces.joined(separator: "\n\n")
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExtractionError.noText
        }
        return joined
    }
}
