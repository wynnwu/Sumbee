import Foundation

/// One atomic document owns identities, redirect history, and explicitly remembered voices.
actor ParticipantStore {
    let root: URL
    init(root: URL) { self.root = MeetingLibraryPath.directory(root) }

    nonisolated static func cleanName(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 120 else { throw ParticipantError.invalidName }
        return clean
    }

    func load() throws -> ParticipantCatalog {
        let url = try catalogURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return ParticipantCatalog() }
        let catalog: ParticipantCatalog
        do { catalog = try JSONDecoder().decode(ParticipantCatalog.self, from: Data(contentsOf: url)) }
        catch { throw ParticipantError.invalidCatalog }
        try catalog.validate()
        return catalog
    }

    func add(name: String) throws -> Participant {
        let person = Participant(name: try Self.cleanName(name))
        var catalog = try load()
        catalog.participants.append(person)
        try save(catalog)
        return person
    }

    func rename(_ id: UUID, name: String) throws {
        var catalog = try load()
        guard let resolved = catalog.resolve(id), let index = catalog.participants.firstIndex(where: { $0.id == resolved }) else {
            throw ParticipantError.missingParticipant
        }
        catalog.participants[index].name = try Self.cleanName(name)
        catalog.participants[index].updatedAt = Date()
        try save(catalog)
    }

    func merge(_ source: UUID, into target: UUID) throws {
        var catalog = try load()
        guard let from = catalog.resolve(source), let to = catalog.resolve(target) else { throw ParticipantError.missingParticipant }
        guard from != to else { return }
        catalog.participants.removeAll { $0.id == from }
        for index in catalog.profiles.indices where catalog.profiles[index].participantID == from {
            catalog.profiles[index].participantID = to
        }
        catalog.retirements.append(.init(id: from, destinationID: to))
        try save(catalog)
    }

    func delete(_ id: UUID) throws {
        var catalog = try load()
        guard let resolved = catalog.resolve(id) else { throw ParticipantError.missingParticipant }
        catalog.participants.removeAll { $0.id == resolved }
        catalog.profiles.removeAll { $0.participantID == resolved }
        catalog.retirements.append(.init(id: resolved, destinationID: nil))
        try save(catalog)
    }

    func removeProfile(_ id: UUID) throws {
        var catalog = try load()
        catalog.profiles.removeAll { $0.id == id }
        try save(catalog)
    }

    func resolvedNames() throws -> [UUID: String] {
        let catalog = try load()
        var names = Dictionary(uniqueKeysWithValues: catalog.participants.map { ($0.id, $0.name) })
        for retired in catalog.retirements {
            if let id = catalog.resolve(retired.id) { names[retired.id] = names[id] }
        }
        return names
    }

    /// Caller supplies the current stored document, not a cached review draft.
    func enroll(meetingID: UUID, speakerID: UUID, meetings: MeetingStore) async throws {
        guard MeetingLibraryPath.sameRoot(root, meetings.root) else { throw MeetingDataError.missingMeeting }
        let meeting = try await meetings.load(meetingID)
        guard let speaker = meeting.speakers.first(where: { $0.id == speakerID }) else { throw MeetingDataError.invalidRecord }
        if let reason = Self.enrollmentReason(meeting: meeting, speaker: speaker) { throw ParticipantError.ineligibleVoice(reason) }
        var catalog = try load()
        guard let confirmed = speaker.confirmedParticipantID, let participantID = catalog.resolve(confirmed),
              let recognition = meeting.recognitionResult, let key = speaker.clusterKeys.first,
              let raw = recognition.embeddings[key], let embedding = ParticipantMatcher.normalized(raw) else {
            throw ParticipantError.missingParticipant
        }
        // Repeating the explicit action does not multiply identical samples.
        guard !catalog.profiles.contains(where: {
            $0.participantID == participantID && $0.sourceMeetingID == meeting.id &&
            $0.sourceClusterKeys == speaker.clusterKeys && $0.sourceAttributionRevision == meeting.attributionRevision
        }) else { return }
        catalog.profiles.append(.init(participantID: participantID, embedding: embedding,
            embeddingFingerprint: recognition.embeddingFingerprint, dimension: embedding.count,
            sourceMeetingID: meeting.id, sourceClusterKeys: speaker.clusterKeys,
            sourceAttributionRevision: meeting.attributionRevision))
        try save(catalog)
    }

    func candidates(fingerprint: String, meetings: MeetingStore) async throws -> [ParticipantCandidate] {
        guard MeetingLibraryPath.sameRoot(root, meetings.root) else { return [] }
        let catalog = try load()
        var candidates: [ParticipantCandidate] = []
        for profile in catalog.profiles where profile.embeddingFingerprint == fingerprint {
            // Missing/corrupt sources and attribution revisions invalidate voices even after a crash.
            guard let source = try? await meetings.load(profile.sourceMeetingID),
                  source.attributionRevision == profile.sourceAttributionRevision,
                  let speaker = source.speakers.first(where: { $0.clusterKeys == profile.sourceClusterKeys }),
                  let confirmed = speaker.confirmedParticipantID,
                  catalog.resolve(confirmed) == profile.participantID,
                  Self.enrollmentReason(meeting: source, speaker: speaker) == nil,
                  source.recognitionResult?.embeddingFingerprint == fingerprint else { continue }
            candidates.append(.init(participantID: profile.participantID, embedding: profile.embedding))
        }
        return candidates
    }

    nonisolated static func enrollmentReason(meeting: MeetingDocument, speaker: MeetingSpeaker) -> String? {
        guard meeting.status == .ready, speaker.confirmedParticipantID != nil else { return "Confirm this speaker's name first." }
        return voiceSampleReason(meeting: meeting, speaker: speaker)
    }

    /// Both enrollment and a new query need a usable original cluster with clear speech.
    nonisolated static func voiceSampleReason(meeting: MeetingDocument, speaker: MeetingSpeaker) -> String? {
        guard !speaker.attributionEdited, speaker.clusterKeys.count == 1 else {
            return "This speaker's turns were regrouped. Remember their voice from another recording with a clear speaker group."
        }
        guard let recognition = meeting.recognitionResult, let key = speaker.clusterKeys.first,
              let embedding = recognition.embeddings[key], ParticipantMatcher.normalized(embedding) != nil else {
            return "There isn't a usable voice sample here. You can still name the speaker; try another recording to remember their voice."
        }
        // Sweep interval boundaries and count only time occupied exclusively by this cluster.
        let intervals = recognition.intervals.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }
        let boundaries = Set(intervals.flatMap { [$0.start, min($0.end, meeting.durationSeconds)] }).sorted()
        var cleanSeconds = 0.0
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            let midpoint = (start + end) / 2
            let keys = Set(intervals.filter { $0.start <= midpoint && $0.end > midpoint }.map(\.speakerKey))
            if keys == [key] { cleanSeconds += end - start }
        }
        guard cleanSeconds >= 10 else { return "At least 10 seconds of clear speech without other speakers is needed. Try another recording to remember this voice." }
        return nil
    }

    private func catalogURL() throws -> URL {
        do { return try MeetingLibraryPath.resolve(".meetings/participants.json", in: root) }
        catch { throw ParticipantError.invalidCatalog }
    }

    private func save(_ catalog: ParticipantCatalog) throws {
        try catalog.validate()
        let url = try catalogURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: url, options: .atomic)
    }
}
