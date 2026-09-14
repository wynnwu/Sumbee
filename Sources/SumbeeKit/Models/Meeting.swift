import Foundation

enum MeetingStatus: String, Codable, Sendable {
    case queued, awaitingModels, transcribing, diarizing, assembling
    case ready, noSpeech, failed, cancelled, interrupted
    var isProcessing: Bool { [.transcribing, .diarizing, .assembling].contains(self) }
}

struct MeetingTurn: Codable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var start: Double?
    var end: Double?
    var speakerID: UUID
}

struct MeetingSpeaker: Codable, Identifiable, Sendable {
    var id = UUID()
    var genericLabel: String
    var clusterKeys: [String] = []
    var confirmedParticipantID: UUID?
    var displayNameSnapshot: String?
    var suggestedParticipantID: UUID?
    var suggestionScore: Float?
    var attributionEdited = false
}

struct MeetingExport: Codable, Identifiable, Sendable {
    var id: UUID
    var reviewRevision: Int
    var path: String
}

struct MeetingDocument: Codable, Identifiable, Sendable {
    var schemaVersion = 1
    var id: UUID
    var title: String
    var createdAt = Date()
    var audioPath: String
    var originalFilename: String
    var audioSHA256: String
    var durationSeconds: Double
    var status: MeetingStatus = .queued
    var failureMessage: String?
    var reviewRevision = 1
    var attributionRevision = 1
    var modelFingerprint: String?
    var turns: [MeetingTurn] = []
    var speakers: [MeetingSpeaker] = []
    var recognitionResult: MeetingRecognition?
    var expectedParticipantIDs: Set<UUID> = []
    var exports: [MeetingExport] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, createdAt, audioPath, originalFilename, audioSHA256, durationSeconds
        case status, failureMessage, reviewRevision, attributionRevision, modelFingerprint
        case turns, speakers, recognitionResult, expectedParticipantIDs, exports
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        audioPath = try c.decode(String.self, forKey: .audioPath)
        originalFilename = try c.decode(String.self, forKey: .originalFilename)
        audioSHA256 = try c.decode(String.self, forKey: .audioSHA256)
        durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        status = try c.decode(MeetingStatus.self, forKey: .status)
        reviewRevision = try c.decode(Int.self, forKey: .reviewRevision)
        attributionRevision = try c.decode(Int.self, forKey: .attributionRevision)
        turns = try c.decode([MeetingTurn].self, forKey: .turns)
        speakers = try c.decode([MeetingSpeaker].self, forKey: .speakers)
        failureMessage = try c.decodeIfPresent(String.self, forKey: .failureMessage)
        modelFingerprint = try c.decodeIfPresent(String.self, forKey: .modelFingerprint)
        recognitionResult = try c.decodeIfPresent(MeetingRecognition.self, forKey: .recognitionResult)
        expectedParticipantIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .expectedParticipantIDs) ?? []
        exports = try c.decodeIfPresent([MeetingExport].self, forKey: .exports) ?? []
    }

    init(id: UUID = UUID(), title: String, originalFilename: String,
         audioSHA256: String, durationSeconds: Double) {
        self.id = id
        self.title = title
        self.originalFilename = originalFilename
        self.audioSHA256 = audioSHA256
        self.durationSeconds = durationSeconds
        let ext = (originalFilename as NSString).pathExtension.lowercased()
        self.audioPath = ".meetings/\(id.uuidString)/audio.\(ext)"
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw MeetingDataError.unsupportedVersion }
        guard durationSeconds.isFinite, durationSeconds >= 0, reviewRevision > 0, attributionRevision > 0,
              audioSHA256.count == 64, audioSHA256.allSatisfy(\.isHexDigit),
              Self.safeRelativePath(audioPath), !originalFilename.isEmpty,
              Set(speakers.map(\.id)).count == speakers.count,
              Set(turns.map(\.id)).count == turns.count,
              Set(exports.map(\.id)).count == exports.count else { throw MeetingDataError.invalidRecord }
        let speakerIDs = Set(speakers.map(\.id))
        for turn in turns {
            guard speakerIDs.contains(turn.speakerID) else { throw MeetingDataError.invalidRecord }
            switch (turn.start, turn.end) {
            case (nil, nil): break
            case let (start?, end?) where start.isFinite && end.isFinite && start >= 0 && start <= end && end <= durationSeconds: break
            default: throw MeetingDataError.invalidRecord
            }
        }
        guard status != .noSpeech || turns.isEmpty else { throw MeetingDataError.invalidRecord }
        guard exports.allSatisfy({ $0.reviewRevision > 0 && $0.reviewRevision <= reviewRevision && Self.safeRelativePath($0.path) }) else {
            throw MeetingDataError.invalidRecord
        }
    }

    static func safeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && value.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }
    }
}

enum MeetingDataError: LocalizedError {
    case unsupportedVersion, invalidRecord, missingAudio, writeFailed, missingMeeting
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This meeting was saved by an unsupported app version. Its files have been preserved."
        case .invalidRecord: return "This meeting file could not be read safely. Its contents have been preserved."
        case .missingAudio: return "The recording could not be found. Restore its files or import it again."
        case .writeFailed: return "Could not save the meeting. Check the library folder and available disk space, then try again."
        case .missingMeeting: return "This meeting is no longer available in the selected library."
        }
    }
}
