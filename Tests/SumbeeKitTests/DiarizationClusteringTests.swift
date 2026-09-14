import XCTest
@testable import FluidAudio

final class DiarizationClusteringTests: XCTestCase {
    func testContradictoryOverlappingVoicesCannotTrainAnIdentity() {
        let mixed = Array(repeating: [Float(1), 0], count: 4)
            + Array(repeating: [Float(0), 1], count: 4)
            + Array(repeating: [Float(1), 1], count: 2)
        let clean = Array(repeating: [Float(1), 0], count: 10)
        var segmentation = SegmentationOutput(logProbs: [], speakerWeights: [mixed, clean],
                                             numChunks: 2, numFrames: 10, numSpeakers: 2)
        func sample(_ chunk: Int, _ slot: Int, _ vector: [Float]) -> TimedEmbedding {
            TimedEmbedding(chunkIndex: chunk, speakerIndex: slot, startFrame: 0, endFrame: 9,
                           frameWeights: segmentation.speakerWeights[chunk].map { $0[slot] },
                           startTime: Double(chunk * 10), endTime: Double(chunk * 10 + 10),
                           embedding256: vector, rho128: [1, 0])
        }
        var samples = [sample(0, 0, [1, 0]), sample(0, 1, [1, 0]), sample(1, 0, [1, 0])]
        let manager = OfflineDiarizerManager()
        XCTAssertEqual(manager.selectTrainingEmbeddings(timedEmbeddings: samples, segmentation: segmentation), [2])
        XCTAssertTrue(manager.selectTrainingEmbeddings(timedEmbeddings: Array(samples.prefix(2)),
                                                      segmentation: segmentation).isEmpty)
        // Distinct simultaneous voices remain valid training evidence.
        samples[1] = sample(0, 1, [0, 1])
        XCTAssertEqual(manager.selectTrainingEmbeddings(timedEmbeddings: samples, segmentation: segmentation), [0, 1, 2])
        // Similar voices in non-overlapping slots do not contradict segmentation.
        samples[1] = sample(0, 1, [1, 0])
        segmentation = SegmentationOutput(logProbs: [],
            speakerWeights: [Array(mixed.prefix(8)) + [[0, 0], [0, 0]], clean],
            numChunks: 2, numFrames: 10, numSpeakers: 2)
        XCTAssertEqual(manager.selectTrainingEmbeddings(timedEmbeddings: samples, segmentation: segmentation), [0, 1, 2])
    }

    func testUnsupportedEmbeddingsRemainUnassigned() {
        let manager = OfflineDiarizerManager()
        XCTAssertEqual(manager.assignEmbeddings(embeddingFeatures: [[-1, 0], [0, 1], [1, 0]],
                                               centroids: [[1, 0]]), [-2, -2, 0])
        XCTAssertEqual(manager.assignEmbeddings(embeddingFeatures: [[1, 0]], centroids: []), [-2])
    }

    func testReconstructionDoesNotInventAClusterForUnassignedSpeech() {
        let segmentation = SegmentationOutput(logProbs: [],
            speakerWeights: [Array(repeating: [Float(1)], count: 10)],
            numChunks: 1, numFrames: 10, numSpeakers: 1, frameDuration: 1)
        XCTAssertTrue(OfflineReconstruction(config: .default).buildSegments(
            segmentation: segmentation, hardClusters: [[-2]], centroids: [[1, 0]]).isEmpty)
    }

    func testClusteringTrainsOnSufficientNonOverlappingSpeech() {
        let chunks: [[[Float]]] = [
            [[1, 0]] + Array(repeating: [0, 0], count: 9),
            Array(repeating: [1, 0], count: 5) + Array(repeating: [0, 0], count: 5),
            Array(repeating: [1, 1], count: 10)
        ]
        let segmentation = SegmentationOutput(logProbs: [], speakerWeights: chunks, numChunks: 3,
                                              numFrames: 10, numSpeakers: 2)
        let samples = chunks.indices.map { index in
            TimedEmbedding(chunkIndex: index, speakerIndex: 0, startFrame: 0, endFrame: 10,
                           frameWeights: chunks[index].map { $0[0] }, startTime: Double(index * 10),
                           endTime: Double(index * 10 + 10), embedding256: [1, 0], rho128: [1, 0])
        }
        XCTAssertEqual(OfflineDiarizerManager().selectTrainingEmbeddings(timedEmbeddings: samples,
                                                                        segmentation: segmentation), [1])
        let insufficient = SegmentationOutput(logProbs: [], speakerWeights: [chunks[0], chunks[2], chunks[2]],
                                             numChunks: 3, numFrames: 10, numSpeakers: 2)
        XCTAssertEqual(OfflineDiarizerManager().selectTrainingEmbeddings(timedEmbeddings: samples,
                                                                        segmentation: insufficient), [0])
    }

    func testSpeakerMaskTransposeKeepsEachVoicesTimelineSeparate() {
        let frames: [Float] = [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]
        var speakers = [Float](repeating: 0, count: frames.count)
        frames.withUnsafeBufferPointer { input in
            speakers.withUnsafeMutableBufferPointer { output in
                OfflineEmbeddingExtractor.transposeSpeakerWeights(input.baseAddress!, into: output.baseAddress!,
                                                                 frameCount: 4, speakerCount: 3)
            }
        }
        XCTAssertEqual(speakers, [1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    }

    func testPowersetMaskExcludesInactiveVoicesAndPreservesOverlap() {
        let decoder = OfflineSegmentationProcessor()
        XCTAssertEqual(decoder.speakerActivity(probabilities: [0.05, 0.7, 0.05, 0.05, 0.05, 0.05, 0.05]), [1, 0, 0])
        XCTAssertEqual(decoder.speakerActivity(probabilities: [0.7, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]), [0, 0, 0])
        XCTAssertEqual(decoder.speakerActivity(probabilities: [0.05, 0.05, 0.05, 0.05, 0.7, 0.05, 0.05]), [1, 1, 0])
    }

    func testWarmStartUsesEuclideanDistanceOnNormalizedVoices() {
        // The two unit directions are 0.75 apart. A distance limit of 0.6 must
        // separate them; interpreting 0.6 as cosine similarity incorrectly merges them.
        let cosine = 1 - (0.75 * 0.75 / 2)
        let voices = [[2.0, 0.0], [cosine * 3, sqrt(1 - cosine * cosine) * 3]]
        let separated = AHCClustering().cluster(embeddingFeatures: voices, threshold: 0.6)
        XCTAssertNotEqual(separated[0], separated[1])
        let merged = AHCClustering().cluster(embeddingFeatures: voices, threshold: 0.8)
        XCTAssertEqual(merged[0], merged[1])
    }

    func testCentroidInversionCannotHideAnEarlierMergeAboveTheLimit() {
        // Three unit vectors 0.75 apart. Merging two moves their centroid closer
        // to the third (about 0.65), but that must not erase the earlier 0.75 merge.
        let c = 1 - (0.75 * 0.75 / 2)
        let s = sqrt(1 - c * c)
        let y = (c - c * c) / s
        let voices = [[1.0, 0, 0], [c, s, 0], [c, y, sqrt(1 - c * c - y * y)]]
        let groups = AHCClustering().cluster(embeddingFeatures: voices, threshold: 0.7)
        XCTAssertEqual(Set(groups).count, 3)
    }
}
