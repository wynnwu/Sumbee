import XCTest
@testable import SumbeeKit

final class MeetingParticipantTests: XCTestCase {
    private func fixture() throws -> (MeetingStore, ParticipantStore, MeetingDocument, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent(".meetings")
        var meeting = MeetingDocument(title: "Planning", originalFilename: "meeting.wav",
            audioSHA256: String(repeating: "a", count: 64), durationSeconds: 60)
        meeting.status = .ready
        meeting.speakers = [.init(genericLabel: "Speaker 1", clusterKeys: ["a"]), .init(genericLabel: "Speaker 2", clusterKeys: ["b"])]
        meeting.turns = [.init(text: "First turn. ", start: 0, end: 20, speakerID: meeting.speakers[0].id),
                         .init(text: "Second turn.", start: 30, end: 50, speakerID: meeting.speakers[1].id)]
        meeting.recognitionResult = .init(text: "First turn. Second turn.", duration: 60, tokens: [],
            intervals: [.init(speakerKey: "a", start: 0, end: 20), .init(speakerKey: "b", start: 30, end: 50)],
            embeddings: ["a": [1, 0], "b": [0, 1]], modelFingerprint: "test", embeddingFingerprint: "test")
        let folder = directory.appendingPathComponent(meeting.id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(meeting).write(to: folder.appendingPathComponent("meeting.json"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (MeetingStore(root: root), ParticipantStore(root: root), meeting, root)
    }

    func testMergeRenameAndDeleteKeepOldExportsAndUseLatestOrSavedNamesForNewOnes() async throws {
        let (store, people, original, root) = try fixture()
        let first = try await people.add(name: "Original name"), survivor = try await people.add(name: "Survivor")
        try await store.assignParticipant(original.id, speakerID: original.speakers[0].id, participantID: first.id, name: first.name)
        let assigned = try await store.load(original.id)
        XCTAssertEqual(assigned.reviewRevision, original.reviewRevision + 1)
        XCTAssertEqual(assigned.attributionRevision, original.attributionRevision + 1)
        let before = try await MeetingSummaryInputBuilder.prepare(original.id, meetings: store, people: people)
        let frozen = try Data(contentsOf: root.appendingPathComponent(XCTUnwrap(before.sourceRef)))
        try await people.merge(first.id, into: survivor.id)
        try await people.rename(survivor.id, name: "Current name")
        let merged = try await MeetingSummaryInputBuilder.prepare(original.id, meetings: store, people: people)
        XCTAssertTrue(merged.text.contains("Current name:"))
        try await people.delete(survivor.id)
        let deleted = try await MeetingSummaryInputBuilder.prepare(original.id, meetings: store, people: people)
        XCTAssertTrue(deleted.text.contains("Original name:"))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(before.sourceRef!)), frozen)
        let after = try await store.load(original.id)
        XCTAssertEqual(after.reviewRevision, assigned.reviewRevision)
        XCTAssertEqual(after.turns.map(\.text), assigned.turns.map(\.text))
        XCTAssertEqual(after.speakers[0].displayNameSnapshot, first.name)
    }

    func testTextEditsDoNotInvalidateVoicesButMergingTurnLabelsDoes() async throws {
        let (store, people, original, _) = try fixture()
        let person = try await people.add(name: "Alex")
        try await store.assignParticipant(original.id, speakerID: original.speakers[0].id, participantID: person.id, name: person.name)
        try await people.enroll(meetingID: original.id, speakerID: original.speakers[0].id, meetings: store)
        let named = try await store.load(original.id)
        try await store.editText(original.id, turnID: original.turns[0].id, text: "Corrected first turn. ")
        let edited = try await store.load(original.id)
        XCTAssertEqual(edited.reviewRevision, named.reviewRevision + 1)
        XCTAssertEqual(edited.attributionRevision, named.attributionRevision)
        let eligible = try await people.candidates(fingerprint: "test", meetings: store)
        XCTAssertEqual(eligible.count, 1)
        try await store.mergeSpeakers(original.id, from: original.speakers[1].id, into: original.speakers[0].id)
        let merged = try await store.load(original.id)
        XCTAssertEqual(merged.turns.map(\.text), edited.turns.map(\.text))
        XCTAssertEqual(merged.turns.map(\.id), edited.turns.map(\.id))
        XCTAssertEqual(merged.attributionRevision, edited.attributionRevision + 1)
        let stale = try await people.candidates(fingerprint: "test", meetings: store)
        XCTAssertTrue(stale.isEmpty)
    }

    func testConcurrentAttendeeSelectionsPreserveBothPeopleAndReview() async throws {
        let (store, _, meeting, _) = try fixture()
        let first = UUID(), second = UUID()
        async let one: Void = store.setExpectedParticipant(meeting.id, participantID: first, included: true)
        async let two: Void = store.setExpectedParticipant(meeting.id, participantID: second, included: true)
        _ = try await (one, two)
        let selected = try await store.load(meeting.id)
        XCTAssertEqual(selected.expectedParticipantIDs, [first, second])
        try await store.setExpectedParticipant(meeting.id, participantID: first, included: false)
        let removed = try await store.load(meeting.id)
        XCTAssertEqual(removed.expectedParticipantIDs, [second])
        XCTAssertEqual(removed.turns.map(\.id), meeting.turns.map(\.id))
        XCTAssertEqual(removed.turns.map(\.text), meeting.turns.map(\.text))
        XCTAssertEqual(removed.reviewRevision, meeting.reviewRevision)
        XCTAssertEqual(removed.attributionRevision, meeting.attributionRevision)
    }
}
