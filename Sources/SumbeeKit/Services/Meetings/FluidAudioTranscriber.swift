import AVFoundation
import CoreML
import FluidAudio
import Foundation

/// The only SDK-facing adapter. Model handles are built from local verified files, with no downloader.
actor FluidAudioTranscriber: MeetingTranscribing {
    private var running = false

    func transcribe(audio: URL, models: VerifiedMeetingModels,
                    stage: @escaping @Sendable (MeetingProcessingStage) -> Void) async throws -> MeetingRecognition {
        #if !arch(arm64)
        throw MeetingTranscriptionError.unsupportedHardware
        #else
        guard !running else { throw MeetingTranscriptionError.busy }
        running = true
        defer { running = false }
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: audio)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration >= 0 else { throw MeetingTranscriptionError.invalidAudio }
        // Digital silence has no speech to infer. This also avoids the SDK's short-input error.
        guard file.length > 0, try !isDigitallySilent(file) else {
            return result(text: "", duration: duration, tokens: [], diarization: nil, models: models)
        }
        stage(.loadingModels)
        let asr = try await recognize(audio: audio, duration: duration, directory: models.directory, stage: stage)
        try Task.checkCancellation()
        let tokens = (asr.tokenTimings ?? []).map {
            MeetingRecognition.Token(text: $0.token, start: $0.startTime, end: $0.endTime)
        }
        if asr.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result(text: "", duration: duration, tokens: [], diarization: nil, models: models)
        }
        // Less than a second provides insufficient evidence for speaker clustering. Preserve
        // recognized words with unknown attribution, and keep manual naming available.
        if duration < 1 {
            return result(text: asr.text, duration: duration, tokens: tokens, diarization: nil, models: models)
        }
        stage(.diarizing)
        let diarizer = OfflineDiarizerManager()
        diarizer.initialize(models: try diarizationModels(in: models.directory))
        let speakers = try await diarizer.process(audio)
        try Task.checkCancellation()
        stage(.assembling)
        return result(text: asr.text, duration: duration, tokens: tokens, diarization: speakers, models: models)
        #endif
    }

    private func recognize(audio: URL, duration: Double, directory: URL,
                           stage: @escaping @Sendable (MeetingProcessingStage) -> Void) async throws -> ASRResult {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let vocabularyData = try Data(contentsOf: directory.appendingPathComponent("asr/parakeet_vocab.json"))
        let raw = try JSONDecoder().decode([String: String].self, from: vocabularyData)
        var vocabulary: [Int: String] = [:]
        for (key, value) in raw {
            guard let id = Int(key) else { throw MeetingTranscriptionError.invalidModelData }
            vocabulary[id] = value
        }
        guard !vocabulary.isEmpty else { throw MeetingTranscriptionError.invalidModelData }
        let loaded = try AsrModels(
            encoder: model("asr/Encoder.mlmodelc", in: directory, units: .cpuAndNeuralEngine),
            preprocessor: model("asr/Preprocessor.mlmodelc", in: directory, units: .cpuOnly),
            decoder: model("asr/Decoder.mlmodelc", in: directory, units: .cpuAndNeuralEngine),
            joint: model("asr/JointDecision.mlmodelc", in: directory, units: .cpuAndNeuralEngine),
            configuration: config, vocabulary: vocabulary, version: .v2)
        let manager = AsrManager()
        try await manager.initialize(models: loaded)
        defer { manager.cleanup() }
        try Task.checkCancellation()
        stage(.transcribing)
        if duration < 1 {
            var samples = try AudioConverter().resampleAudioFile(audio)
            samples.append(contentsOf: repeatElement(0, count: max(0, 16000 - samples.count)))
            return try await manager.transcribe(samples)
        }
        return try await manager.transcribe(audio)
    }

    private func isDigitallySilent(_ file: AVAudioFile) throws -> Bool {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65536) else {
            throw MeetingTranscriptionError.invalidAudio
        }
        var read: AVAudioFramePosition = 0
        while read < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(65536, file.length - read)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { throw MeetingTranscriptionError.invalidAudio }
            for channel in 0..<Int(buffer.format.channelCount) {
                for sample in UnsafeBufferPointer(start: channels[channel], count: Int(buffer.frameLength)) {
                    guard sample.isFinite else { throw MeetingTranscriptionError.invalidAudio }
                    if sample != 0 { return false }
                }
            }
            read += AVAudioFramePosition(buffer.frameLength)
        }
        return true
    }

    private func model(_ path: String, in root: URL, units: MLComputeUnits) throws -> MLModel {
        try Task.checkCancellation()
        let config = MLModelConfiguration()
        config.computeUnits = units
        return try MLModel(contentsOf: root.appendingPathComponent(path), configuration: config)
    }

    private func diarizationModels(in root: URL) throws -> OfflineDiarizerModels {
        struct Parameters: Decodable {
            struct Tensor: Decodable { let data_base64: String }
            let tensors: [String: Tensor]
        }
        let parameters = try JSONDecoder().decode(Parameters.self,
            from: Data(contentsOf: root.appendingPathComponent("diar/plda-parameters.json")))
        guard let encoded = parameters.tensors["psi"]?.data_base64,
              let data = Data(base64Encoded: encoded), !data.isEmpty, data.count % 4 == 0 else {
            throw MeetingTranscriptionError.invalidModelData
        }
        let psi: [Double] = data.withUnsafeBytes { bytes in
            stride(from: 0, to: data.count, by: 4).map {
                Double(Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self))))
            }
        }
        guard psi.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw MeetingTranscriptionError.invalidModelData }
        return try OfflineDiarizerModels(
            segmentationModel: model("diar/Segmentation.mlmodelc", in: root, units: .all),
            fbankModel: model("diar/FBank.mlmodelc", in: root, units: .cpuOnly),
            embeddingModel: model("diar/Embedding.mlmodelc", in: root, units: .all),
            pldaRhoModel: model("diar/PldaRho.mlmodelc", in: root, units: .all),
            pldaPsi: psi, compilationDuration: 0)
    }

    private func result(text: String, duration: Double, tokens: [MeetingRecognition.Token],
                        diarization: DiarizationResult?, models: VerifiedMeetingModels) -> MeetingRecognition {
        MeetingRecognition(text: text, duration: duration, tokens: tokens,
            intervals: (diarization?.segments ?? []).map {
                .init(speakerKey: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
            }, embeddings: diarization?.speakerDatabase ?? [:], modelFingerprint: models.manifest.id,
            embeddingFingerprint: models.manifest.embeddingFingerprint)
    }
}
