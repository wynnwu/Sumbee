import XCTest
@testable import SumbeeKit

final class ParticipantMatcherTests: XCTestCase {
    func testUnknownAndAmbiguousVoicesAbstain() {
        let a = UUID(), b = UUID()
        let candidates = [ParticipantCandidate(participantID: a, embedding: [1, 0]),
                          ParticipantCandidate(participantID: b, embedding: [1, 0])]
        XCTAssertNil(ParticipantMatcher.suggest(embedding: [1, 0], candidates: candidates))
        XCTAssertNil(ParticipantMatcher.suggest(embedding: [0, 1], candidates: [candidates[0]]))
        XCTAssertNil(ParticipantMatcher.suggest(embedding: [.nan, 0], candidates: candidates))
    }

    func testDistinctPersonMarginAndAttendeesRatherThanProfileMargin() throws {
        let a = UUID(), b = UUID()
        let candidates = [ParticipantCandidate(participantID: a, embedding: [1, 0]),
                          ParticipantCandidate(participantID: a, embedding: [0.99, 0.01]),
                          ParticipantCandidate(participantID: b, embedding: [0, 1])]
        XCTAssertEqual(ParticipantMatcher.suggest(embedding: [1, 0], candidates: candidates)?.participantID, a)
        XCTAssertNil(ParticipantMatcher.suggest(embedding: [1, 0], candidates: candidates, expected: [b]))
    }

    func testDimensionMismatchAndZeroVectorsAreIgnored() {
        let a = UUID()
        XCTAssertNil(ParticipantMatcher.suggest(embedding: [1, 0], candidates: [
            .init(participantID: a, embedding: [1, 0, 0]), .init(participantID: a, embedding: [0, 0])]))
    }
}
