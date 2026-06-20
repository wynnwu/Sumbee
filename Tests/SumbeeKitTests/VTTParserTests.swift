import XCTest
@testable import SumbeeKit

final class VTTParserTests: XCTestCase {
    func testDedupesRollingCaptions() {
        // Auto-captions: each cue repeats the prior line then adds a new one.
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        Hello and welcome

        00:00:02.000 --> 00:00:04.000
        Hello and welcome
        to the show

        00:00:04.000 --> 00:00:06.000
        to the show
        let's begin
        """
        let out = VTTParser.parse(vtt, includeTimestamps: false)
        let lines = out.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines, ["Hello and welcome", "to the show", "let's begin"])
    }

    func testStripsInlineTagsAndEntities() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        <c>It&#39;s</c> a <b>test</b>
        """
        let out = VTTParser.parse(vtt, includeTimestamps: false)
        XCTAssertTrue(out.contains("It's a test"))
        XCTAssertFalse(out.contains("<c>"))
        XCTAssertFalse(out.contains("&#39;"))
    }

    func testInjectsCoarseTimestamps() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        first

        00:00:40.000 --> 00:00:42.000
        later
        """
        let out = VTTParser.parse(vtt, includeTimestamps: true, interval: 30)
        XCTAssertTrue(out.contains("(0:01)"))
        XCTAssertTrue(out.contains("(0:40)"))
    }

    func testSecondsFromTimestamp() throws {
        let a = try XCTUnwrap(VTTParser.seconds(fromTimestamp: "01:02:03.500"))
        XCTAssertEqual(a, 3723.5, accuracy: 0.001)
        let b = try XCTUnwrap(VTTParser.seconds(fromTimestamp: "02:05.000"))
        XCTAssertEqual(b, 125, accuracy: 0.001)
    }
}
