import AVFoundation
import XCTest
@testable import SumbeeKit

final class MeetingStoreTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("input.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
        buffer.frameLength = 16000
        let file = try AVAudioFile(forWriting: audio, settings: format.settings)
        try file.write(from: buffer)
        return (root, audio)
    }

    func testFailedCopyLeavesNoSavedMeetingAndOriginalRemains() async throws {
        let (root, audio) = try fixture()
        let library = root.appendingPathComponent("library")
        let store = MeetingStore(root: library)
        do { _ = try await store.importAudio(from: root.appendingPathComponent("missing.wav")); XCTFail() }
        catch { }
        let meetings = try await store.loadAll()
        XCTAssertTrue(meetings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testDeleteRemovesOnlyAudioAndPreservesTranscriptOriginalAndExports() async throws {
        let (root, audio) = try fixture()
        let original = try Data(contentsOf: audio)
        let store = MeetingStore(root: root)
        let meeting = try await store.importAudio(from: audio)
        let other = try await store.importAudio(from: audio)
        try await store.finish(meeting.id, recognition: .init(text: "Hello", duration: 1,
            tokens: [.init(text: "Hello", start: 0, end: 1)], intervals: [], embeddings: [:],
            modelFingerprint: "test", embeddingFingerprint: "test"))
        let export = try await store.export(meeting.id, participantNames: [:])
        let snapshot = try Data(contentsOf: root.appendingPathComponent(export.path))
        let record = root.appendingPathComponent(".meetings/\(meeting.id)/meeting.json")
        let saved = try Data(contentsOf: record)
        try await store.deleteAudio(meeting.id)
        let remaining = try await MeetingStore(root: root).loadAll()
        XCTAssertEqual(Set(remaining.map(\.id)), [meeting.id, other.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(meeting.audioPath).path))
        XCTAssertEqual(try Data(contentsOf: record), saved)
        XCTAssertEqual(try Data(contentsOf: audio), original)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(export.path)), snapshot)
    }

    func testDeleteRefusesRedirectedMeetingDirectory() async throws {
        let (root, audio) = try fixture()
        let store = MeetingStore(root: root)
        let meeting = try await store.importAudio(from: audio)
        let folder = root.appendingPathComponent(".meetings/\(meeting.id)")
        let redirected = root.appendingPathComponent("keep-this-folder")
        try FileManager.default.moveItem(at: folder, to: redirected)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: redirected)
        do { try await store.deleteAudio(meeting.id); XCTFail("Deletion must not follow a folder alias") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: redirected.appendingPathComponent("meeting.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testDeleteAudioNeverRecursivelyDeletesADirectory() async throws {
        let (root, original) = try fixture()
        let store = MeetingStore(root: root)
        let meeting = try await store.importAudio(from: original)
        let audio = root.appendingPathComponent(meeting.audioPath)
        try FileManager.default.removeItem(at: audio)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: false)
        let retained = audio.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: retained)
        do { try await store.deleteAudio(meeting.id); XCTFail("Only a regular audio file may be deleted") } catch { }
        XCTAssertEqual(try Data(contentsOf: retained), Data("keep".utf8))
    }

    func testImportReloadAndInterruptedRecoveryPreserveAudio() async throws {
        let (root, audio) = try fixture()
        let library = root.appendingPathComponent("library")
        let store = MeetingStore(root: library)
        let meeting = try await store.importAudio(from: audio)
        try await store.setStatus(meeting.id, status: .transcribing)
        let reopened = MeetingStore(root: library)
        try await reopened.recoverInterruptedJobs()
        let recovered = try await reopened.load(meeting.id)
        XCTAssertEqual(recovered.status, .interrupted)
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(recovered.audioPath)), try Data(contentsOf: audio))
    }

    func testNewExportUsesLatestNamesAndOldExportStaysUnchanged() async throws {
        let (root, audio) = try fixture()
        let library = root.appendingPathComponent("library")
        let store = MeetingStore(root: library)
        let meeting = try await store.importAudio(from: audio)
        let raw = MeetingRecognition(text: "Hello.", duration: 1,
            tokens: [.init(text: "Hello.", start: 0, end: 1)],
            intervals: [.init(speakerKey: "a", start: 0, end: 1)], embeddings: [:],
            modelFingerprint: "test", embeddingFingerprint: "test")
        try await store.finish(meeting.id, recognition: raw)
        let ready = try await store.load(meeting.id)
        let participant = UUID()
        try await store.assignParticipant(meeting.id, speakerID: ready.speakers[0].id,
                                          participantID: participant, name: "First name")
        let first = try await store.export(meeting.id, participantNames: [participant: "First name"])
        let second = try await store.export(meeting.id, participantNames: [participant: "Current name"])
        XCTAssertNotEqual(first.path, second.path)
        let oldText = try String(contentsOf: library.appendingPathComponent(first.path), encoding: .utf8)
        let newText = try String(contentsOf: library.appendingPathComponent(second.path), encoding: .utf8)
        XCTAssertTrue(oldText.contains("First name"))
        XCTAssertTrue(newText.contains("Current name"))
        XCTAssertEqual(first.reviewRevision, second.reviewRevision)
        XCTAssertFalse(newText.contains(library.path))
    }

    func testCorruptRecordIsNeverReplacedWithDefaults() async throws {
        let (root, audio) = try fixture()
        let library = root.appendingPathComponent("library")
        let store = MeetingStore(root: library)
        let meeting = try await store.importAudio(from: audio)
        let record = library.appendingPathComponent(".meetings/\(meeting.id.uuidString)/meeting.json")
        let corrupt = Data("not a meeting".utf8)
        try corrupt.write(to: record)
        do { _ = try await store.load(meeting.id); XCTFail() } catch { }
        XCTAssertEqual(try Data(contentsOf: record), corrupt)
    }

    func testSourceSymlinkImportsAudioBytesThatSurviveOriginalRemoval() async throws {
        let (root, original) = try fixture()
        let link = root.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let expected = try Data(contentsOf: original)
        let store = MeetingStore(root: root.appendingPathComponent("library"))
        let meeting = try await store.importAudio(from: link)
        try FileManager.default.removeItem(at: original)
        let retained = try await store.audioURL(meeting.id)
        XCTAssertEqual(try Data(contentsOf: retained), expected)
        XCTAssertEqual(try retained.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, true)
        XCTAssertGreaterThan(try AVAudioFile(forReading: retained).length, 0)
    }
}
