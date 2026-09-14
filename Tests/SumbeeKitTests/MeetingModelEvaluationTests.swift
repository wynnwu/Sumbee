import XCTest
import Darwin
import AVFoundation
@testable import SumbeeKit

/// Opt-in local evaluation. Audio and recognized content are never written to the repository.
final class MeetingModelEvaluationTests: XCTestCase {
    func testCancellationDuringRealImportRemovesStagingAndSavedJob() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUMBEE_IMPORT_CANCEL_AUDIO"] else {
            throw XCTSkip("Set a substantial local recording to cancel after its staged copy starts.")
        }
        let original = URL(fileURLWithPath: path)
        let hash = try MeetingFileDigest.sha256(original)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MeetingStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task { try await store.importAudio(from: original) }
        let storage = root.appendingPathComponent(".meetings")
        let deadline = Date().addingTimeInterval(10)
        var stagedCopyStarted = false
        while Date() < deadline {
            let directories = (try? FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)) ?? []
            stagedCopyStarted = directories.contains { directory in
                directory.lastPathComponent.hasPrefix(".import-") &&
                FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio.\(original.pathExtension.lowercased())").path)
            }
            if stagedCopyStarted { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        task.cancel()
        XCTAssertTrue(stagedCopyStarted, "The supplied recording must allow observation of the in-progress copy")
        do { _ = try await task.value; XCTFail("Cancellation during staging must not publish a saved job") }
        catch is CancellationError { }
        let saved = try await store.loadAll()
        XCTAssertTrue(saved.isEmpty)
        let remaining = try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(try MeetingFileDigest.sha256(original), hash)
    }

    func testSubsecondSpeechKeepsWordsWithoutSpeakerClaims() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SUMBEE_SHORT_AUDIO"], let models = env["SUMBEE_MEETING_MODELS"] else {
            throw XCTSkip("Set a sub-second local speech clip and model paths for short-input evaluation.")
        }
        let verified = try await MeetingModelManager(manifest: MeetingModelManifest.bundled())
            .verify(directory: URL(fileURLWithPath: models))
        let result = try await FluidAudioTranscriber().transcribe(audio: URL(fileURLWithPath: path),
            models: verified, stage: { _ in })
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertLessThan(result.duration, 1)
        XCTAssertFalse(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(result.intervals.isEmpty)
        XCTAssertTrue(result.embeddings.isEmpty)
        let assembled = TranscriptAssembler.assemble(result)
        XCTAssertEqual(assembled.turns.map(\.text).joined(), result.text)
        XCTAssertTrue(assembled.speakers.allSatisfy { $0.clusterKeys.isEmpty })
    }

    func testSupportedFormatsImportReviewAndReopenOffline() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SUMBEE_FORMAT_FIXTURES"], let models = env["SUMBEE_MEETING_MODELS"] else {
            throw XCTSkip("Set local format fixtures and model paths for the supported-format evaluation.")
        }
        let verified = try await MeetingModelManager(manifest: MeetingModelManifest.bundled())
            .verify(directory: URL(fileURLWithPath: models))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        for ext in ["wav", "mp3", "m4a"] {
            let original = URL(fileURLWithPath: path).appendingPathComponent("sample.\(ext)")
            let digest = try MeetingFileDigest.sha256(original)
            let meeting = try await store.importAudio(from: original)
            let audio = try await store.audioURL(meeting.id)
            let result = try await FluidAudioTranscriber().transcribe(audio: audio, models: verified, stage: { _ in })
            XCTAssertFalse(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ext)
            try await store.finish(meeting.id, recognition: result)
            let ready = try await store.load(meeting.id)
            XCTAssertEqual(ready.turns.map(\.text).joined(), result.text, ext)
            let first = try XCTUnwrap(ready.turns.first)
            try await store.editText(meeting.id, turnID: first.id, text: "Reviewed paragraph.")
            let reopened = MeetingStore(root: root)
            let saved = try await reopened.load(meeting.id)
            XCTAssertEqual(saved.status, .ready)
            XCTAssertEqual(saved.turns.first?.text, "Reviewed paragraph.")
            XCTAssertEqual(saved.reviewRevision, ready.reviewRevision + 1)
            XCTAssertEqual(saved.attributionRevision, ready.attributionRevision)
            let retained = try await reopened.audioURL(meeting.id)
            XCTAssertEqual(try MeetingFileDigest.sha256(retained), digest)
            XCTAssertEqual(try MeetingFileDigest.sha256(original), digest)
            let reader = try AVAudioFile(forReading: retained)
            XCTAssertGreaterThan(reader.length, 0)
            let export = try await reopened.export(meeting.id, participantNames: [:])
            let text = try String(contentsOf: root.appendingPathComponent(export.path), encoding: .utf8)
            XCTAssertTrue(text.contains("Reviewed paragraph."))
            print("Supported format passed: \(ext), seconds=\(saved.durationSeconds), turns=\(saved.turns.count)")
        }
    }

    func testExplicitModelDownloadAndActivation() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUMBEE_MODEL_INSTALL_ROOT"] else {
            throw XCTSkip("Set an isolated installation root to exercise the explicit network downloader.")
        }
        let root = URL(fileURLWithPath: path)
        let manager = MeetingModelManager(root: root, manifest: try MeetingModelManifest.bundled())
        let installed = try await manager.install()
        let reopened = try await manager.verifiedInstallation()
        XCTAssertEqual(installed.directory, reopened.directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("active.json").path))
        print("Model installation verified: files=\(installed.manifest.assets.count), bytes=\(installed.manifest.downloadBytes)")
    }

    @MainActor
    func testRealInferenceCancellationAcknowledgesBeforeSDKReturns() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let models = env["SUMBEE_MEETING_MODELS"], let audio = env["SUMBEE_MEETING_AUDIO"] else {
            throw XCTSkip("Set local model/audio paths to validate cancellation during real inference.")
        }
        let manager = MeetingModelManager(manifest: try MeetingModelManifest.bundled())
        let verified = try await manager.verify(directory: URL(fileURLWithPath: models))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let meeting = try await store.importAudio(from: URL(fileURLWithPath: audio))
        let state = MeetingProcessingState(manager: manager, loadModels: { verified })
        await state.selectRoot(root)
        await state.enqueue(meeting.id)
        let deadline = Date().addingTimeInterval(30)
        while state.stage != .transcribing && state.hasWork && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(state.stage, .transcribing)
        let start = Date()
        await state.cancel(meeting.id)
        let acknowledgment = Date().timeIntervalSince(start)
        XCTAssertLessThan(acknowledgment, 2)
        while state.hasWork && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(state.hasWork, "The SDK call should release the queue after returning")
        let saved = try await store.load(meeting.id)
        XCTAssertEqual(saved.status, .cancelled)
        XCTAssertTrue(saved.turns.isEmpty)
        print("Real cancellation: acknowledgmentSeconds=\(acknowledgment), queueReleasedSeconds=\(Date().timeIntervalSince(start))")
    }

    func testSilentRecordingsDoNotInventSpeech() async throws {
        guard let models = ProcessInfo.processInfo.environment["SUMBEE_MEETING_MODELS"] else {
            throw XCTSkip("Set the local model folder to evaluate silence.")
        }
        let verified = try await MeetingModelManager(manifest: MeetingModelManifest.bundled())
            .verify(directory: URL(fileURLWithPath: models))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for seconds in [0.25, 2.0] {
            let url = root.appendingPathComponent("silence-\(seconds).wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let count = AVAudioFrameCount(seconds * 16000)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            buffer.frameLength = count
            buffer.floatChannelData![0].initialize(repeating: 0, count: Int(count))
            do { let writer = try AVAudioFile(forWriting: url, settings: format.settings); try writer.write(from: buffer) }
            let result = try await FluidAudioTranscriber().transcribe(audio: url, models: verified, stage: { _ in })
            XCTAssertTrue(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(TranscriptAssembler.assemble(result).turns.isEmpty)
        }
    }

    func testSplitRecordings() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let fixtures = env["SUMBEE_MEETING_SPLIT_FIXTURES"], let models = env["SUMBEE_MEETING_MODELS"],
              let output = env["SUMBEE_MEETING_SPLIT_RESULTS"] else {
            throw XCTSkip("Set split-fixture/models/results folders to evaluate the local clips.")
        }
        let folder = URL(fileURLWithPath: fixtures), results = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        let manifest = try MeetingModelManifest.bundled()
        let verified = try await MeetingModelManager(manifest: manifest).verify(directory: URL(fileURLWithPath: models))
        let policy = try XCTUnwrap(manifest.recognitionPolicy)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 6)
        var enrollment: [ParticipantCandidate] = []
        for file in files {
            let start = Date()
            let recognition = try await FluidAudioTranscriber().transcribe(audio: file, models: verified, stage: { _ in })
            let assembled = TranscriptAssembler.assemble(recognition)
            XCTAssertEqual(assembled.turns.map(\.text).joined(), recognition.text)
            XCTAssertFalse(recognition.text.isEmpty)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(recognition).write(to: results.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".json"), options: .atomic)
            var document = MeetingDocument(title: file.deletingPathExtension().lastPathComponent,
                originalFilename: file.lastPathComponent, audioSHA256: try MeetingFileDigest.sha256(file),
                durationSeconds: recognition.duration)
            document.status = .ready
            document.speakers = assembled.speakers
            document.turns = assembled.turns
            document.recognitionResult = recognition
            let eligible = assembled.speakers.compactMap { speaker -> [Float]? in
                guard ParticipantStore.voiceSampleReason(meeting: document, speaker: speaker) == nil,
                      let key = speaker.clusterKeys.first else { return nil }
                return recognition.embeddings[key]
            }
            if file.lastPathComponent.contains("enrollment") {
                enrollment = eligible.map { .init(participantID: UUID(), embedding: $0) }
            }
            let suggestions = eligible.compactMap {
                ParticipantMatcher.suggest(embedding: $0, candidates: enrollment,
                    minimumScore: policy.minimumScore, separation: policy.separation)
            }
            // This measures cross-clip candidate coverage only. No human identity labels exist,
            // so it must never be reported as precision or speaker-identification accuracy.
            print("Split evaluation: file=\(file.lastPathComponent), seconds=\(recognition.duration), elapsed=\(Date().timeIntervalSince(start)), clusters=\(recognition.embeddings.count), eligible=\(eligible.count), suggested=\(suggestions.count), turns=\(assembled.turns.count)")
        }
    }

    func testPersistAndReopenRecognizedMeeting() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let audio = env["SUMBEE_MEETING_AUDIO"], let resultPath = env["SUMBEE_MEETING_RESULT"],
              let library = env["SUMBEE_MEETING_REVIEW_LIBRARY"] else {
            throw XCTSkip("Set local audio/result/review-library paths to validate saved real-model output.")
        }
        let recognition = try JSONDecoder().decode(MeetingRecognition.self, from: Data(contentsOf: URL(fileURLWithPath: resultPath)))
        let root = URL(fileURLWithPath: library)
        let store = MeetingStore(root: root)
        let document = try await store.importAudio(from: URL(fileURLWithPath: audio))
        try await store.finish(document.id, recognition: recognition)
        let reopened = try await MeetingStore(root: root).load(document.id)
        XCTAssertEqual(reopened.turns.map(\.text).joined(), recognition.text)
        XCTAssertEqual(reopened.status, .ready)
        XCTAssertEqual(reopened.audioSHA256, try MeetingFileDigest.sha256(URL(fileURLWithPath: audio)))
        let export = try await store.export(document.id, participantNames: [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(export.path).path))
    }

    func testAnnotatedSpeakerRangesFromSavedResult() throws {
        let env = ProcessInfo.processInfo.environment
        guard let replay = env["SUMBEE_DIARIZATION_REPLAY"], let audio = env["SUMBEE_MEETING_AUDIO"] else {
            throw XCTSkip("Set local result/audio paths to replay the user-labelled speaker ranges.")
        }
        let result = try JSONDecoder().decode(MeetingRecognition.self,
            from: Data(contentsOf: URL(fileURLWithPath: replay)))
        try assertMarketingSpeakerReferences(result, audio: URL(fileURLWithPath: audio))
    }

    /// Sparse identity checks, not a full-meeting DER score. Labels came from the user;
    /// neither these ranges nor the known speaker count are inputs to inference.
    private func assertMarketingSpeakerReferences(_ result: MeetingRecognition, audio: URL) throws {
        let digest = try MeetingFileDigest.sha256(audio)
        let expectedDigest = "04f48fca196bc1ed6873028f9af04fbdb2904731676c36046f20fffa36cf1fdb"
        XCTAssertEqual(digest, expectedDigest, "These references require the annotated marketing recording")
        guard digest == expectedDigest else { return }
        let references: [(person: Int, start: Double, end: Double)] = [
            (1, 70, 90), (1, 151, 170),
            (2, 106, 113), (2, 120, 130), (2, 340, 355),
            (3, 1948, 1956)
        ]
        var identities: [Int: String] = [:]
        for reference in references {
            var durations: [String: Double] = [:]
            for interval in result.intervals {
                let overlap = max(0, min(reference.end, interval.end) - max(reference.start, interval.start))
                if overlap > 0 { durations[interval.speakerKey, default: 0] += overlap }
            }
            let winner = try XCTUnwrap(durations.max { $0.value < $1.value },
                                      "Missing person \(reference.person) at \(reference.start)s")
            let detected = durations.values.reduce(0, +)
            // Approximate human ranges may include pauses; require substantial coverage
            // while checking that all detected speech has one consistent attribution.
            XCTAssertGreaterThanOrEqual(winner.value / (reference.end - reference.start), 0.8)
            XCTAssertEqual(winner.value, detected, accuracy: 0.001,
                           "Mixed identities within person \(reference.person)'s reference range")
            if let previous = identities[reference.person] {
                XCTAssertEqual(winner.key, previous, "The same person must retain one identity across ranges")
            }
            identities[reference.person] = winner.key
            print("Speaker reference: person=\(reference.person), range=\(reference.start)-\(reference.end), group=\(winner.key), detectedSeconds=\(detected)")
        }
        XCTAssertEqual(Set(identities.values).count, 3, "The three reference people must remain distinct")
        // The user identified this ending as all three people talking over one another.
        // It may remain unattributed, but it must not establish a fourth identity.
        let overlappingGroups = Set(result.intervals.filter { $0.start < 2026 && $0.end > 2022 }.map(\.speakerKey))
        XCTAssertTrue(overlappingGroups.isSubset(of: Set(identities.values)),
                      "The known three-person overlap must not invent a new speaker identity")
    }

    func testLocalRecording() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let audio = env["SUMBEE_MEETING_AUDIO"], let models = env["SUMBEE_MEETING_MODELS"],
              let output = env["SUMBEE_MEETING_RESULT"] else {
            throw XCTSkip("Set local audio/models/result paths to run real-model evaluation.")
        }
        let manifest = try MeetingModelManifest.bundled()
        let manager = MeetingModelManager(root: URL(fileURLWithPath: models), manifest: manifest)
        let verified = try await manager.verify(directory: URL(fileURLWithPath: models))
        let start = Date()
        let result = try await FluidAudioTranscriber().transcribe(
            audio: URL(fileURLWithPath: audio), models: verified,
            stage: { print("Meeting stage: \($0.rawValue)") })
        let elapsed = Date().timeIntervalSince(start)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertFalse(result.text.isEmpty, "The supplied speech fixture should produce recognized text")
        XCTAssertFalse(result.intervals.isEmpty, "The supplied meeting should produce speaker intervals")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: URL(fileURLWithPath: output), options: .atomic)
        if env["SUMBEE_MEETING_REFERENCE"] == "marketing" {
            try assertMarketingSpeakerReferences(result, audio: URL(fileURLWithPath: audio))
        }
        if let expected = env["SUMBEE_MEETING_EXPECTED_SPEAKERS"].flatMap(Int.init) {
            XCTAssertEqual(Set(result.intervals.map(\.speakerKey)).count, expected,
                           "Known meeting voices must not collapse into one group or fragment into extra groups")
        }
        let assembled = TranscriptAssembler.assemble(result)
        XCTAssertEqual(assembled.turns.map(\.text).joined(), result.text)
        print("Meeting evaluation: duration=\(result.duration), elapsed=\(elapsed), peakResidentBytes=\(usage.ru_maxrss), tokens=\(result.tokens.count), clusters=\(result.embeddings.count), turns=\(assembled.turns.count)")
    }
}
