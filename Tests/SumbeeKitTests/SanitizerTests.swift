import XCTest
@testable import SumbeeKit

final class SanitizerTests: XCTestCase {
    func testStripsIllegalCharacters() {
        let result = Sanitizer.sanitizeTitle("Q2/Roadmap: \"Sync\" <plan>?")
        XCTAssertFalse(result.contains("/"))
        XCTAssertFalse(result.contains(":"))
        XCTAssertFalse(result.contains("\""))
        XCTAssertFalse(result.contains("<"))
        XCTAssertFalse(result.contains(">"))
        XCTAssertFalse(result.contains("?"))
    }

    func testCollapsesWhitespaceAndTrims() {
        XCTAssertEqual(Sanitizer.sanitizeTitle("  Hello   world \n test "), "Hello world test")
    }

    func testEmptyBecomesUntitled() {
        XCTAssertEqual(Sanitizer.sanitizeTitle("   "), "Untitled")
        XCTAssertEqual(Sanitizer.sanitizeTitle("///"), "Untitled")
    }

    func testTrimsLength() {
        let long = String(repeating: "a", count: 200)
        XCTAssertLessThanOrEqual(Sanitizer.sanitizeTitle(long).count, 80)
    }

    func testUniqueFilenameAppendsSuffix() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sani-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = Sanitizer.uniqueFilename(baseName: "note", ext: "md", in: dir)
        XCTAssertEqual(first, "note.md")
        try Data().write(to: dir.appendingPathComponent(first))

        let second = Sanitizer.uniqueFilename(baseName: "note", ext: "md", in: dir)
        XCTAssertEqual(second, "note (2).md")
        try Data().write(to: dir.appendingPathComponent(second))

        let third = Sanitizer.uniqueFilename(baseName: "note", ext: "md", in: dir)
        XCTAssertEqual(third, "note (3).md")
    }

    func testUniqueFilenameEmptyExtension() {
        let dir = FileManager.default.temporaryDirectory
        let name = Sanitizer.uniqueFilename(baseName: "video__2026", ext: "", in: dir)
        XCTAssertFalse(name.hasSuffix("."))
    }
}
