import XCTest
@testable import SumbeeKit

final class TranscriptAssemblerTests: XCTestCase {
    func testLongSpeakerMonologueHasReviewableParagraphsWithoutTextLoss() {
        let tokens = (0..<120).map { MeetingRecognition.Token(text: " word\($0)", start: Double($0), end: Double($0 + 1)) }
        let text = tokens.map(\.text).joined()
        let recognition = MeetingRecognition(text: text, duration: 120, tokens: tokens,
            intervals: [.init(speakerKey: "a", start: 0, end: 120)], embeddings: [:],
            modelFingerprint: "test", embeddingFingerprint: "test")
        let assembled = TranscriptAssembler.assemble(recognition)
        XCTAssertEqual(assembled.turns.map(\.text).joined(), text)
        XCTAssertGreaterThanOrEqual(assembled.turns.count, 4)
        XCTAssertTrue(assembled.turns.allSatisfy { ($0.end ?? 0) - ($0.start ?? 0) <= 30 })
    }
    private func recognition(_ text: String, tokens: [MeetingRecognition.Token],
                             intervals: [MeetingRecognition.SpeakerInterval] = []) -> MeetingRecognition {
        MeetingRecognition(text: text, duration: 10, tokens: tokens, intervals: intervals,
                           embeddings: [:], modelFingerprint: "test", embeddingFingerprint: "embedding")
    }

    func testSubwordsUseIntervalsAndPreserveOriginalText() throws {
        let result = recognition("Hello everyone. Next topic!", tokens: [
            .init(text: " Hel", start: 0, end: 0.3), .init(text: "lo", start: 0.3, end: 0.5),
            .init(text: " everyone.", start: 0.5, end: 1),
            .init(text: " Next", start: 4, end: 4.5), .init(text: " topic!", start: 4.5, end: 5)
        ], intervals: [.init(speakerKey: "a", start: 0, end: 2), .init(speakerKey: "b", start: 3, end: 6)])
        let assembled = TranscriptAssembler.assemble(result)
        XCTAssertEqual(assembled.turns.map(\.text).joined(), result.text)
        XCTAssertEqual(assembled.turns.count, 2)
        XCTAssertNotEqual(assembled.turns[0].speakerID, assembled.turns[1].speakerID)
        XCTAssertEqual(assembled.turns[0].start, 0)
    }

    func testMissingTokenTextAndTimingsNeverDiscardRecognizedWords() {
        let result = recognition("Before middle after", tokens: [
            .init(text: "Before", start: 0, end: 1), .init(text: " after", start: 8, end: 9)
        ])
        let assembled = TranscriptAssembler.assemble(result)
        XCTAssertEqual(assembled.turns.map(\.text).joined(), result.text)
        XCTAssertTrue(assembled.turns.contains { $0.start == nil && $0.text.contains("middle") })
    }

    func testOverlapTieIsUnknownAndNoTimingsStillPreserveText() {
        let result = recognition("Yes.", tokens: [.init(text: "Yes.", start: 0, end: 1)], intervals: [
            .init(speakerKey: "a", start: 0, end: 1), .init(speakerKey: "b", start: 0, end: 1)
        ])
        let output = TranscriptAssembler.assemble(result)
        XCTAssertEqual(output.speakers.first { $0.id == output.turns[0].speakerID }?.genericLabel, "Unknown speaker")
        let untimed = TranscriptAssembler.assemble(recognition("Keep everything.", tokens: []))
        XCTAssertEqual(untimed.turns.map(\.text).joined(), "Keep everything.")
        XCTAssertNil(untimed.turns.first?.start)
    }
}
