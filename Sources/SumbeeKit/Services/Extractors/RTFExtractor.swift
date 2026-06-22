import Foundation
import AppKit

/// `.rtf`: native conversion via `NSAttributedString`, which handles RTF markup and
/// HTML entities for us (no third-party RTF parser needed).
struct RTFExtractor: FileTextExtractor {
    func extract(from url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
            let attributed = try NSAttributedString(data: data, options: options, documentAttributes: nil)
            return attributed.string
        } catch let e as ExtractionError {
            throw e
        } catch {
            throw ExtractionError.readFailed(error.localizedDescription)
        }
    }
}
