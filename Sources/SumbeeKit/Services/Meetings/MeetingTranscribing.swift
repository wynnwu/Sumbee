import Foundation

enum MeetingProcessingStage: String, Codable, Sendable {
    case loadingModels, transcribing, diarizing, assembling
    var title: String {
        switch self {
        case .loadingModels: return "Loading meeting models"
        case .transcribing: return "Transcribing"
        case .diarizing: return "Identifying speakers"
        case .assembling: return "Preparing transcript"
        }
    }
}

struct MeetingRecognition: Codable, Sendable {
    struct Token: Codable, Sendable {
        var text: String
        var start: Double?
        var end: Double?
    }
    struct SpeakerInterval: Codable, Sendable {
        var speakerKey: String
        var start: Double
        var end: Double
    }
    var text: String
    var duration: Double
    var tokens: [Token]
    var intervals: [SpeakerInterval]
    var embeddings: [String: [Float]]
    var modelFingerprint: String
    var embeddingFingerprint: String
}

protocol MeetingTranscribing: Sendable {
    func transcribe(audio: URL, models: VerifiedMeetingModels,
                    stage: @escaping @Sendable (MeetingProcessingStage) -> Void) async throws -> MeetingRecognition
}

enum MeetingTranscriptionError: LocalizedError {
    case busy, invalidAudio, invalidModelData, unsupportedHardware
    var errorDescription: String? {
        switch self {
        case .busy: return "Another meeting is still processing. Please wait for it to finish."
        case .invalidAudio: return "Could not read this recording. Choose a playable audio file and try again."
        case .invalidModelData: return "The local meeting models could not be read. Install them again."
        case .unsupportedHardware: return "Meeting transcription requires an Apple Silicon Mac."
        }
    }
}
