import Foundation
import Combine

/// UI state and one inference queue shared across all selected libraries. Each work item owns its root.
@MainActor
final class MeetingProcessingState: ObservableObject {
    struct Importing: Identifiable {
        let id: UUID
        let filename: String
        var cancelling = false
    }
    private struct Work {
        let id: UUID
        let store: MeetingStore
        let people: ParticipantStore
        let root: URL
    }
    @Published private(set) var root: URL?
    @Published private(set) var documents: [MeetingDocument] = []
    @Published private(set) var availableAudioIDs: Set<UUID> = []
    @Published private(set) var unreadableMeetingCount = 0
    @Published private(set) var catalog = ParticipantCatalog()
    @Published private(set) var names: [UUID: String] = [:]
    @Published private(set) var imports: [Importing] = []
    @Published private(set) var modelsReady = false
    @Published private(set) var checkingModels = false
    @Published private(set) var downloading = false
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var activeID: UUID?
    @Published private(set) var stage: MeetingProcessingStage?
    @Published private(set) var finishingCancelledCall = false
    @Published var error: String?
    @Published var modelError: String?
    let manager: MeetingModelManager?
    private let transcriber: any MeetingTranscribing
    private let loadModels: @Sendable () async throws -> VerifiedMeetingModels
    private var stores: [URL: MeetingStore] = [:]
    private var peopleStores: [URL: ParticipantStore] = [:]
    @Published private var pending: [Work] = []
    private var active: Work?
    private var cancelled: Set<UUID> = []
    private var enqueueing: Set<UUID> = []
    @Published private var deleting: Set<UUID> = []
    private var processingTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var importTasks: [UUID: Task<Void, Never>] = [:]

    init(transcriber: any MeetingTranscribing = FluidAudioTranscriber(),
         manager: MeetingModelManager? = nil,
         loadModels: (@Sendable () async throws -> VerifiedMeetingModels)? = nil) {
        self.transcriber = transcriber
        let resolved = manager ?? (try? MeetingModelManifest.bundled()).map { MeetingModelManager(manifest: $0) }
        self.manager = resolved
        self.loadModels = loadModels ?? {
            guard let resolved else { throw MeetingModelError.invalidManifest }
            return try await resolved.verifiedInstallation()
        }
    }

    var downloadSize: Int64 { manager?.manifest.downloadBytes ?? 0 }
    var hasWork: Bool { active != nil || !pending.isEmpty || !imports.isEmpty || downloading || !deleting.isEmpty }

    func isScheduled(_ id: UUID) -> Bool {
        activeID == id || pending.contains { $0.id == id }
    }

    func canStart(_ document: MeetingDocument) -> Bool {
        hasAudio(document.id) && !deleting.contains(document.id) && !isScheduled(document.id) && (document.status == .queued ||
            (document.status == .awaitingModels && modelsReady))
    }

    func hasAudio(_ id: UUID) -> Bool { availableAudioIDs.contains(id) }

    func canDeleteAudio(_ document: MeetingDocument) -> Bool {
        hasAudio(document.id) && documents.contains { $0.id == document.id } && !isScheduled(document.id)
            && !document.status.isProcessing && !enqueueing.contains(document.id)
            && !deleting.contains(document.id)
    }

    func deleteAudio(_ id: UUID, root expectedRoot: URL) async -> Bool {
        guard root == expectedRoot, let store = stores[expectedRoot],
              let document = documents.first(where: { $0.id == id }), canDeleteAudio(document) else {
            error = "The meeting is busy or the library changed. Cancel processing and wait for it to stop before deleting."
            return false
        }
        deleting.insert(id)
        defer { deleting.remove(id) }
        do {
            try await store.deleteAudio(id)
            await refresh(root: expectedRoot)
            return true
        } catch {
            if root == expectedRoot { self.error = "Could not delete the saved audio. \(error.localizedDescription)" }
            return false
        }
    }

    func participantContext(_ id: UUID) -> String {
        guard let meeting = documents.first(where: { document in
            document.speakers.contains { speaker in
                speaker.confirmedParticipantID.flatMap { catalog.resolve($0) } == id
            }
        }) else { return "No meeting assignments yet" }
        return "\(meeting.title) · \(meeting.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    func selectRoot(_ url: URL) async {
        let selected = MeetingLibraryPath.directory(url)
        root = selected
        documents = []
        availableAudioIDs = []
        unreadableMeetingCount = 0
        catalog = ParticipantCatalog()
        names = [:]
        if stores[selected] == nil {
            let store = MeetingStore(root: selected)
            stores[selected] = store
            peopleStores[selected] = ParticipantStore(root: selected)
            do { try await store.recoverInterruptedJobs() }
            catch { self.error = error.localizedDescription }
        }
        await refresh(root: selected)
    }

    func refresh(root selected: URL? = nil) async {
        guard let selected = selected ?? root, let store = stores[selected], let people = peopleStores[selected] else { return }
        do {
            let contents = try await store.libraryContents()
            if root == selected {
                self.documents = contents.documents
                self.availableAudioIDs = contents.audioIDs
                self.unreadableMeetingCount = contents.unreadableIDs.count
            }
            let catalog = try await people.load()
            let names = try await people.resolvedNames()
            guard root == selected else { return }
            self.catalog = catalog
            self.names = names
        } catch { if root == selected { self.error = error.localizedDescription } }
    }

    func checkModels() async {
        guard !checkingModels else { return }
        checkingModels = true
        defer { checkingModels = false }
        do { _ = try await loadModels(); modelsReady = true; modelError = nil }
        catch { modelsReady = false; modelError = error.localizedDescription }
    }

    func downloadModels() {
        guard downloadTask == nil, let manager else { return }
        downloading = true
        downloadedBytes = 0
        modelError = nil
        downloadTask = Task {
            defer { downloading = false; downloadTask = nil }
            do {
                _ = try await manager.install { [weak self] completed, _ in
                    Task { @MainActor in self?.downloadedBytes = completed }
                }
                modelsReady = true
                await resumeWaitingForModels()
            } catch is CancellationError { modelError = "Download cancelled. You can resume setup by downloading again." }
            catch { modelError = error.localizedDescription }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func resumeWaitingForModels() async {
        guard let selected = root else { return }
        let waiting = documents.filter { $0.status == .awaitingModels }.sorted { $0.createdAt < $1.createdAt }
        for document in waiting { await enqueue(document.id, root: selected) }
    }

    func importAudio(_ urls: [URL]) {
        guard let selected = root, let store = stores[selected] else { return }
        for url in urls {
            let id = UUID()
            imports.append(.init(id: id, filename: url.lastPathComponent))
            importTasks[id] = Task {
                defer { imports.removeAll { $0.id == id }; importTasks[id] = nil }
                do {
                    let document = try await store.importAudio(from: url)
                    // Publication is the copy transaction's commit point; cancellation afterwards
                    // is a saved-job cancellation, never a claim that the copy failed.
                    if Task.isCancelled { try await store.setStatus(document.id, status: .cancelled) }
                    else if document.status == .queued { await enqueue(document.id, root: selected) }
                    await refresh(root: selected)
                } catch is CancellationError { }
                catch { self.error = "Could not import \(url.lastPathComponent). \(error.localizedDescription) Import the recording again." }
            }
        }
    }

    func cancelImport(_ id: UUID) {
        if let index = imports.firstIndex(where: { $0.id == id }) { imports[index].cancelling = true }
        importTasks[id]?.cancel()
    }

    func enqueue(_ id: UUID, root selected: URL? = nil) async {
        guard let selected = selected ?? root, let store = stores[selected], let people = peopleStores[selected],
              !deleting.contains(id), active?.id != id, !pending.contains(where: { $0.id == id }), enqueueing.insert(id).inserted else { return }
        defer { enqueueing.remove(id) }
        do {
            let document = try await store.load(id)
            guard [.queued, .awaitingModels, .failed, .cancelled, .interrupted].contains(document.status) else { return }
            _ = try await store.audioURL(id)
            cancelled.remove(id)
            try await store.setStatus(id, status: .queued)
            pending.append(.init(id: id, store: store, people: people, root: selected))
            await refresh(root: selected)
            startNext()
        } catch { self.error = error.localizedDescription }
    }

    func cancel(_ id: UUID) async {
        guard let work = active?.id == id ? active : pending.first(where: { $0.id == id }) else {
            if let root, let store = stores[root] {
                do { try await store.setStatus(id, status: .cancelled); await refresh() }
                catch { self.error = error.localizedDescription }
            }
            return
        }
        cancelled.insert(id)
        pending.removeAll { $0.id == id }
        if active?.id == id {
            finishingCancelledCall = true
            processingTask?.cancel()
        }
        do { try await work.store.setStatus(id, status: .cancelled) }
        catch { self.error = error.localizedDescription }
        await refresh(root: work.root)
    }

    private func startNext() {
        guard active == nil, !pending.isEmpty else { return }
        let work = pending.removeFirst()
        active = work
        activeID = work.id
        stage = .loadingModels
        processingTask = Task {
            await process(work)
            active = nil
            activeID = nil
            stage = nil
            finishingCancelledCall = false
            processingTask = nil
            startNext()
        }
    }

    private func process(_ work: Work) async {
        do {
            let models: VerifiedMeetingModels
            do { models = try await loadModels(); modelsReady = true }
            catch is CancellationError { throw CancellationError() }
            catch {
                modelsReady = false
                modelError = error.localizedDescription
                if !cancelled.contains(work.id) { try await work.store.setStatus(work.id, status: .awaitingModels) }
                await refresh(root: work.root)
                return
            }
            try Task.checkCancellation()
            let audio = try await work.store.audioURL(work.id)
            try await work.store.setStatus(work.id, status: .transcribing)
            await refresh(root: work.root)
            let recognition = try await transcriber.transcribe(audio: audio, models: models) { [weak self] stage in
                Task { @MainActor in await self?.updateStage(stage, work: work) }
            }
            try Task.checkCancellation()
            guard !cancelled.contains(work.id) else { return }
            try await work.store.finish(work.id, recognition: recognition)
            await suggest(work: work)
        } catch is CancellationError {
            try? await work.store.setStatus(work.id, status: .cancelled)
        } catch {
            if !cancelled.contains(work.id) {
                do { try await work.store.setStatus(work.id, status: .failed, message: error.localizedDescription) }
                catch { self.error = error.localizedDescription }
            }
        }
        await refresh(root: work.root)
    }

    private func updateStage(_ stage: MeetingProcessingStage, work: Work) async {
        guard active?.id == work.id, !cancelled.contains(work.id) else { return }
        self.stage = stage
        let status: MeetingStatus = stage == .diarizing ? .diarizing : stage == .assembling ? .assembling : .transcribing
        // A final callback can arrive after the completed result. Never overwrite ready content.
        if let document = try? await work.store.load(work.id), document.status.isProcessing {
            try? await work.store.setStatus(work.id, status: status)
        }
        await refresh(root: work.root)
    }

    private func suggest(work: Work) async {
        do {
            let document = try await work.store.load(work.id)
            guard let recognition = document.recognitionResult else { return }
            guard let policy = manager?.manifest.recognitionPolicy,
                  policy.embeddingFingerprint == recognition.embeddingFingerprint else {
                try await work.store.setSuggestions(work.id, suggestions: [:])
                return
            }
            let candidates = try await work.people.candidates(fingerprint: recognition.embeddingFingerprint, meetings: work.store)
            let catalog = try await work.people.load()
            let expected = Set(document.expectedParticipantIDs.compactMap { catalog.resolve($0) })
            // A nonempty but entirely deleted attendee selection must not broaden the search.
            guard document.expectedParticipantIDs.isEmpty || !expected.isEmpty else {
                try await work.store.setSuggestions(work.id, suggestions: [:]); return
            }
            var suggestions: [UUID: ParticipantSuggestion] = [:]
            for speaker in document.speakers where ParticipantStore.voiceSampleReason(meeting: document, speaker: speaker) == nil {
                if let key = speaker.clusterKeys.first, let embedding = recognition.embeddings[key] {
                    suggestions[speaker.id] = ParticipantMatcher.suggest(embedding: embedding, candidates: candidates,
                        expected: expected, minimumScore: policy.minimumScore, separation: policy.separation)
                }
            }
            try await work.store.setSuggestions(work.id, suggestions: suggestions)
        } catch { self.error = "The transcript is saved, but speaker suggestions are unavailable. \(error.localizedDescription)" }
    }

    func updateAttendee(_ id: UUID, participantID: UUID, included: Bool) async {
        guard let root, let store = stores[root], let people = peopleStores[root] else { return }
        do {
            try await store.setExpectedParticipant(id, participantID: participantID, included: included)
            await suggest(work: .init(id: id, store: store, people: people, root: root))
            await refresh(root: root)
        } catch { self.error = error.localizedDescription }
    }

    func meetingStore() throws -> MeetingStore {
        guard let root, let store = stores[root] else { throw MeetingDataError.missingMeeting }
        return store
    }
    func participantStore() throws -> ParticipantStore {
        guard let root, let store = peopleStores[root] else { throw ParticipantError.missingParticipant }
        return store
    }

    func perform(_ action: @escaping (MeetingStore, ParticipantStore) async throws -> Void) {
        guard let root, let store = stores[root], let people = peopleStores[root] else { return }
        Task {
            do { try await action(store, people); await refresh(root: root) }
            catch { self.error = error.localizedDescription }
        }
    }
}
