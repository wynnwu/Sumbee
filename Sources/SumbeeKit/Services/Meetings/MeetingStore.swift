import AVFoundation
import Foundation

/// Serial owner of a library's meeting documents, staged audio imports, edits, and frozen exports.
actor MeetingStore {
    let root: URL
    private let fm = FileManager.default
    init(root: URL) { self.root = MeetingLibraryPath.directory(root) }

    func importAudio(from original: URL) throws -> MeetingDocument {
        let ext = original.pathExtension.lowercased()
        guard ["wav", "mp3", "m4a"].contains(ext) else { throw MeetingTranscriptionError.invalidAudio }
        try Task.checkCancellation()
        let storage = try safeURL(".meetings")
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
        let id = UUID()
        let staging = storage.appendingPathComponent(".import-\(id.uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let audio = staging.appendingPathComponent("audio.\(ext)")
        // Retain the bytes, not a symbolic link back to a recording outside the library.
        try fm.copyItem(at: original.resolvingSymlinksInPath(), to: audio)
        try Task.checkCancellation()
        let hash = try MeetingFileDigest.sha256(audio)
        guard hash == (try MeetingFileDigest.sha256(original)) else { throw MeetingTranscriptionError.invalidAudio }
        let reader = try AVAudioFile(forReading: audio)
        let format = reader.processingFormat
        let duration = Double(reader.length) / format.sampleRate
        guard duration.isFinite, duration >= 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536) else {
            throw MeetingTranscriptionError.invalidAudio
        }
        // Decode through EOF now, so a truncated compressed stream never becomes a saved job.
        var decodedFrames: AVAudioFramePosition = 0
        // Some codecs throw a nilError for a read at EOF; framePosition itself can raise an
        // Objective-C exception. Count decoded frames and bound every read by the file length.
        while decodedFrames < reader.length {
            try Task.checkCancellation()
            let remaining = AVAudioFrameCount(min(65536, reader.length - decodedFrames))
            try reader.read(into: buffer, frameCount: remaining)
            guard buffer.frameLength > 0 else { throw MeetingTranscriptionError.invalidAudio }
            decodedFrames += AVAudioFramePosition(buffer.frameLength)
        }
        guard reader.length == 0 || decodedFrames > 0 else { throw MeetingTranscriptionError.invalidAudio }
        var meeting = MeetingDocument(id: id, title: original.deletingPathExtension().lastPathComponent,
            originalFilename: original.lastPathComponent, audioSHA256: hash, durationSeconds: duration)
        if reader.length == 0 { meeting.status = .noSpeech }
        try meeting.validate()
        try encoder().encode(meeting).write(to: staging.appendingPathComponent("meeting.json"), options: .atomic)
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: storage.appendingPathComponent(id.uuidString, isDirectory: true))
        return meeting
    }

    func load(_ id: UUID) throws -> MeetingDocument {
        let data = try Data(contentsOf: safeURL(".meetings/\(id.uuidString)/meeting.json"))
        let document = try JSONDecoder().decode(MeetingDocument.self, from: data)
        try document.validate()
        guard document.id == id, document.audioPath.hasPrefix(".meetings/\(id.uuidString)/") else {
            throw MeetingDataError.invalidRecord
        }
        return document
    }

    func loadAll() throws -> [MeetingDocument] {
        let storage = try safeURL(".meetings")
        guard fm.fileExists(atPath: storage.path) else { return [] }
        return try fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
            .map { try load($0) }.sorted { $0.createdAt > $1.createdAt }
    }

    func libraryContents() throws -> (documents: [MeetingDocument], unreadableIDs: [UUID], audioIDs: Set<UUID>) {
        let storage = try safeURL(".meetings")
        guard fm.fileExists(atPath: storage.path) else { return ([], [], []) }
        var documents: [MeetingDocument] = [], unreadable: [UUID] = []
        for entry in try fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: entry.lastPathComponent) else { continue }
            do { documents.append(try load(id)) }
            catch { unreadable.append(id) }
        }
        let audioIDs = Set(documents.compactMap { document -> UUID? in
            guard let url = try? safeURL(document.audioPath), fm.fileExists(atPath: url.path) else { return nil }
            return document.id
        })
        return (documents.sorted { $0.createdAt > $1.createdAt }, unreadable, audioIDs)
    }

    /// Call once when opening a library, never while this store's queue is processing.
    func recoverInterruptedJobs() throws {
        let storage = try safeURL(".meetings")
        guard fm.fileExists(atPath: storage.path) else { return }
        for entry in try fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil) {
            if entry.lastPathComponent.hasPrefix(".import-") {
                try fm.removeItem(at: entry)
            } else if let id = UUID(uuidString: entry.lastPathComponent) {
                // Report unreadable records in the library scan; recover the healthy jobs too.
                guard var document = try? load(id) else { continue }
                if document.status.isProcessing {
                    document.status = .interrupted
                    document.failureMessage = "Processing was interrupted. Retry to continue from the saved audio."
                    try save(document)
                }
            }
        }
    }

    func audioURL(_ id: UUID) throws -> URL {
        let url = try safeURL(load(id).audioPath)
        guard fm.fileExists(atPath: url.path) else { throw MeetingDataError.missingAudio }
        return url
    }

    /// Remove only the retained audio bytes. Meeting metadata and voice profiles remain valid.
    func deleteAudio(_ id: UUID) throws {
        let document = try load(id)
        guard !document.status.isProcessing else { throw MeetingTranscriptionError.busy }
        let audio = try safeURL(document.audioPath)
        let expected = root.resolvingSymlinksInPath().appendingPathComponent(document.audioPath).standardizedFileURL
        // Do not follow a redirected folder or audio symlink to another retained file.
        guard audio.path == expected.path,
              audio.lastPathComponent == "audio.\(URL(fileURLWithPath: document.originalFilename).pathExtension.lowercased())" else {
            throw MeetingDataError.invalidRecord
        }
        if fm.fileExists(atPath: audio.path) {
            guard try audio.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw MeetingDataError.invalidRecord
            }
            try fm.removeItem(at: audio)
        }
    }

    func setStatus(_ id: UUID, status: MeetingStatus, message: String? = nil) throws {
        var document = try load(id)
        guard document.status != .ready else { throw MeetingDataError.invalidRecord }
        document.status = status
        document.failureMessage = message
        try save(document)
    }

    func setExpectedParticipant(_ id: UUID, participantID: UUID, included: Bool) throws {
        var document = try load(id)
        if included { document.expectedParticipantIDs.insert(participantID) }
        else { document.expectedParticipantIDs.remove(participantID) }
        try save(document)
    }

    func setSuggestions(_ id: UUID, suggestions: [UUID: ParticipantSuggestion]) throws {
        var document = try load(id)
        for index in document.speakers.indices where document.speakers[index].confirmedParticipantID == nil {
            let suggestion = suggestions[document.speakers[index].id]
            document.speakers[index].suggestedParticipantID = suggestion?.participantID
            document.speakers[index].suggestionScore = suggestion?.score
        }
        try save(document)
    }

    func dismissSuggestion(_ id: UUID, speakerID: UUID) throws {
        var document = try load(id)
        guard let index = document.speakers.firstIndex(where: { $0.id == speakerID }) else { throw MeetingDataError.invalidRecord }
        document.speakers[index].suggestedParticipantID = nil
        document.speakers[index].suggestionScore = nil
        try save(document)
    }

    func finish(_ id: UUID, recognition: MeetingRecognition) throws {
        var document = try load(id)
        guard ![.ready, .cancelled].contains(document.status) else { throw MeetingDataError.invalidRecord }
        let assembled = TranscriptAssembler.assemble(recognition)
        document.turns = assembled.turns
        document.speakers = assembled.speakers
        document.recognitionResult = recognition
        document.modelFingerprint = recognition.modelFingerprint
        document.status = recognition.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .noSpeech : .ready
        document.failureMessage = nil
        try save(document)
    }

    func editText(_ id: UUID, turnID: UUID, text: String) throws {
        try edit(id) { document in
            guard let index = document.turns.firstIndex(where: { $0.id == turnID }) else { throw MeetingDataError.invalidRecord }
            document.turns[index].text = text
        }
    }

    func assignParticipant(_ id: UUID, speakerID: UUID, participantID: UUID?, name: String?) throws {
        try edit(id, attribution: true) { document in
            guard let index = document.speakers.firstIndex(where: { $0.id == speakerID }) else { throw MeetingDataError.invalidRecord }
            document.speakers[index].confirmedParticipantID = participantID
            document.speakers[index].displayNameSnapshot = name
            document.speakers[index].suggestedParticipantID = nil
            document.speakers[index].suggestionScore = nil
        }
    }

    func reassignTurn(_ id: UUID, turnID: UUID, to speakerID: UUID?) throws {
        try edit(id, attribution: true) { document in
            guard let index = document.turns.firstIndex(where: { $0.id == turnID }) else { throw MeetingDataError.invalidRecord }
            let oldID = document.turns[index].speakerID
            let target: UUID
            if let speakerID { target = speakerID }
            else {
                let speaker = MeetingSpeaker(genericLabel: "Speaker \(document.speakers.count + 1)", attributionEdited: true)
                document.speakers.append(speaker)
                target = speaker.id
            }
            guard document.speakers.contains(where: { $0.id == target }) else { throw MeetingDataError.invalidRecord }
            document.turns[index].speakerID = target
            for i in document.speakers.indices where [oldID, target].contains(document.speakers[i].id) {
                document.speakers[i].attributionEdited = true
            }
        }
    }

    func mergeSpeakers(_ id: UUID, from sourceID: UUID, into destinationID: UUID) throws {
        guard sourceID != destinationID else { return }
        try edit(id, attribution: true) { document in
            guard document.speakers.contains(where: { $0.id == sourceID }),
                  let index = document.speakers.firstIndex(where: { $0.id == destinationID }) else { throw MeetingDataError.invalidRecord }
            document.speakers[index].attributionEdited = true
            for i in document.turns.indices where document.turns[i].speakerID == sourceID {
                document.turns[i].speakerID = destinationID
            }
            document.speakers.removeAll { $0.id == sourceID }
        }
    }

    func export(_ id: UUID, participantNames: [UUID: String]) throws -> MeetingExport {
        var document = try load(id)
        guard document.status == .ready else { throw MeetingDataError.invalidRecord }
        let exportID = UUID()
        let name = "\(DateUtil.assetTimestamp(document.createdAt)) - \(Sanitizer.sanitizeTitle(document.title)) - \(exportID.uuidString).md"
        let path = "source/" + name
        var text = "---\nsourceType: meeting\nmeetingID: \(id.uuidString)\nreviewRevision: \(document.reviewRevision)\nexportID: \(exportID.uuidString)\n---\n\n# \(Sanitizer.sanitizeTitle(document.title))\n\n"
        for turn in document.turns {
            guard let speaker = document.speakers.first(where: { $0.id == turn.speakerID }) else { throw MeetingDataError.invalidRecord }
            let label = speaker.confirmedParticipantID.map { participantNames[$0] ?? speaker.displayNameSnapshot ?? speaker.genericLabel } ?? speaker.genericLabel
            let cleanName = label.components(separatedBy: .newlines).joined(separator: " ")
            let stamp = turn.start.map(Self.timestamp) ?? "Untimed"
            text += "<!-- turn: \(turn.id.uuidString) -->\n[\(stamp)] \(cleanName): \(turn.text)\n\n"
        }
        let url = try safeURL(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        let export = MeetingExport(id: exportID, reviewRevision: document.reviewRevision, path: path)
        document.exports.append(export)
        try save(document)
        return export
    }

    static func timestamp(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }

    private func edit(_ id: UUID, attribution: Bool = false,
                      change: (inout MeetingDocument) throws -> Void) throws {
        var document = try load(id)
        guard document.status == .ready else { throw MeetingDataError.invalidRecord }
        try change(&document)
        document.reviewRevision += 1
        if attribution { document.attributionRevision += 1 }
        try save(document)
    }

    private func save(_ document: MeetingDocument) throws {
        try document.validate()
        try encoder().encode(document).write(to: safeURL(".meetings/\(document.id.uuidString)/meeting.json"), options: .atomic)
    }
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
    private func safeURL(_ relative: String) throws -> URL {
        try MeetingLibraryPath.resolve(relative, in: root)
    }
}
