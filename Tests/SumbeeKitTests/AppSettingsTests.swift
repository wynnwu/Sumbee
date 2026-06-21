import XCTest
@testable import SumbeeKit

final class AppSettingsTests: XCTestCase {

    /// An older config.json (no systemPrompt / previewFontSize) must decode with defaults for the
    /// new fields and keep every existing value — never silently reset (FR-034/036, D15).
    func testDecodeToleratesMissingNewFields() throws {
        let json = """
        {"schemaVersion":2,"libraryRootPath":"~/Sumbee Summaries","model":"claude-opus-4-8",
         "maxOutputTokens":12345,"temperature":0.5,"extendedThinking":false,
         "captionLanguage":"en","outputFormat":"markdown","htmlStylingPrompt":"keep me"}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(s.maxOutputTokens, 12345)          // preserved
        XCTAssertEqual(s.htmlStylingPrompt, "keep me")    // preserved
        XCTAssertEqual(s.systemPrompt, "")                // new field defaulted
        XCTAssertEqual(s.previewFontSize, 16)             // new field defaulted
    }

    func testRoundTripPreservesNewFields() throws {
        var s = AppSettings()
        s.systemPrompt = "Shared prefix for all styles"
        s.previewFontSize = 22
        s.geekMode = true
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.systemPrompt, "Shared prefix for all styles")
        XCTAssertEqual(back.previewFontSize, 22)
        XCTAssertTrue(back.geekMode)
    }

    func testGeekModeDefaultsFalseWhenAbsent() throws {
        let json = "{\"schemaVersion\":2}".data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: json).geekMode)
    }
}
