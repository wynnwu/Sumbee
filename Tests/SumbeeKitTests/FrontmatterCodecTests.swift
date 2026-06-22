import XCTest
@testable import SumbeeKit

final class FrontmatterCodecTests: XCTestCase {
    func testRoundTrip() {
        var fm = Frontmatter()
        fm["id"] = "abc-123"
        fm["channel"] = "file"
        fm["order"] = "2"
        fm["enabled"] = "true"
        let doc = FrontmatterCodec.Document(frontmatter: fm, body: "# Title\n\nBody text here.")

        let serialized = FrontmatterCodec.serialize(doc)
        let parsed = FrontmatterCodec.parse(serialized)

        XCTAssertEqual(parsed.frontmatter["id"], "abc-123")
        XCTAssertEqual(parsed.frontmatter["channel"], "file")
        XCTAssertEqual(parsed.frontmatter.int("order"), 2)
        XCTAssertEqual(parsed.frontmatter.bool("enabled"), true)
        XCTAssertEqual(parsed.body, "# Title\n\nBody text here.")
    }

    func testNoFrontmatterReturnsWholeBody() {
        let content = "Just a plain body\nwith two lines."
        let parsed = FrontmatterCodec.parse(content)
        XCTAssertTrue(parsed.frontmatter.pairs.isEmpty)
        XCTAssertEqual(parsed.body, content)
    }

    func testValueWithColonIsQuotedAndPreserved() {
        var fm = Frontmatter()
        fm["title"] = "Q2: Roadmap - Notes"
        let serialized = FrontmatterCodec.serialize(.init(frontmatter: fm, body: "x"))
        XCTAssertTrue(serialized.contains("\"Q2: Roadmap - Notes\""))
        let parsed = FrontmatterCodec.parse(serialized)
        XCTAssertEqual(parsed.frontmatter["title"], "Q2: Roadmap - Notes")
    }

    func testCRLFNormalized() {
        let content = "---\r\nid: x\r\n---\r\n\r\nBody"
        let parsed = FrontmatterCodec.parse(content)
        XCTAssertEqual(parsed.frontmatter["id"], "x")
        XCTAssertEqual(parsed.body, "Body")
    }
}
