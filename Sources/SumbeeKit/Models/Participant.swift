import Foundation

struct Participant: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var updatedAt = Date()
}

struct VoiceProfile: Codable, Identifiable, Sendable {
    var id = UUID()
    var participantID: UUID
    var embedding: [Float]
    var embeddingFingerprint: String
    var dimension: Int
    var sourceMeetingID: UUID
    var sourceClusterKeys: [String]
    var sourceAttributionRevision: Int
    var createdAt = Date()
}

struct ParticipantRetirement: Codable, Sendable {
    var id: UUID
    /// nil is a deletion tombstone; a UUID redirects to a surviving identity.
    var destinationID: UUID?
}

struct ParticipantCatalog: Codable, Sendable {
    var schemaVersion = 1
    var participants: [Participant] = []
    var profiles: [VoiceProfile] = []
    var retirements: [ParticipantRetirement] = []

    func resolve(_ id: UUID) -> UUID? {
        var current = id
        var visited: Set<UUID> = []
        while visited.insert(current).inserted {
            if participants.contains(where: { $0.id == current }) { return current }
            guard let next = retirements.first(where: { $0.id == current })?.destinationID else { return nil }
            current = next
        }
        return nil
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw ParticipantError.unsupportedVersion }
        let active = Set(participants.map(\.id)), retired = Set(retirements.map(\.id))
        guard active.count == participants.count, retired.count == retirements.count,
              active.isDisjoint(with: retired), Set(profiles.map(\.id)).count == profiles.count else {
            throw ParticipantError.invalidCatalog
        }
        for person in participants {
            guard try ParticipantStore.cleanName(person.name) == person.name else { throw ParticipantError.invalidCatalog }
        }
        for retirement in retirements {
            var current: UUID? = retirement.id
            var visited: Set<UUID> = []
            while let id = current, !active.contains(id) {
                guard visited.insert(id).inserted, let record = retirements.first(where: { $0.id == id }) else {
                    throw ParticipantError.invalidCatalog
                }
                current = record.destinationID
            }
        }
        for profile in profiles {
            guard active.contains(profile.participantID), profile.dimension == profile.embedding.count,
                  !profile.embeddingFingerprint.isEmpty, profile.sourceAttributionRevision > 0,
                  profile.sourceClusterKeys.count == 1,
                  ParticipantMatcher.normalized(profile.embedding) != nil else { throw ParticipantError.invalidCatalog }
            let norm = profile.embedding.reduce(0.0) { $0 + Double($1) * Double($1) }
            guard abs(norm - 1) < 0.001 else { throw ParticipantError.invalidCatalog }
        }
    }
}

enum ParticipantError: LocalizedError {
    case invalidName, missingParticipant, invalidCatalog, unsupportedVersion, ineligibleVoice(String)
    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a name between 1 and 120 characters."
        case .missingParticipant: return "This participant is no longer in the catalog. Choose another person."
        case .invalidCatalog: return "The participant catalog could not be read safely. Its file has been preserved."
        case .unsupportedVersion: return "This participant catalog needs a different app version. Its file has been preserved."
        case .ineligibleVoice(let reason): return reason
        }
    }
}
