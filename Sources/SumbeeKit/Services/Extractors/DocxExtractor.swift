import Foundation

/// `.docx`: a DOCX is a ZIP whose main content is `word/document.xml`. We extract that
/// entry with the system `unzip` binary (zero third-party deps) and pull the text runs
/// out with Foundation's `XMLParser`.
struct DocxExtractor: FileTextExtractor {
    func extract(from url: URL) throws -> String {
        let unzip = Self.unzipPath()
        let result: ProcessRunner.Result
        do {
            result = try ProcessRunner.run(unzip, ["-p", url.path, "word/document.xml"])
        } catch {
            throw ExtractionError.readFailed("unzip failed: \(error)")
        }
        guard result.status == 0, !result.stdout.isEmpty else {
            throw ExtractionError.readFailed("Couldn’t read word/document.xml (\(result.status))")
        }

        let parser = XMLParser(data: result.stdout)
        let delegate = DocxXMLDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw ExtractionError.readFailed("Malformed DOCX XML")
        }
        return delegate.text
    }

    private static func unzipPath() -> String {
        let candidates = ["/usr/bin/unzip", "/bin/unzip"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/unzip"
    }
}

/// Collects readable text from WordprocessingML: `<w:t>` runs, `<w:p>` → newline,
/// `<w:tab>` → tab, `<w:br>` → newline.
private final class DocxXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var text = ""
    private var inTextRun = false
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        switch elementName {
        case "w:t": inTextRun = true; buffer = ""
        case "w:tab": text += "\t"
        case "w:br", "w:cr": text += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTextRun { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t":
            text += buffer
            buffer = ""
            inTextRun = false
        case "w:p":
            text += "\n"
        default:
            break
        }
    }
}
