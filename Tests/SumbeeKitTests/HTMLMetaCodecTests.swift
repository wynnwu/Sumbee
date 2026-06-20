import XCTest
@testable import SumbeeKit

final class HTMLMetaCodecTests: XCTestCase {
    func testEscapeDecodeRoundTrip() {
        let originals = [
            #"Q&A: "Plinko" review <draft>"#,
            "https://example.com/?a=1&b=2",
            "plain title",
            "tag <b> & quote \"x\"",
        ]
        for s in originals {
            XCTAssertEqual(HTMLMetaCodec.decode(HTMLMetaCodec.escape(s)), s, "round-trip failed for \(s)")
        }
    }

    func testInsertSourceLinkBeforeBody() {
        let html = "<!DOCTYPE html><html><head></head><body><h1>x</h1><p>body</p></body></html>"
        let url = "https://youtu.be/abc?x=1&y=2"
        let out = HTMLMetaCodec.insertSourceLink(url, into: html)

        // Link is present, escaped, and sits before the closing body tag.
        XCTAssertTrue(out.contains("text-align:center"))
        XCTAssertTrue(out.contains("text-decoration:underline"))
        XCTAssertTrue(out.contains("https://youtu.be/abc?x=1&amp;y=2"))
        let linkIdx = try? XCTUnwrap(out.range(of: "<a href")?.lowerBound)
        let bodyIdx = try? XCTUnwrap(out.range(of: "</body>")?.lowerBound)
        if let l = linkIdx, let b = bodyIdx { XCTAssertTrue(l < b, "link must precede </body>") }
    }

    func testInsertSourceLinkAppendsWhenNoBody() {
        let out = HTMLMetaCodec.insertSourceLink("https://x.test", into: "<h1>no body tag</h1>")
        XCTAssertTrue(out.contains("https://x.test"))
    }

    func testEmbedAndReadBackPreservesTitleWithSpecials() {
        let title = #"Q&A: "Plinko" review <draft>"#
        let html = "<!DOCTYPE html><html><head><title>x</title></head><body><h1>x</h1></body></html>"
        let withMeta = HTMLMetaCodec.embed([
            ("title", title),
            ("style", "YouTube"),
            ("created", "2026-06-20T14:32:05-07:00"),
            ("source", "https://youtu.be/abc?x=1&y=2"),
            ("model", "claude-opus-4-8"),
        ], into: html)

        // The on-disk meta is escaped...
        XCTAssertTrue(withMeta.contains("&amp;"))
        XCTAssertTrue(withMeta.contains("&quot;"))
        // ...and LibraryStore's reader decodes it back to the original.
        XCTAssertEqual(LibraryStore.htmlMeta(withMeta, name: "title"), title)
        XCTAssertEqual(LibraryStore.htmlMeta(withMeta, name: "source"), "https://youtu.be/abc?x=1&y=2")
    }
}
