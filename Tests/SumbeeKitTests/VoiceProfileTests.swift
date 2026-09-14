import XCTest
@testable import SumbeeKit

final class VoiceProfileTests: XCTestCase {
    @MainActor
    func testDeletingAudioPreservesTranscriptPeopleVoicesModelsAndSummarySource() async throws {
        let (root, meeting) = try fixture()
        let meetings = MeetingStore(root: root), people = ParticipantStore(root: root)
        let audio = root.appendingPathComponent(meeting.audioPath)
        try Data("retained audio".utf8).write(to: audio)
        let model = root.appendingPathComponent("model.bin")
        try Data("model bytes".utf8).write(to: model)
        let summary = root.appendingPathComponent("summary.md")
        try Data("saved summary".utf8).write(to: summary)
        let person = try await people.add(name: "Alex")
        try await meetings.assignParticipant(meeting.id, speakerID: meeting.speakers[0].id,
                                            participantID: person.id, name: person.name)
        try await people.enroll(meetingID: meeting.id, speakerID: meeting.speakers[0].id, meetings: meetings)
        let prepared = try await MeetingSummaryInputBuilder.prepare(meeting.id, meetings: meetings, people: people)
        let catalogURL = root.appendingPathComponent(".meetings/participants.json")
        let catalogBytes = try Data(contentsOf: catalogURL)
        let state = MeetingProcessingState()
        await state.selectRoot(root)
        let deleted = await state.deleteAudio(meeting.id, root: MeetingLibraryPath.directory(root))
        XCTAssertTrue(deleted)
        XCTAssertEqual(state.documents.map(\.id), [meeting.id])
        XCTAssertFalse(state.hasAudio(meeting.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertEqual(try Data(contentsOf: catalogURL), catalogBytes)
        XCTAssertEqual(try Data(contentsOf: model), Data("model bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: summary), Data("saved summary".utf8))
        let candidates = try await people.candidates(fingerprint: "voice-v1", meetings: meetings)
        XCTAssertEqual(candidates.map(\.participantID), [person.id])
        let snapshot = try MeetingSummaryInputBuilder.readSnapshot(sourceRef: XCTUnwrap(prepared.sourceRef), root: root, title: meeting.title)
        XCTAssertEqual(snapshot.text, prepared.text)
        // Review/edit/export/summary preparation still work after reopening without audio.
        let reopened = MeetingProcessingState()
        await reopened.selectRoot(root)
        XCTAssertFalse(reopened.hasAudio(meeting.id))
        XCTAssertEqual(reopened.documents.first?.turns.map(\.text), meeting.turns.map(\.text))
        try await meetings.editText(meeting.id, turnID: meeting.turns[0].id, text: "Reviewed without audio")
        let next = try await MeetingSummaryInputBuilder.prepare(meeting.id, meetings: meetings, people: people)
        XCTAssertTrue(next.text.contains("Reviewed without audio"))
    }

    func testDeletingAudioDoesNotReadOrRewriteParticipantCatalog() async throws {
        let (root, meeting) = try fixture()
        let audio = root.appendingPathComponent(meeting.audioPath)
        try Data("audio".utf8).write(to: audio)
        let catalogURL = root.appendingPathComponent(".meetings/participants.json")
        let original = Data("corrupt catalog".utf8)
        try original.write(to: catalogURL)
        try await MeetingStore(root: root).deleteAudio(meeting.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertEqual(try Data(contentsOf: catalogURL), original)
        let retained = try await MeetingStore(root: root).load(meeting.id)
        XCTAssertEqual(retained.id, meeting.id)
    }

    private func fixture() throws -> (URL, MeetingDocument) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var meeting = MeetingDocument(title: "Voice fixture", originalFilename: "voice.wav",
            audioSHA256: String(repeating: "a", count: 64), durationSeconds: 30)
        meeting.status = .ready
        let speaker = MeetingSpeaker(genericLabel: "Speaker 1", clusterKeys: ["a"])
        meeting.speakers = [speaker]
        meeting.turns = [.init(text: "Hello", start: 0, end: 20, speakerID: speaker.id)]
        meeting.recognitionResult = .init(text: "Hello", duration: 30, tokens: [],
            intervals: [.init(speakerKey: "a", start: 0, end: 20)], embeddings: ["a": [3, 4]],
            modelFingerprint: "model", embeddingFingerprint: "voice-v1")
        let directory = root.appendingPathComponent(".meetings/\(meeting.id.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(meeting).write(to: directory.appendingPathComponent("meeting.json"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, meeting)
    }

    func testNamingDoesNotEnrollAndAttributionChangesInvalidateAcrossRestart() async throws {
        let (root, meeting) = try fixture()
        let meetings = MeetingStore(root: root), people = ParticipantStore(root: root)
        let person = try await people.add(name: "Alex")
        try await meetings.assignParticipant(meeting.id, speakerID: meeting.speakers[0].id, participantID: person.id, name: person.name)
        let named = try await people.load()
        XCTAssertTrue(named.profiles.isEmpty)
        try await people.enroll(meetingID: meeting.id, speakerID: meeting.speakers[0].id, meetings: meetings)
        try await people.enroll(meetingID: meeting.id, speakerID: meeting.speakers[0].id, meetings: meetings)
        let enrolled = try await people.load()
        XCTAssertEqual(enrolled.profiles.count, 1)
        XCTAssertEqual(enrolled.profiles[0].embedding, [0.6, 0.8])
        try await meetings.editText(meeting.id, turnID: meeting.turns[0].id, text: "Edited words")
        try await people.rename(person.id, name: "Renamed")
        let stillEligible = try await people.candidates(fingerprint: "voice-v1", meetings: meetings)
        XCTAssertEqual(stillEligible.count, 1)
        let incompatible = try await people.candidates(fingerprint: "voice-v2", meetings: meetings)
        XCTAssertTrue(incompatible.isEmpty)
        try await meetings.reassignTurn(meeting.id, turnID: meeting.turns[0].id, to: nil)
        let restarted = ParticipantStore(root: root)
        let stale = try await restarted.candidates(fingerprint: "voice-v1", meetings: meetings)
        XCTAssertTrue(stale.isEmpty)
        do { try await restarted.enroll(meetingID: meeting.id, speakerID: meeting.speakers[0].id, meetings: meetings); XCTFail() }
        catch { }
    }

    func testUnconfirmedShortOverlappingAndRegroupedVoicesCannotEnroll() throws {
        let (_, original) = try fixture()
        var meeting = original
        var speaker = meeting.speakers[0]
        XCTAssertNotNil(ParticipantStore.enrollmentReason(meeting: meeting, speaker: speaker))
        speaker.confirmedParticipantID = UUID()
        XCTAssertNil(ParticipantStore.enrollmentReason(meeting: meeting, speaker: speaker))
        meeting.recognitionResult?.intervals.append(.init(speakerKey: "b", start: 5, end: 25))
        XCTAssertNotNil(ParticipantStore.enrollmentReason(meeting: meeting, speaker: speaker))
        speaker.attributionEdited = true
        XCTAssertNotNil(ParticipantStore.enrollmentReason(meeting: original, speaker: speaker))
    }

    func testMissingSourceAbstainsAndDeleteRemovesProfilesWithoutRevival() async throws {
        let (root, meeting) = try fixture()
        let meetings = MeetingStore(root: root), people = ParticipantStore(root: root)
        let person = try await people.add(name: "Alex")
        try await meetings.assignParticipant(meeting.id, speakerID: meeting.speakers[0].id, participantID: person.id, name: person.name)
        try await people.enroll(meetingID: meeting.id, speakerID: meeting.speakers[0].id, meetings: meetings)
        try FileManager.default.removeItem(at: root.appendingPathComponent(".meetings/\(meeting.id.uuidString)/meeting.json"))
        let missing = try await people.candidates(fingerprint: "voice-v1", meetings: meetings)
        XCTAssertTrue(missing.isEmpty)
        try await people.delete(person.id)
        _ = try await people.add(name: "Alex")
        let catalog = try await people.load()
        XCTAssertTrue(catalog.profiles.isEmpty)
        XCTAssertNil(catalog.resolve(person.id))
    }

    func testRejectingSuggestionNeverConfirmsOrTrainsVoice() async throws {
        let (root, meeting) = try fixture()
        let meetings = MeetingStore(root: root), people = ParticipantStore(root: root)
        let person = try await people.add(name: "Alex")
        let speakerID = meeting.speakers[0].id
        try await meetings.setSuggestions(meeting.id, suggestions: [speakerID: .init(participantID: person.id, score: 0.99)])
        do { try await people.enroll(meetingID: meeting.id, speakerID: speakerID, meetings: meetings); XCTFail() }
        catch { }
        try await meetings.dismissSuggestion(meeting.id, speakerID: speakerID)
        let reopened = try await MeetingStore(root: root).load(meeting.id)
        XCTAssertNil(reopened.speakers[0].confirmedParticipantID)
        XCTAssertNil(reopened.speakers[0].suggestedParticipantID)
        XCTAssertNil(reopened.speakers[0].suggestionScore)
        XCTAssertEqual(reopened.turns.map(\.text), meeting.turns.map(\.text))
        XCTAssertEqual(reopened.attributionRevision, meeting.attributionRevision)
        let catalog = try await ParticipantStore(root: root).load()
        XCTAssertTrue(catalog.profiles.isEmpty)
    }

    func testProfileRemovalKeepsParticipantAndFrozenSummarySourceAfterRestart() async throws {
        let (root, meeting) = try fixture()
        let meetings = MeetingStore(root: root), people = ParticipantStore(root: root)
        let person = try await people.add(name: "Alex")
        try await meetings.assignParticipant(meeting.id, speakerID: meeting.speakers[0].id,
            participantID: person.id, name: person.name)
        try await people.enroll(meetingID: meeting.id, speakerID: meeting.speakers[0].id, meetings: meetings)
        let prepared = try await MeetingSummaryInputBuilder.prepare(meeting.id, meetings: meetings, people: people)
        let catalog = try await people.load()
        try await people.removeProfile(XCTUnwrap(catalog.profiles.first).id)
        let restarted = ParticipantStore(root: root)
        let after = try await restarted.load()
        XCTAssertEqual(after.participants.map(\.id), [person.id])
        XCTAssertTrue(after.profiles.isEmpty)
        let candidates = try await restarted.candidates(fingerprint: "voice-v1", meetings: meetings)
        XCTAssertTrue(candidates.isEmpty)
        let restored = try MeetingSummaryInputBuilder.readSnapshot(sourceRef: XCTUnwrap(prepared.sourceRef), root: root, title: "Voice fixture")
        XCTAssertEqual(restored.text, prepared.text)
        let saved = try await meetings.load(meeting.id)
        XCTAssertEqual(saved.speakers[0].confirmedParticipantID, person.id)
    }
}
