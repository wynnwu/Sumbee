import XCTest
@testable import SumbeeKit

final class MeetingDocumentTests: XCTestCase {
    func testOptionalReviewMetadataDefaultsWithoutLosingRequiredIdentity() throws {
        let original = MeetingDocument(title: "Older meeting", originalFilename: "meeting.wav",
            audioSHA256: String(repeating: "a", count: 64), durationSeconds: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["expectedParticipantIDs", "exports", "recognitionResult", "modelFingerprint"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(MeetingDocument.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertTrue(decoded.expectedParticipantIDs.isEmpty)
        XCTAssertTrue(decoded.exports.isEmpty)
        object.removeValue(forKey: "id")
        XCTAssertThrowsError(try JSONDecoder().decode(MeetingDocument.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    func testRoundTripPreservesIdentityAndRejectsFutureSchema() throws {
        var meeting = MeetingDocument(title: "Team sync", originalFilename: "meeting.m4a",
                                      audioSHA256: String(repeating: "a", count: 64), durationSeconds: 90)
        let encoded = try JSONEncoder().encode(meeting)
        let decoded = try JSONDecoder().decode(MeetingDocument.self, from: encoded)
        try decoded.validate()
        XCTAssertEqual(decoded.id, meeting.id)
        meeting.schemaVersion = 2
        XCTAssertThrowsError(try meeting.validate())
    }

    func testRejectsDanglingSpeakerInvalidTimesAndEscapingPaths() throws {
        var meeting = MeetingDocument(title: "Sync", originalFilename: "file.wav",
                                      audioSHA256: String(repeating: "b", count: 64), durationSeconds: 10)
        let speaker = MeetingSpeaker(genericLabel: "Speaker 1")
        meeting.speakers = [speaker]
        meeting.turns = [.init(text: "Hello", start: 0, end: 11, speakerID: speaker.id)]
        XCTAssertThrowsError(try meeting.validate())
        meeting.turns[0].end = 5
        try meeting.validate()
        meeting.turns[0].speakerID = UUID()
        XCTAssertThrowsError(try meeting.validate())
        meeting.turns = []
        meeting.audioPath = "../private.wav"
        XCTAssertThrowsError(try meeting.validate())
    }

    func testUntimedTextIsValidButNoSpeechCannotContainWords() throws {
        var meeting = MeetingDocument(title: "Sync", originalFilename: "file.wav",
                                      audioSHA256: String(repeating: "c", count: 64), durationSeconds: 10)
        let speaker = MeetingSpeaker(genericLabel: "Unknown speaker")
        meeting.speakers = [speaker]
        meeting.turns = [.init(text: "Still retain this", start: nil, end: nil, speakerID: speaker.id)]
        try meeting.validate()
        meeting.status = .noSpeech
        XCTAssertThrowsError(try meeting.validate())
    }
}
