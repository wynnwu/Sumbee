import AVFoundation
import XCTest
@testable import SumbeeKit

/// Filesystem scenarios use whole saved documents and audio, including relocation and partial writes.
final class MeetingPersistenceTests: XCTestCase {
    private func fixture() throws -> (root: URL, audio: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("original.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000)!
        buffer.frameLength = 32000
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return (root, url)
    }

    func testMovingLibraryPreservesAudioTranscriptCatalogAndExportReferences() async throws {
        let fixture = try fixture()
        let original = fixture.root.appendingPathComponent("original-library")
        let moved = fixture.root.appendingPathComponent("moved-library")
        let meetings = MeetingStore(root: original), people = ParticipantStore(root: original)
        let person = try await people.add(name: "Alex")
        let imported = try await meetings.importAudio(from: fixture.audio)
        try await meetings.finish(imported.id, recognition: .init(text: "I'll send it.", duration: 2,
            tokens: [.init(text: "I'll send it.", start: 0, end: 2)],
            intervals: [.init(speakerKey: "a", start: 0, end: 2)], embeddings: [:], modelFingerprint: "test", embeddingFingerprint: "test"))
        let ready = try await meetings.load(imported.id)
        try await meetings.assignParticipant(ready.id, speakerID: ready.speakers[0].id, participantID: person.id, name: person.name)
        let prepared = try await MeetingSummaryInputBuilder.prepare(ready.id, meetings: meetings, people: people)
        try FileManager.default.moveItem(at: original, to: moved)
        let reopened = MeetingStore(root: moved), relocatedPeople = ParticipantStore(root: moved)
        let audio = try await reopened.audioURL(ready.id)
        XCTAssertEqual(try MeetingFileDigest.sha256(audio), try MeetingFileDigest.sha256(fixture.audio))
        let names = try await relocatedPeople.resolvedNames()
        XCTAssertEqual(names[person.id], "Alex")
        let snapshot = try MeetingSummaryInputBuilder.readSnapshot(sourceRef: XCTUnwrap(prepared.sourceRef), root: moved, title: "Moved")
        XCTAssertEqual(snapshot.text, prepared.text)
        XCTAssertEqual(snapshot.libraryRoot?.path, moved.path)
        let document = try await reopened.load(ready.id)
        XCTAssertEqual(document.speakers[0].confirmedParticipantID, person.id)
    }

    func testAbandonedStagingIsRemovedButAtomicWriteDebrisDoesNotReplaceSavedRecord() async throws {
        let fixture = try fixture()
        let root = fixture.root.appendingPathComponent("library"), store = MeetingStore(root: fixture.root.appendingPathComponent("library"))
        let document = try await store.importAudio(from: fixture.audio)
        let record = root.appendingPathComponent(".meetings/\(document.id.uuidString)/meeting.json")
        let originalBytes = try Data(contentsOf: record)
        try Data("incomplete write".utf8).write(to: record.appendingPathExtension("tmp"))
        let abandoned = root.appendingPathComponent(".meetings/.import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("partial audio".utf8).write(to: abandoned.appendingPathComponent("audio.wav"))
        try await store.recoverInterruptedJobs()
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertEqual(try Data(contentsOf: record), originalBytes)
        let records = try await store.loadAll()
        XCTAssertEqual(records.map(\.id), [document.id])
    }

    func testCancelledImportLeavesNeitherPublishedJobNorStaging() async throws {
        let fixture = try fixture(), library = fixture.root.appendingPathComponent("library")
        let store = MeetingStore(root: library)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.importAudio(from: fixture.audio)
        }
        do { _ = try await task.value; XCTFail("Cancelled import must fail") } catch is CancellationError { }
        let saved = try await store.loadAll()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent(".meetings").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.audio.path))
    }

    func testOneCorruptMeetingDoesNotHideHealthyMeetingsOrPreventRecovery() async throws {
        let fixture = try fixture(), library = fixture.root.appendingPathComponent("library")
        let store = MeetingStore(root: library)
        let healthy = try await store.importAudio(from: fixture.audio)
        let corrupt = try await store.importAudio(from: fixture.audio)
        try await store.setStatus(healthy.id, status: .diarizing)
        let record = library.appendingPathComponent(".meetings/\(corrupt.id.uuidString)/meeting.json")
        let bad = Data("incomplete external edit".utf8)
        try bad.write(to: record)
        try await store.recoverInterruptedJobs()
        let contents = try await store.libraryContents()
        XCTAssertEqual(contents.documents.map(\.id), [healthy.id])
        XCTAssertEqual(contents.documents.first?.status, .interrupted)
        XCTAssertEqual(contents.unreadableIDs, [corrupt.id])
        XCTAssertEqual(try Data(contentsOf: record), bad)
    }

    func testSymlinkCannotRedirectAudioOrCatalogOutsideLibrary() async throws {
        let fixture = try fixture(), library = fixture.root.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent(".meetings"), withDestinationURL: fixture.root)
        let store = MeetingStore(root: library), people = ParticipantStore(root: library)
        do { _ = try await store.importAudio(from: fixture.audio); XCTFail() } catch { }
        do { _ = try await people.add(name: "Alex"); XCTFail() } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("participants.json").path))
    }
}
