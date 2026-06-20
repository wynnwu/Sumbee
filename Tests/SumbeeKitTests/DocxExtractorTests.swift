import XCTest
@testable import SumbeeKit

final class DocxExtractorTests: XCTestCase {
    func testExtractsTextFromGeneratedDocx() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/zip") else {
            throw XCTSkip("zip not available")
        }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("docx-\(UUID().uuidString)", isDirectory: true)
        let wordDir = tmp.appendingPathComponent("word", isDirectory: true)
        try fm.createDirectory(at: wordDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Hello world</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second </w:t><w:t>paragraph</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        try xml.data(using: .utf8)!.write(to: wordDir.appendingPathComponent("document.xml"))

        let docx = tmp.appendingPathComponent("test.docx")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = tmp
        zip.arguments = ["-r", "-q", "test.docx", "word"]
        try zip.run()
        zip.waitUntilExit()
        try XCTSkipUnless(zip.terminationStatus == 0, "zip failed")

        let text = try TextExtractor().extract(from: docx)
        XCTAssertTrue(text.contains("Hello world"), "got: \(text)")
        XCTAssertTrue(text.contains("Second paragraph"), "got: \(text)")
    }
}
