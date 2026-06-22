import Foundation

/// `.txt` / `.md`: read as UTF-8, falling back to other common encodings.
struct PlainTextExtractor: FileTextExtractor {
    func extract(from url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        // Foundation can sniff the encoding for many files.
        if let s = try? String(contentsOf: url, encoding: .isoLatin1) { return s }
        do {
            let data = try Data(contentsOf: url)
            if let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                return s
            }
            throw ExtractionError.readFailed("Unknown text encoding")
        } catch let e as ExtractionError {
            throw e
        } catch {
            throw ExtractionError.readFailed(error.localizedDescription)
        }
    }
}
