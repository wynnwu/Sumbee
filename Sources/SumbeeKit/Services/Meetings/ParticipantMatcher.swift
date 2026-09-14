import Foundation

struct ParticipantCandidate: Sendable {
    var participantID: UUID
    var embedding: [Float]
}

struct ParticipantSuggestion: Sendable {
    var participantID: UUID
    var score: Float
}

enum ParticipantMatcher {
    // Provisional conservative policy; held-out identity calibration remains a release gate.
    static func suggest(embedding: [Float], candidates: [ParticipantCandidate], expected: Set<UUID> = [],
                        minimumScore: Float = 0.75, separation: Float = 0.12) -> ParticipantSuggestion? {
        guard let query = normalized(embedding) else { return nil }
        var best: [UUID: Float] = [:]
        for candidate in candidates where expected.isEmpty || expected.contains(candidate.participantID) {
            guard candidate.embedding.count == query.count, let vector = normalized(candidate.embedding) else { continue }
            let score = zip(query, vector).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            best[candidate.participantID] = max(best[candidate.participantID] ?? -1, score)
        }
        let ranked = best.sorted { $0.value > $1.value }
        guard let first = ranked.first, first.value >= minimumScore,
              ranked.count < 2 || first.value - ranked[1].value >= separation else { return nil }
        return .init(participantID: first.key, score: first.value)
    }

    static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let norm = sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard norm.isFinite, norm > 0 else { return nil }
        return vector.map { Float(Double($0) / norm) }
    }
}
