import Foundation

/// Geek-mode prompt preview modal (FR-039): show the modal immediately while preparing, then
/// reveal the full assembled prompt + token estimate.
public enum PreviewPhase {
    case preparing
    case ready(PendingPreview)
}

/// A pending, fully-assembled request awaiting user confirmation in geek mode (FR-039).
public struct PendingPreview: Identifiable {
    public let id = UUID()
    public var system: String
    public var user: String
    public var estimatedTokens: Int
    public var modelName: String
    var prepared: PreparedInput
    var style: SummaryStyle
    var displayName: String
    var input: Job.Input
}

/// Sequential job queue with a resilient retry policy (FR-021): one job at a time, one
/// failure never aborts the batch, and transient/environmental failures (no network, model
/// unavailable, region/VPN-blocked, rate limit, overload) are retried with exponential
/// backoff capped at 5 minutes, plus a manual "Run queue" trigger.
@MainActor
public extension AppState {

    /// Backoff schedule in seconds (interval capped at 5 minutes; this many auto-attempts).
    private static var retryDelays: [Int] { [5, 15, 30, 60, 120, 300] }

    // MARK: Enqueue

    func enqueueFiles(_ urls: [URL], style: SummaryStyle) {
        guard requireKey() else { return }
        let supported = urls.filter { TextExtractor.isSupported($0) }
        let unsupported = urls.filter { !TextExtractor.isSupported($0) }
        if !unsupported.isEmpty {
            present(.error, "Skipped \(unsupported.count) unsupported file\(unsupported.count == 1 ? "" : "s").")
        }
        guard !supported.isEmpty else { return }
        // Geek mode: preview the exact prompt before sending a single file (FR-039). Batches skip it.
        if settings.geekMode, supported.count == 1 {
            previewSingle(input: .file(supported[0]), displayName: supported[0].lastPathComponent, style: style)
            return
        }
        for url in supported {
            jobs.append(Job(input: .file(url), displayName: url.lastPathComponent,
                            styleID: style.id, styleName: style.name))
        }
        startProcessing()
    }

    func enqueueYouTube(_ url: URL, style: SummaryStyle) {
        guard requireKey() else { return }
        if settings.geekMode {
            previewSingle(input: .youtube(url), displayName: youtubeDisplayName(url), style: style)
            return
        }
        jobs.append(Job(input: .youtube(url),
                        displayName: youtubeDisplayName(url),
                        styleID: style.id, styleName: style.name))
        startProcessing()
    }

    /// Re-run a saved summary from its archived source with a chosen style and optional
    /// model/format override; produces a NEW summary, leaving the original intact (FR-037).
    func regenerate(_ asset: Asset, style: SummaryStyle, override: ModelOverride?) {
        guard requireKey() else { return }
        if settings.geekMode {
            previewSingle(input: .regenerate(summaryURL: asset.url, override: override),
                          displayName: "Regenerate · \(asset.title)", style: style)
            return
        }
        jobs.append(Job(input: .regenerate(summaryURL: asset.url, override: override),
                        displayName: "Regenerate · \(asset.title)",
                        styleID: style.id, styleName: style.name))
        startProcessing()
    }

    // MARK: Geek-mode prompt preview (FR-039)

    /// Prepare the input, assemble the exact prompt, and surface it for confirmation. On Send the
    /// job is enqueued with the prepared input cached (so it isn't prepared twice).
    private func previewSingle(input: Job.Input, displayName: String, style: SummaryStyle) {
        let settingsSnapshot = settings
        previewPhase = .preparing         // show the modal + spinner immediately (FR-039)
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            let noop: @Sendable (SummarizationEvent) -> Void = { _ in }
            do {
                let prepared: PreparedInput
                switch input {
                case .file(let url):
                    prepared = try await engine.prepareFile(url, settings: settingsSnapshot, progress: noop)
                case .youtube(let url):
                    prepared = try await engine.prepareYouTube(url, settings: settingsSnapshot, progress: noop)
                case .regenerate(let url, _):
                    prepared = try await engine.prepareFromArchive(summaryURL: url, settings: settingsSnapshot, progress: noop)
                }
                try Task.checkCancellation()
                var effStyle = style
                if case .regenerate(_, let o) = input, let o { effStyle.modelOverride = o }
                let format = effStyle.modelOverride?.outputFormat ?? settingsSnapshot.outputFormat
                let model = effStyle.modelOverride?.model ?? settingsSnapshot.model
                let (system, user) = PromptBuilder.assemble(
                    style: effStyle, format: format, htmlStylingPrompt: settingsSnapshot.htmlStylingPrompt,
                    globalPrompt: settingsSnapshot.systemPrompt, transcript: prepared.text, videoMeta: prepared.videoMeta)
                let preview = PendingPreview(
                    system: system, user: user,
                    estimatedTokens: TokenEstimator.estimate(system + "\n\n" + user),
                    modelName: model, prepared: prepared, style: style,
                    displayName: displayName, input: input)
                guard !Task.isCancelled else { return }
                self.previewPhase = .ready(preview)
            } catch is CancellationError {
                // user cancelled the modal mid-prepare — phase already cleared
            } catch {
                self.previewPhase = nil
                self.present(.error, "Couldn’t prepare preview: \(error.localizedDescription)")
            }
        }
    }

    /// Send the previewed request (geek mode): enqueue with the already-prepared input.
    func confirmPendingPreview() {
        guard case .ready(let p)? = previewPhase else { return }
        var job = Job(input: p.input, displayName: p.displayName, styleID: p.style.id, styleName: p.style.name)
        job.prepared = p.prepared       // skip re-prepare — runJob reuses the cache
        jobs.append(job)
        previewPhase = nil
        startProcessing()
    }

    func cancelPendingPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewPhase = nil
    }

    func cancel(_ jobID: UUID) {
        if jobID == currentJobID {
            currentJobTask?.cancel()
        } else {
            updateJob(jobID) { $0.phase = .cancelled; $0.nextRetryAt = nil }
        }
    }

    func clearFinishedJobs() {
        jobs.removeAll { $0.phase.isTerminal }
    }

    /// Manual "Run queue": requeue every waiting or failed job immediately (resetting backoff),
    /// keeping their cached input so nothing is re-extracted or re-archived. (FR-021)
    func runQueueNow() {
        guard requireKey() else { return }
        var requeued = 0
        for i in jobs.indices {
            switch jobs[i].phase {
            case .waitingRetry, .failed:
                jobs[i].phase = .queued
                jobs[i].attempt = 0
                jobs[i].nextRetryAt = nil
                requeued += 1
            default:
                break
            }
        }
        if requeued > 0 { present(.info, "Re-running \(requeued) job\(requeued == 1 ? "" : "s")…") }
        startProcessing()
    }

    // MARK: Status helpers

    var activeJobCount: Int { jobs.filter { !$0.phase.isTerminal }.count }

    /// True while any job is queued, running, or waiting to retry (used by the quit guard).
    var hasRunningJobs: Bool { jobs.contains { !$0.phase.isTerminal } }

    /// Cancel everything in flight (used when the user confirms quit mid-run).
    func cancelAllJobs() {
        currentJobTask?.cancel()
        queueTask?.cancel()
        retryTicker?.cancel()
        for i in jobs.indices where !jobs[i].phase.isTerminal {
            jobs[i].phase = .cancelled
            jobs[i].nextRetryAt = nil
        }
    }

    /// True when there are jobs waiting to retry or failed jobs that "Run queue" could retry.
    var hasPendingRetry: Bool {
        jobs.contains {
            switch $0.phase { case .waitingRetry, .failed: return true; default: return false }
        }
    }

    var statusLine: String? {
        if let id = currentJobID, let job = jobs.first(where: { $0.id == id }) {
            let total = jobs.count
            let pos = (jobs.firstIndex(where: { $0.id == id }) ?? 0) + 1
            return "\(job.phaseLabel) \(pos) of \(total)…"
        }
        let waiting = jobs.compactMap { job -> Date? in
            if case .waitingRetry(let at) = job.phase { return at } else { return nil }
        }
        if let soonest = waiting.min() {
            let remaining = max(0, Int(ceil(soonest.timeIntervalSince(clock))))
            return "Retrying \(waiting.count) job\(waiting.count == 1 ? "" : "s") in \(remaining)s…"
        }
        if jobs.contains(where: { $0.phase == .queued }) { return "Queued…" }
        return nil
    }

    // MARK: Processing

    private func startProcessing() {
        guard queueTask == nil else { return }
        queueTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
        }
    }

    private func processQueue() async {
        defer { queueTask = nil }
        while let job = jobs.first(where: { $0.phase == .queued }) {
            currentJobID = job.id
            let task = Task { [weak self] in
                guard let self else { return }
                await self.runJob(job)
            }
            currentJobTask = task
            await task.value
            currentJobID = nil
            currentJobTask = nil
        }
    }

    private func runJob(_ job: Job) async {
        guard let apiKey = keychain.load(), !apiKey.isEmpty else {
            handleAuthFailure()
            updateJob(job.id) { $0.phase = .failed("No API key.") }
            return
        }
        guard let style = library.styles.first(where: { $0.id == job.styleID }) else {
            updateJob(job.id) { $0.phase = .failed("Style no longer exists.") }
            return
        }
        let settings = self.settings
        let progress: @Sendable (SummarizationEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.apply(event, to: job.id) }
        }

        do {
            // Prepare once (extract/fetch + archive); reuse the cache on retries.
            let prepared: PreparedInput
            if let cached = jobs.first(where: { $0.id == job.id })?.prepared {
                prepared = cached
            } else {
                switch job.input {
                case .file(let url):
                    prepared = try await engine.prepareFile(url, settings: settings, progress: progress)
                case .youtube(let url):
                    prepared = try await engine.prepareYouTube(url, settings: settings, progress: progress)
                case .regenerate(let summaryURL, _):
                    prepared = try await engine.prepareFromArchive(summaryURL: summaryURL,
                                                                   settings: settings, progress: progress)
                }
                updateJob(job.id) { $0.prepared = prepared }
            }
            try Task.checkCancellation()

            // Regenerate may override the chosen style's model/format (FR-037/038).
            var effectiveStyle = style
            if case .regenerate(_, let override) = job.input, let o = override {
                effectiveStyle.modelOverride = o
            }
            streamingText = ""; streamingJobID = job.id     // begin live preview (FR-040)
            let asset = try await engine.finish(prepared, style: effectiveStyle, settings: settings,
                                                apiKey: apiKey, progress: progress)
            updateJob(job.id) { $0.phase = .done(asset.url); $0.nextRetryAt = nil }
            clearStreaming(job.id)
            reloadLibrary()
            selectedAsset = asset
            present(.success, "Saved “\(asset.title)”.")
        } catch is CancellationError {
            markCancelled(job.id)
        } catch let e as AnthropicError {
            if Task.isCancelled { markCancelled(job.id) }       // cancellation always wins
            else if e.isAuth {
                handleAuthFailure()
                updateJob(job.id) { $0.phase = .failed(e.userMessage) }
            } else if e.isRetryable {
                scheduleRetry(job.id, message: e.userMessage)
            } else {
                fail(job.id, e.userMessage)
            }
        } catch let e as YouTubeError {
            if Task.isCancelled { markCancelled(job.id) }
            else if e == .network { scheduleRetry(job.id, message: e.userMessage) }
            else { fail(job.id, e.userMessage) }
        } catch let e as ExtractionError {
            fail(job.id, "\(job.displayName): \(e.userMessage)")
        } catch let e as RegenerateError {
            fail(job.id, e.userMessage)
        } catch let e as URLError {
            if Task.isCancelled || e.code == .cancelled { markCancelled(job.id) }
            else { scheduleRetry(job.id, message: "Network problem: \(e.localizedDescription)") }
        } catch {
            fail(job.id, error.localizedDescription)
        }
    }

    private func markCancelled(_ id: UUID) {
        updateJob(id) { $0.phase = .cancelled; $0.nextRetryAt = nil }
        clearStreaming(id)
    }

    private func fail(_ id: UUID, _ message: String) {
        updateJob(id) { $0.phase = .failed(message); $0.nextRetryAt = nil }
        clearStreaming(id)
        present(.error, message)
    }

    /// Clear the live preview buffer when this job stops streaming.
    private func clearStreaming(_ id: UUID) {
        if streamingJobID == id { streamingText = ""; streamingJobID = nil }
    }

    /// Schedule an automatic retry with exponential backoff (cap 5 min). After the schedule is
    /// exhausted, leave the job failed but requeue-able via "Run queue".
    private func scheduleRetry(_ id: UUID, message: String) {
        clearStreaming(id)
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        let attempt = jobs[idx].attempt + 1
        jobs[idx].attempt = attempt
        let delays = AppState.retryDelays
        guard attempt <= delays.count else {
            jobs[idx].phase = .failed(message)
            jobs[idx].nextRetryAt = nil
            present(.error, "\(message) Stopped auto-retrying after \(delays.count) attempts — use Run queue to try again.")
            return
        }
        let delay = delays[attempt - 1]
        let when = Date().addingTimeInterval(Double(delay))
        jobs[idx].nextRetryAt = when
        jobs[idx].phase = .waitingRetry(when)
        present(.info, "\(message) Retrying in \(delay)s (attempt \(attempt) of \(delays.count)).")
        ensureRetryTicker()
    }

    /// 1 Hz ticker: publishes `clock` (for countdowns) and promotes due waiting jobs to queued.
    private func ensureRetryTicker() {
        guard retryTicker == nil else { return }
        retryTicker = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.setClock(Date())
                var due = false
                for i in self.jobs.indices {
                    if case .waitingRetry(let at) = self.jobs[i].phase, Date() >= at {
                        self.jobs[i].phase = .queued
                        self.jobs[i].nextRetryAt = nil
                        due = true
                    }
                }
                if due { self.startProcessing() }
                let stillWaiting = self.jobs.contains {
                    if case .waitingRetry = $0.phase { return true } else { return false }
                }
                if !stillWaiting { self.retryTicker = nil; return }
            }
        }
    }

    private func apply(_ event: SummarizationEvent, to id: UUID) {
        switch event {
        case .phase(let p):
            updateJob(id) { if !$0.phase.isTerminal { $0.phase = p } }
        case .streamDelta(let d):
            updateJob(id) { $0.preview = String(($0.preview + d).suffix(320)) }
            streamingJobID = id
            streamingText += d          // full live text for the preview pane (FR-040)
        case .notice(let text):
            present(.info, text)
        }
    }

    private func updateJob(_ id: UUID, _ mutate: (inout Job) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { mutate(&jobs[i]) }
    }

    private func youtubeDisplayName(_ url: URL) -> String {
        YouTubeService.videoID(from: url).map { "YouTube · \($0)" } ?? url.absoluteString
    }
}
