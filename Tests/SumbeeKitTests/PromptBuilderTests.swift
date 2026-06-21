import XCTest
@testable import SumbeeKit

final class PromptBuilderTests: XCTestCase {
    private let style = SummaryStyle(name: "Meetings — General", channel: .file,
                                     prompt: "Summarize the meeting. Use ## sections.", order: 1)

    func testMarkdownConventionIncludesStylePromptAndTitleRule() {
        let sys = PromptBuilder.systemPrompt(style: style, format: .markdown, htmlStylingPrompt: "")
        XCTAssertTrue(sys.contains("Summarize the meeting"))
        XCTAssertTrue(sys.contains("# <a concise"))
        XCTAssertTrue(sys.contains("Markdown"))
    }

    func testHTMLConventionMentionsH1AndStylingPrompt() {
        let sys = PromptBuilder.systemPrompt(style: style, format: .html,
                                             htmlStylingPrompt: "Use a dark theme with orange accents.")
        XCTAssertTrue(sys.contains("<h1>"))
        XCTAssertTrue(sys.contains("self-contained HTML"))
        XCTAssertTrue(sys.contains("dark theme with orange accents"))
    }

    func testExtractTitleMarkdown() {
        let out = "# Q2 Roadmap Sync\n\n## TL;DR\nStuff."
        XCTAssertEqual(PromptBuilder.extractTitle(from: out, format: .markdown), "Q2 Roadmap Sync")
    }

    func testExtractTitleMarkdownIgnoresH2() {
        let out = "Intro line\n## Not a title\n# Real Title"
        XCTAssertEqual(PromptBuilder.extractTitle(from: out, format: .markdown), "Real Title")
    }

    func testExtractTitleHTML() {
        let out = "<!DOCTYPE html><html><head></head><body><h1>Hello World</h1><p>x</p></body></html>"
        XCTAssertEqual(PromptBuilder.extractTitle(from: out, format: .html), "Hello World")
    }

    func testExtractTitleNilWhenAbsent() {
        XCTAssertNil(PromptBuilder.extractTitle(from: "no heading here", format: .markdown))
    }

    func testGlobalSystemPromptPrependedBeforeStyle() {
        let sys = PromptBuilder.systemPrompt(style: style, format: .markdown, htmlStylingPrompt: "",
                                             globalPrompt: "You are a precise note-taker.")
        XCTAssertTrue(sys.contains("You are a precise note-taker."))
        // Global prompt must come before the style prompt, which comes before the convention.
        let gi = sys.range(of: "precise note-taker")!.lowerBound
        let si = sys.range(of: "Summarize the meeting")!.lowerBound
        XCTAssertTrue(gi < si, "global system prompt should precede the style prompt")
    }

    func testEmptyGlobalSystemPromptIsNoOp() {
        let withEmpty = PromptBuilder.systemPrompt(style: style, format: .markdown,
                                                   htmlStylingPrompt: "", globalPrompt: "   ")
        let without = PromptBuilder.systemPrompt(style: style, format: .markdown, htmlStylingPrompt: "")
        XCTAssertEqual(withEmpty, without)
    }

    func testUserMessageEmbedsVideoMeta() {
        let meta = VideoMeta(videoID: "abc", title: "Cool Video", channel: "Chan",
                             durationSeconds: 125, uploadDate: "2026-06-20")
        let msg = PromptBuilder.userMessage(transcript: "hello", videoMeta: meta)
        XCTAssertTrue(msg.contains("Cool Video"))
        XCTAssertTrue(msg.contains("hello"))
    }
}
