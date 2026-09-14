import AVFoundation
import XCTest
@testable import SumbeeKit

private actor ControlledMeetingTranscriber: MeetingTranscribing {
    private var continuations: [CheckedContinuation<MeetingRecognition, Error>] = []
    private(set) var audioURLs: [URL] = []
    func transcribe(audio: URL, models: VerifiedMeetingModels,
                    stage: @escaping @Sendable (MeetingProcessingStage) -> Void) async throws -> MeetingRecognition {
        audioURLs.append(audio)
        stage(.transcribing)
        // Model an SDK call that cannot be interrupted: cancellation must not overlap the next call.
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func finish(_ result: MeetingRecognition = .init(text: "Hello", duration: 1,
            tokens: [.init(text: "Hello", start: 0, end: 1)],
            intervals: [.init(speakerKey: "a", start: 0, end: 1)], embeddings: [:],
            modelFingerprint: "test", embeddingFingerprint: "test")) {
        continuations.removeFirst().resume(returning: result)
    }
}

@MainActor
final class MeetingProcessingTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func audio(in root: URL, seconds: Int = 1) throws -> URL {
        let url = root.appendingPathComponent("input.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(16000 * seconds))!
        buffer.frameLength = buffer.frameCapacity
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return url
    }

    private func models(in root: URL) async throws -> VerifiedMeetingModels {
        let source = root.appendingPathComponent("model")
        try Data("model".utf8).write(to: source)
        var manifest = MeetingModelManifest(schemaVersion: 1, id: "test", sdkRevision: "test", embeddingFingerprint: "test",
            repositories: [], assets: [.init(path: "test.bin", url: URL(string: "https://huggingface.co/test")!,
                byteCount: 5, sha256: try MeetingFileDigest.sha256(source))])
        manifest.recognitionPolicy = .init(id: "test", embeddingFingerprint: "test", minimumScore: 0.75,
            separation: 0.12, calibrationStatus: "test")
        return try await MeetingModelManager(root: root.appendingPathComponent("models"), manifest: manifest)
            .install(download: { _ in source })
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected queue state was not reached")
        throw MeetingDataError.invalidRecord
    }

    func testCancellationRejectsLateResultAndNextJobWaitsAcrossLibrarySwitch() async throws {
        let firstRoot = try root(), secondRoot = try root()
        let store = MeetingStore(root: firstRoot)
        let source = try audio(in: firstRoot)
        let first = try await store.importAudio(from: source), second = try await store.importAudio(from: source)
        let verified = try await models(in: firstRoot)
        let transcriber = ControlledMeetingTranscriber()
        let state = MeetingProcessingState(transcriber: transcriber, loadModels: { verified })
        await state.selectRoot(firstRoot)
        await state.enqueue(first.id)
        try await eventually { await transcriber.audioURLs.count == 1 }
        await state.enqueue(second.id)
        let cancellationStart = Date()
        await state.cancel(first.id)
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStart), 2)
        let cancelled = try await store.load(first.id)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertTrue(state.finishingCancelledCall)
        await state.selectRoot(secondRoot)
        let startedBeforeReturn = await transcriber.audioURLs.count
        XCTAssertEqual(startedBeforeReturn, 1)
        await transcriber.finish()
        try await eventually { await transcriber.audioURLs.count == 2 }
        await transcriber.finish()
        try await eventually { !state.hasWork }
        let finalFirst = try await store.load(first.id), finalSecond = try await store.load(second.id)
        XCTAssertEqual(finalFirst.status, .cancelled)
        XCTAssertTrue(finalFirst.turns.isEmpty)
        XCTAssertEqual(finalSecond.status, .ready)
        XCTAssertTrue(state.documents.isEmpty)
        let paths = await transcriber.audioURLs
        XCTAssertTrue(paths.allSatisfy { $0.path.hasPrefix(firstRoot.resolvingSymlinksInPath().path + "/") })
    }

    func testDeletionWaitsForQueueAndCancellationAndRejectsOldLibraryConfirmation() async throws {
        let firstRoot = try root(), secondRoot = try root()
        let store = MeetingStore(root: firstRoot)
        let source = try audio(in: firstRoot)
        let first = try await store.importAudio(from: source), second = try await store.importAudio(from: source)
        let verified = try await models(in: firstRoot)
        let transcriber = ControlledMeetingTranscriber()
        let state = MeetingProcessingState(transcriber: transcriber, loadModels: { verified })
        await state.selectRoot(firstRoot)
        let selectedRoot = try XCTUnwrap(state.root)
        await state.enqueue(first.id)
        try await eventually { await transcriber.audioURLs.count == 1 }
        await state.enqueue(second.id)
        let activeDeleted = await state.deleteAudio(first.id, root: selectedRoot)
        let queuedDeleted = await state.deleteAudio(second.id, root: selectedRoot)
        XCTAssertFalse(activeDeleted)
        XCTAssertFalse(queuedDeleted)
        await state.cancel(second.id)
        await state.cancel(first.id)
        let stoppingDeleted = await state.deleteAudio(first.id, root: selectedRoot)
        XCTAssertFalse(stoppingDeleted)
        await transcriber.finish()
        try await eventually { !state.hasWork }
        let deleted = await state.deleteAudio(first.id, root: selectedRoot)
        XCTAssertTrue(deleted)
        XCTAssertFalse(state.hasAudio(first.id))
        await state.enqueue(first.id)
        XCTAssertFalse(state.isScheduled(first.id))
        await state.selectRoot(secondRoot)
        let wrongLibraryDeleted = await state.deleteAudio(second.id, root: selectedRoot)
        XCTAssertFalse(wrongLibraryDeleted)
        let remaining = try await store.loadAll()
        XCTAssertEqual(Set(remaining.map(\.id)), [first.id, second.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMissingModelsWaitsWithoutCallingTranscriberOrRequiringKey() async throws {
        let root = try root()
        let store = MeetingStore(root: root)
        let meeting = try await store.importAudio(from: audio(in: root))
        let transcriber = ControlledMeetingTranscriber()
        let state = MeetingProcessingState(transcriber: transcriber, loadModels: { throw MeetingModelError.notInstalled })
        await state.selectRoot(root)
        await state.enqueue(meeting.id)
        try await eventually { !state.hasWork }
        let saved = try await store.load(meeting.id)
        XCTAssertEqual(saved.status, .awaitingModels)
        let calls = await transcriber.audioURLs.count
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(state.modelsReady)
    }

    func testMixedFileRoutingKeepsAudioIndependentOfCloudDocuments() {
        let root = URL(fileURLWithPath: "/tmp")
        let classified = MeetingFileRouting.classify(["voice.M4A", "notes.md", "memo.pdf", "song.mp3", "archive.zip"].map { root.appendingPathComponent($0) })
        XCTAssertEqual(classified.audio.map(\.lastPathComponent), ["voice.M4A", "song.mp3"])
        XCTAssertEqual(classified.documents.map(\.lastPathComponent), ["notes.md", "memo.pdf"])
        XCTAssertEqual(classified.unsupported.map(\.lastPathComponent), ["archive.zip"])
    }

    func testWaitingRecordingCanStartAfterRestartAndQueuedRecordingCanCancel() async throws {
        let root = try root()
        let store = MeetingStore(root: root)
        let source = try audio(in: root)
        let first = try await store.importAudio(from: source)
        let second = try await store.importAudio(from: source)
        try await store.setStatus(first.id, status: .awaitingModels)
        let verified = try await models(in: root)
        let transcriber = ControlledMeetingTranscriber()
        let state = MeetingProcessingState(transcriber: transcriber, loadModels: { verified })
        await state.selectRoot(root)
        await state.checkModels()
        let waiting = try await store.load(first.id)
        XCTAssertTrue(state.canStart(waiting))
        await state.enqueue(first.id)
        try await eventually { await transcriber.audioURLs.count == 1 }
        await state.enqueue(second.id)
        XCTAssertTrue(state.isScheduled(second.id))
        XCTAssertFalse(state.canStart(second))
        await state.cancel(second.id)
        XCTAssertFalse(state.isScheduled(second.id))
        let saved = try await store.load(second.id)
        XCTAssertEqual(saved.status, .cancelled)
        await transcriber.finish()
        try await eventually { !state.hasWork }
        let calls = await transcriber.audioURLs.count
        XCTAssertEqual(calls, 1)
    }

    func testBatchContinuesInOrderAfterUnreadableAudioAndLibrarySwitch() async throws {
        let firstRoot = try root(), nextRoot = try root()
        let source = try audio(in: firstRoot)
        let first = firstRoot.appendingPathComponent("first.wav")
        let last = firstRoot.appendingPathComponent("last.wav")
        try FileManager.default.copyItem(at: source, to: first)
        try FileManager.default.copyItem(at: source, to: last)
        let bad = firstRoot.appendingPathComponent("bad.wav")
        try Data("not audio".utf8).write(to: bad)
        let verified = try await models(in: firstRoot)
        let transcriber = ControlledMeetingTranscriber()
        let state = MeetingProcessingState(transcriber: transcriber, loadModels: { verified })
        await state.selectRoot(firstRoot)
        state.importAudio([first, bad, last])
        await state.selectRoot(nextRoot)
        try await eventually { await transcriber.audioURLs.count == 1 }
        await transcriber.finish()
        try await eventually { await transcriber.audioURLs.count == 2 }
        await transcriber.finish()
        try await eventually { !state.hasWork }
        let records = try await MeetingStore(root: firstRoot).loadAll()
        XCTAssertEqual(Set(records.map(\.originalFilename)), ["first.wav", "last.wav"])
        XCTAssertTrue(records.allSatisfy { $0.status == .ready })
        let paths = await transcriber.audioURLs
        let orderedNames = paths.compactMap { url in records.first { url.path.contains($0.id.uuidString) }?.originalFilename }
        XCTAssertEqual(orderedNames, ["first.wav", "last.wav"])
        XCTAssertTrue(state.documents.isEmpty)
        XCTAssertTrue(state.error?.contains("bad.wav") == true)
    }

    func testModelSetupResumesWaitingRecordingsInImportOrder() async throws {
        let root = try root()
        let store = MeetingStore(root: root), source = try audio(in: root)
        let first = try await store.importAudio(from: source)
        let second = try await store.importAudio(from: source)
        try await store.setStatus(first.id, status: .awaitingModels)
        try await store.setStatus(second.id, status: .awaitingModels)
        let verified = try await models(in: root)
        let transcriber = ControlledMeetingTranscriber()
        let state = MeetingProcessingState(transcriber: transcriber, loadModels: { verified })
        await state.selectRoot(root)
        await state.resumeWaitingForModels()
        try await eventually { await transcriber.audioURLs.count == 1 }
        await transcriber.finish()
        try await eventually { await transcriber.audioURLs.count == 2 }
        await transcriber.finish()
        try await eventually { !state.hasWork }
        let paths = await transcriber.audioURLs
        XCTAssertTrue(paths[0].path.contains(first.id.uuidString))
        XCTAssertTrue(paths[1].path.contains(second.id.uuidString))
    }

    func testSuggestionsRequireClearSpeechInTheNewRecording() async throws {
        let root = try root(), library = try self.root()
        let store = MeetingStore(root: library), people = ParticipantStore(root: library)
        let audio = try audio(in: root, seconds: 30)
        let source = try await store.importAudio(from: audio)
        let clear = MeetingRecognition(text: "Hello", duration: 30,
            tokens: [.init(text: "Hello", start: 0, end: 1)],
            intervals: [.init(speakerKey: "a", start: 0, end: 20)], embeddings: ["a": [1, 0]],
            modelFingerprint: "test", embeddingFingerprint: "test")
        try await store.finish(source.id, recognition: clear)
        let ready = try await store.load(source.id)
        let person = try await people.add(name: "Alex")
        try await store.assignParticipant(source.id, speakerID: ready.speakers[0].id, participantID: person.id, name: person.name)
        try await people.enroll(meetingID: source.id, speakerID: ready.speakers[0].id, meetings: store)
        let verified = try await models(in: root)
        let transcriber = ControlledMeetingTranscriber()
        let state = MeetingProcessingState(transcriber: transcriber,
            manager: MeetingModelManager(manifest: verified.manifest), loadModels: { verified })
        await state.selectRoot(library)
        var short = clear
        short.intervals = [.init(speakerKey: "a", start: 0, end: 1)]
        var overlap = clear
        overlap.intervals.append(.init(speakerKey: "b", start: 0, end: 20))
        for (index, result) in [short, overlap, clear].enumerated() {
            let query = try await store.importAudio(from: audio)
            await state.enqueue(query.id)
            try await eventually { await transcriber.audioURLs.count == index + 1 }
            await transcriber.finish(result)
            try await eventually { !state.hasWork }
            let saved = try await store.load(query.id)
            let suggestions = saved.speakers.compactMap(\.suggestedParticipantID)
            if index == 2 { XCTAssertEqual(suggestions, [person.id]) }
            else { XCTAssertTrue(suggestions.isEmpty, "Short or fully overlapping speech must abstain") }
            XCTAssertTrue(saved.speakers.allSatisfy { $0.confirmedParticipantID == nil })
        }
        let catalog = try await people.load()
        XCTAssertEqual(catalog.profiles.count, 1)
    }
}
