import Foundation

enum MeetingSummaryInputBuilder {
    static func prepare(_ meetingID: UUID, meetings: MeetingStore, people: ParticipantStore) async throws -> PreparedInput {
        guard MeetingLibraryPath.sameRoot(meetings.root, people.root) else { throw MeetingSummaryError.wrongLibrary }
        // A catalog read failure must be visible, not silently exported using outdated names.
        let names = try await people.resolvedNames()
        let snapshot = try await meetings.export(meetingID, participantNames: names)
        let meeting = try await meetings.load(meetingID)
        return try readSnapshot(sourceRef: snapshot.path, root: meetings.root, title: meeting.title)
    }

    static func readSnapshot(sourceRef: String, root: URL, title: String) throws -> PreparedInput {
        guard MeetingDocument.safeRelativePath(sourceRef), sourceRef.hasPrefix("source/") else { throw MeetingSummaryError.missingSnapshot }
        guard let url = try? MeetingLibraryPath.resolve(sourceRef, in: root),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { throw MeetingSummaryError.missingSnapshot }
        let parsed = FrontmatterCodec.parse(raw)
        guard parsed.frontmatter["sourceType"] == "meeting",
              parsed.frontmatter["meetingID"].flatMap(UUID.init(uuidString:)) != nil,
              parsed.frontmatter["exportID"].flatMap(UUID.init(uuidString:)) != nil else { throw MeetingSummaryError.missingSnapshot }
        // Stable turn IDs are useful in the local file; they are not part of a model request.
        let text = parsed.body.components(separatedBy: .newlines)
            .filter { !($0.hasPrefix("<!-- turn: ") && $0.hasSuffix(" -->")) }.joined(separator: "\n")
        var prepared = PreparedInput(text: text, sourceRef: sourceRef, fallbackTitle: title, videoMeta: nil)
        prepared.kind = .meeting
        prepared.libraryRoot = MeetingLibraryPath.directory(root)
        return prepared
    }
}

enum MeetingSummaryError: LocalizedError {
    case wrongLibrary, missingSnapshot, oversized(Int)
    var errorDescription: String? {
        switch self {
        case .wrongLibrary: return "Select this meeting's original library before summarizing it."
        case .missingSnapshot: return "The saved meeting transcript is missing or unreadable. Restore that export to retry, or create a new summary from the meeting."
        case .oversized(let limit): return "The full meeting transcript exceeds this model's estimated input limit (about \(limit) characters). Choose a larger-context model in Settings and try again. No text was sent or truncated."
        }
    }
}
