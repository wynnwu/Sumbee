import XCTest
@testable import SumbeeKit

final class HTMLFeatureScannerTests: XCTestCase {

    // Plain styled prose/tables/lists with inline CSS is the common, "basic" case: not advanced.
    func testPlainStyledHTMLIsNotAdvanced() {
        let html = """
        <!DOCTYPE html><html><head><style>body{font-family:serif;color:#222}</style></head>
        <body><h1>Q2 Roadmap</h1><p>Decisions and next steps.</p>
        <table><tr><th>Owner</th><th>Task</th></tr><tr><td>Wynn</td><td>Spec</td></tr></table>
        <ul><li>Ship preview</li></ul></body></html>
        """
        let r = HTMLFeatureScanner.scan(html)
        XCTAssertFalse(r.hasAdvancedFeatures)
        XCTAssertTrue(r.features.isEmpty)
    }

    // The KEY false-positive guard: a plain anchor link - including the stamped grey source link -
    // must NOT make a document "advanced".
    func testAnchorAndSourceLinkAreNotAdvanced() {
        let html = """
        <!DOCTYPE html><html><body><h1>Video notes</h1><p>See <a href="https://example.com">docs</a>.</p>
        <p style="text-align:center;margin:2.5em 0 1em">
        <a href="https://www.youtube.com/watch?v=abc123" style="color:#888;text-decoration:underline">\
        https://www.youtube.com/watch?v=abc123</a></p></body></html>
        """
        let r = HTMLFeatureScanner.scan(html)
        XCTAssertFalse(r.hasAdvancedFeatures, "anchor links must not count as advanced")
    }

    func testScriptIsAdvanced() {
        let r = HTMLFeatureScanner.scan("<html><body><script>document.title='x'</script></body></html>")
        XCTAssertTrue(r.hasAdvancedFeatures)
        XCTAssertEqual(r.features, ["JavaScript"])
    }

    func testIframeEmbedObjectAreEmbeddedContent() {
        XCTAssertEqual(HTMLFeatureScanner.scan("<iframe src='x'></iframe>").features, ["Embedded content"])
        XCTAssertEqual(HTMLFeatureScanner.scan("<embed src='x'>").features, ["Embedded content"])
        XCTAssertEqual(HTMLFeatureScanner.scan("<object data='x'></object>").features, ["Embedded content"])
    }

    func testMediaIsAdvanced() {
        XCTAssertEqual(HTMLFeatureScanner.scan("<video controls></video>").features, ["Media"])
        XCTAssertEqual(HTMLFeatureScanner.scan("<audio src='a.mp3'></audio>").features, ["Media"])
    }

    func testCanvasIsGraphics() {
        XCTAssertEqual(HTMLFeatureScanner.scan("<canvas id='c'></canvas>").features, ["Graphics"])
    }

    func testFormControlsAreInteractive() {
        XCTAssertEqual(HTMLFeatureScanner.scan("<form><input type='text'></form>").features,
                       ["Interactive controls"])
        XCTAssertEqual(HTMLFeatureScanner.scan("<select><option>a</option></select>").features,
                       ["Interactive controls"])
    }

    func testInlineEventHandlerIsScriptedHandler() {
        let r = HTMLFeatureScanner.scan("<div onclick=\"go()\">tap</div>")
        XCTAssertTrue(r.hasAdvancedFeatures)
        XCTAssertEqual(r.features, ["Scripted handlers"])
    }

    // "on" inside ordinary attribute values / words must not be mistaken for an event handler.
    func testWordContainingOnIsNotAHandler() {
        let r = HTMLFeatureScanner.scan("<p class=\"section\">Companion notes, onboarding.</p>")
        XCTAssertFalse(r.hasAdvancedFeatures)
    }

    // Multiple categories: labels are present, deduped, and in stable (declaration) order.
    func testMultipleFeaturesAreDedupedAndOrdered() {
        let html = "<script></script><script></script><video></video><div onmouseover='x'></div>"
        let r = HTMLFeatureScanner.scan(html)
        XCTAssertEqual(r.features, ["JavaScript", "Media", "Scripted handlers"])
    }

    func testDetectionIsCaseInsensitive() {
        XCTAssertTrue(HTMLFeatureScanner.scan("<BODY><SCRIPT>x</SCRIPT></BODY>").hasAdvancedFeatures)
    }
}
