import XCTest
@testable import SumbeeKit

private actor CapturingMeetingClient: AnthropicStreaming {
    private(set) var requests: [SummarizationRequest] = []
    func stream(_ request: SummarizationRequest, apiKey: String,
                onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        requests.append(request)
        return "# Planning notes\n\nA draft will be sent."
    }
    func validateKey(_ apiKey: String, model: String) async -> Result<Void, AnthropicError> { .success(()) }
    func listModels(_ apiKey: String) async -> [RemoteModel] { [] }
}

final class MeetingSummaryTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMeetingBudgetRejectsRatherThanTruncatingAndGenericDefaultsRemain() throws {
        let root = try root()
        var settings = AppSettings()
        settings.libraryRootPath = root.path
        settings.model = "claude-haiku-4-5"
        let style = SummaryStyle(name: "Test", channel: .file, prompt: "Summarize", order: 1)
        var input = PreparedInput(text: String(repeating: "meeting ", count: 120_000), sourceRef: "source/snapshot.md",
            fallbackTitle: "Test", videoMeta: nil)
        input.kind = .meeting
        input.libraryRoot = root
        XCTAssertThrowsError(try SummaryInputBudget.assemble(input, style: style, settings: settings))
        input.kind = .document
        input.libraryRoot = nil
        let generic = try SummaryInputBudget.assemble(input, style: style, settings: settings)
        XCTAssertTrue(generic.truncated)
        XCTAssertTrue(generic.user.contains("truncated"))
    }

    func testImmutableSnapshotsResolveNamesOnceAndRegenerationDoesNotReadCatalog() async throws {
        let root = try root()
        let meetings = MeetingStore(root: root), people = ParticipantStore(root: root)
        let person = try await people.add(name: "Original")
        var meeting = MeetingDocument(title: "Planning", originalFilename: "private.wav",
            audioSHA256: String(repeating: "b", count: 64), durationSeconds: 60)
        meeting.status = .ready
        let confirmed = MeetingSpeaker(genericLabel: "Speaker 1", confirmedParticipantID: person.id, displayNameSnapshot: person.name)
        let suggested = MeetingSpeaker(genericLabel: "Speaker 2", suggestedParticipantID: person.id, suggestionScore: 0.99)
        meeting.speakers = [confirmed, suggested]
        meeting.turns = [.init(text: "I'll send the draft tomorrow.", start: 12, end: 18, speakerID: confirmed.id),
                         .init(text: "Let's review it.", start: 20, end: 22, speakerID: suggested.id)]
        let directory = root.appendingPathComponent(".meetings/\(meeting.id.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(meeting).write(to: directory.appendingPathComponent("meeting.json"))
        let first = try await MeetingSummaryInputBuilder.prepare(meeting.id, meetings: meetings, people: people)
        try await people.rename(person.id, name: "Current")
        let second = try await MeetingSummaryInputBuilder.prepare(meeting.id, meetings: meetings, people: people)
        XCTAssertNotEqual(first.sourceRef, second.sourceRef)
        XCTAssertTrue(first.text.contains("Original:"))
        XCTAssertTrue(second.text.contains("Current:"))
        XCTAssertTrue(second.text.contains("Speaker 2:"))
        for privateValue in [root.path, "private.wav", "suggestionScore", "embedding", person.id.uuidString] {
            XCTAssertFalse(second.text.contains(privateValue))
        }
        try Data("corrupt catalog".utf8).write(to: root.appendingPathComponent(".meetings/participants.json"))
        let restored = try MeetingSummaryInputBuilder.readSnapshot(sourceRef: XCTUnwrap(first.sourceRef), root: root, title: "Planning")
        XCTAssertEqual(restored.text, first.text)
        do { _ = try await MeetingSummaryInputBuilder.prepare(meeting.id, meetings: meetings, people: people); XCTFail() } catch { }
        try FileManager.default.removeItem(at: root.appendingPathComponent(first.sourceRef!))
        XCTAssertThrowsError(try MeetingSummaryInputBuilder.readSnapshot(sourceRef: first.sourceRef!, root: root, title: "Planning"))
    }

    func testMeetingContextAndRootPreflight() throws {
        let root = try root()
        var settings = AppSettings()
        settings.libraryRootPath = root.path
        let style = SummaryStyle(name: "Notes", channel: .file, prompt: DefaultStyles.meetingNotes, order: 1)
        var input = PreparedInput(text: "[00:00:12] Speaker 1: I'll do it.", sourceRef: "source/a.md", fallbackTitle: "Meeting", videoMeta: nil)
        input.kind = .meeting
        input.libraryRoot = root
        let assembled = try SummaryInputBudget.assemble(input, style: style, settings: settings)
        XCTAssertEqual(assembled.user, input.text)
        XCTAssertTrue(assembled.system.contains("Do not infer"))
        XCTAssertTrue(assembled.system.contains("Untimed"))
        settings.libraryRootPath = root.appendingPathComponent("other").path
        XCTAssertThrowsError(try SummaryInputBudget.assemble(input, style: style, settings: settings))
    }

    func testCapturedRequestEqualsPreviewAndRegenerationUsesOriginalSnapshot() async throws {
        let root = try root()
        let source = "source/\(UUID().uuidString).md"
        try FileManager.default.createDirectory(at: root.appendingPathComponent("source"), withIntermediateDirectories: true)
        let raw = "---\nsourceType: meeting\nmeetingID: \(UUID().uuidString)\nexportID: \(UUID().uuidString)\nreviewRevision: 1\n---\n\n[00:00:12] Speaker 1: I'll send the draft.\n"
        try raw.write(to: root.appendingPathComponent(source), atomically: true, encoding: .utf8)
        var settings = AppSettings()
        settings.libraryRootPath = root.path
        settings.outputFormat = .markdown
        let style = SummaryStyle(name: "Test notes", channel: .file, prompt: DefaultStyles.meetingNotes, order: 1)
        let client = CapturingMeetingClient()
        let engine = SummarizationEngine(extractor: TextExtractor(), anthropic: client, youtube: YouTubeService())
        let prepared = try MeetingSummaryInputBuilder.readSnapshot(sourceRef: source, root: root, title: "Planning")
        let preview = try SummaryInputBudget.assemble(prepared, style: style, settings: settings)
        let before = await client.requests.count
        XCTAssertEqual(before, 0)
        let saved = try await engine.finish(prepared, style: style, settings: settings, apiKey: "test-only", progress: { _ in })
        let captured = await client.requests
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].systemPrompt, preview.system)
        XCTAssertEqual(captured[0].userText, preview.user)
        XCTAssertFalse(captured[0].userText.contains(root.path))
        XCTAssertFalse(captured[0].userText.contains("meetingID"))
        let regenerated = try await engine.prepareFromArchive(summaryURL: saved.url, settings: settings, progress: { _ in })
        XCTAssertEqual(regenerated.kind, .meeting)
        XCTAssertEqual(regenerated.text, prepared.text)
        XCTAssertEqual(regenerated.sourceRef, prepared.sourceRef)
        try FileManager.default.removeItem(at: root.appendingPathComponent(source))
        do { _ = try await engine.finish(prepared, style: style, settings: settings, apiKey: "test-only", progress: { _ in }); XCTFail() }
        catch { }
        let afterMissing = await client.requests.count
        XCTAssertEqual(afterMissing, 1)
    }

    func testOptInStyleInstallationPreservesUserEditsAndRename() throws {
        let root = try root(), store = StyleStore()
        try DefaultStyles.installMeetingNotes(root: root, store: store)
        var style = try XCTUnwrap(store.loadStyles(root: root).first)
        style.prompt = "My own edited notes prompt"
        try store.update(style, root: root)
        try store.rename(style, to: "My notes", root: root)
        try DefaultStyles.installMeetingNotes(root: root, store: store)
        let styles = try store.loadStyles(root: root)
        XCTAssertEqual(styles.count, 1)
        XCTAssertEqual(styles[0].name, "My notes")
        XCTAssertEqual(styles[0].prompt, style.prompt)
    }

    func testRegenerationCannotResolveAnOldSummaryAgainstAnotherLibrary() async throws {
        let originalRoot = try root(), otherRoot = try root()
        let summary = originalRoot.appendingPathComponent("summary.md")
        try "---\nsource: source/same-name.md\n---\nOld summary".write(to: summary, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: otherRoot.appendingPathComponent("source"), withIntermediateDirectories: true)
        try "Unrelated library content".write(to: otherRoot.appendingPathComponent("source/same-name.md"), atomically: true, encoding: .utf8)
        var settings = AppSettings()
        settings.libraryRootPath = otherRoot.path
        let engine = SummarizationEngine(extractor: TextExtractor(), anthropic: CapturingMeetingClient(), youtube: YouTubeService())
        do {
            _ = try await engine.prepareFromArchive(summaryURL: summary, settings: settings, progress: { _ in })
            XCTFail("An old summary must not read a coincidentally named source in another library")
        } catch MeetingSummaryError.wrongLibrary { }
    }
}
