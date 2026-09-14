import Foundation

/// Progress events emitted during a summarization job.
public enum SummarizationEvent: Sendable {
    case phase(Job.Phase)
    case streamDelta(String)
    /// A non-fatal informational notice (e.g. retry pending, input truncated).
    case notice(String)
}

/// The extracted/fetched + archived input for a job, cached so retries never re-extract
/// or re-archive (FR-021).
public struct PreparedInput: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case document, meeting }
    public var text: String
    public var sourceRef: String?
    public var fallbackTitle: String
    public var videoMeta: VideoMeta?
    public var kind: Kind = .document
    public var libraryRoot: URL? = nil
}

/// Regenerate (FR-037) couldn't locate the saved summary's original source.
public enum RegenerateError: Error, CustomStringConvertible {
    case sourceMissing
    public var description: String {
        "Couldn’t find this summary’s original source to regenerate from."
    }
    public var userMessage: String { description }
}

/// Orchestrates the pipeline as two resumable stages: `prepare` (extract/fetch + archive,
/// done once) and `finish` (prompt → stream → save, retried by the job queue). Runs off main.
public struct SummarizationEngine {
    let extractor: TextExtractor
    let anthropic: AnthropicStreaming
    let youtube: YouTubeServicing
    private let fm = FileManager.default

    public init(extractor: TextExtractor, anthropic: AnthropicStreaming, youtube: YouTubeServicing) {
        self.extractor = extractor
        self.anthropic = anthropic
        self.youtube = youtube
    }

    // MARK: Prepare (run once per job, not retried, to avoid duplicate source archives)

    public func prepareFile(_ url: URL, settings: AppSettings,
                            progress: @escaping @Sendable (SummarizationEvent) -> Void) async throws -> PreparedInput {
        progress(.phase(.extracting))
        let text = try extractor.extract(from: url)            // ExtractionError → non-retryable
        try Task.checkCancellation()
        let sourceRef = try archiveFile(url, root: settings.libraryRootURL)
        if url.pathExtension.lowercased() == "md", FrontmatterCodec.parse(text).frontmatter["sourceType"] == "meeting" {
            return try MeetingSummaryInputBuilder.readSnapshot(sourceRef: sourceRef, root: settings.libraryRootURL,
                                                               title: url.deletingPathExtension().lastPathComponent)
        }
        return PreparedInput(text: text, sourceRef: sourceRef,
                             fallbackTitle: url.deletingPathExtension().lastPathComponent, videoMeta: nil)
    }

    public func prepareYouTube(_ url: URL, settings: AppSettings,
                               progress: @escaping @Sendable (SummarizationEvent) -> Void) async throws -> PreparedInput {
        guard let ytDlp = youtube.locate(customPath: settings.ytDlpPath) else { throw YouTubeError.toolMissing }
        progress(.phase(.fetching))
        let (transcript, meta) = try await youtube.fetchTranscript(
            url, language: settings.captionLanguage, ytDlp: ytDlp,
            authMode: settings.youtubeAuthMode, playerClient: settings.youtubePlayerClient)
        try Task.checkCancellation()
        _ = try archiveTranscript(transcript, title: meta.title, root: settings.libraryRootURL, originalURL: url)
        return PreparedInput(text: transcript, sourceRef: url.absoluteString,   // record the URL as the source
                             fallbackTitle: meta.title, videoMeta: meta)
    }

    /// Rebuild a `PreparedInput` from a saved summary's archived source, for Regenerate (FR-037).
    /// Re-extracts an archived file (no re-archiving) or re-fetches a YouTube URL.
    public func prepareFromArchive(summaryURL: URL, settings: AppSettings,
                                   progress: @escaping @Sendable (SummarizationEvent) -> Void) async throws -> PreparedInput {
        guard summaryURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(
            settings.libraryRootURL.standardizedFileURL.resolvingSymlinksInPath().path + "/") else {
            throw MeetingSummaryError.wrongLibrary
        }
        let raw = (try? String(contentsOf: summaryURL, encoding: .utf8)) ?? ""
        let isHTML = summaryURL.pathExtension.lowercased() == "html"
        let doc = isHTML ? nil : FrontmatterCodec.parse(raw)
        let source = (isHTML ? HTMLMetaCodec.readMeta(raw, name: "source") : doc?.frontmatter["source"])?
            .trimmingCharacters(in: .whitespaces)
        guard let source, !source.isEmpty else { throw RegenerateError.sourceMissing }

        // YouTube source = the original URL → re-fetch.
        if let url = URL(string: source), let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return try await prepareYouTube(url, settings: settings, progress: progress)
        }
        // File source = an archived path under the library root (e.g. "source/<name>").
        let fileURL = settings.libraryRootURL.appendingPathComponent(source)
        guard MeetingDocument.safeRelativePath(source),
              fileURL.resolvingSymlinksInPath().path.hasPrefix(settings.libraryRootURL.resolvingSymlinksInPath().path + "/") else {
            throw RegenerateError.sourceMissing
        }
        guard fm.fileExists(atPath: fileURL.path) else { throw RegenerateError.sourceMissing }
        progress(.phase(.extracting))
        let text = try extractor.extract(from: fileURL)
        let title = (isHTML ? HTMLMetaCodec.readMeta(raw, name: "title") : doc?.frontmatter["title"])
            ?? fileURL.deletingPathExtension().lastPathComponent
        if FrontmatterCodec.parse(text).frontmatter["sourceType"] == "meeting" {
            return try MeetingSummaryInputBuilder.readSnapshot(sourceRef: source, root: settings.libraryRootURL, title: title)
        }
        return PreparedInput(text: text, sourceRef: source, fallbackTitle: title, videoMeta: nil)
    }

    // MARK: Finish (retryable: prompt → stream → save)

    public func finish(_ prepared: PreparedInput,
                       style: SummaryStyle, settings: AppSettings, apiKey: String,
                       progress: @escaping @Sendable (SummarizationEvent) -> Void) async throws -> Asset {
        let root = settings.libraryRootURL
        let format = style.modelOverride?.outputFormat ?? settings.outputFormat
        let assembled = try SummaryInputBudget.assemble(prepared, style: style, settings: settings)
        if prepared.kind == .meeting {
            // A cached retry must still have its immutable source; never invent a replacement.
            guard let source = prepared.sourceRef else { throw MeetingSummaryError.missingSnapshot }
            let snapshot = try MeetingSummaryInputBuilder.readSnapshot(sourceRef: source, root: root, title: prepared.fallbackTitle)
            guard snapshot.text == prepared.text else { throw MeetingSummaryError.missingSnapshot }
        }
        if assembled.truncated {
            progress(.notice("Input exceeded the model context window; truncated with a notice."))
        }
        let request = resolveRequest(model: assembled.model, caps: assembled.capabilities, maxTokens: assembled.maxTokens,
                                     style: style, settings: settings, system: assembled.system, user: assembled.user)

        progress(.phase(.summarizing))
        let output = try await anthropic.stream(request, apiKey: apiKey) { delta in
            progress(.streamDelta(delta))
        }
        try Task.checkCancellation()

        progress(.phase(.saving))
        // For YouTube, the source is the original URL (videoMeta != nil); stamp it visibly into HTML.
        let originalLink = prepared.videoMeta != nil ? prepared.sourceRef : nil
        return try saveAsset(output: output, style: style, format: format, root: root,
                             sourceRef: prepared.sourceRef, model: request.model,
                             fallbackTitle: prepared.fallbackTitle, originalLink: originalLink,
                             videoTitle: prepared.videoMeta?.title,
                             videoLength: prepared.videoMeta?.durationString)
    }

    /// Resolve the request, sending only parameters the chosen model accepts (capability-gated).
    /// `effort` is additionally validated against the model's allowed levels so a stale value
    /// (e.g. "xhigh" carried over to a model that lacks it) is never sent.
    func resolveRequest(model: String, caps: ModelCapabilities, maxTokens: Int,
                        style: SummaryStyle, settings: AppSettings,
                        system: String, user: String) -> SummarizationRequest {
        let temperature = caps.supportsTemperature ? (style.modelOverride?.temperature ?? settings.temperature) : nil
        let chosenEffort = style.modelOverride?.effort ?? settings.effort
        let effort: String? = (caps.supportsEffort && chosenEffort != nil && caps.effortLevels.contains(chosenEffort!))
            ? chosenEffort : nil
        let thinking = caps.supportsAdaptiveThinking ? settings.extendedThinking : false
        return SummarizationRequest(model: model, systemPrompt: system, userText: user,
                                    maxTokens: maxTokens, temperature: temperature,
                                    effort: effort, extendedThinking: thinking)
    }

    // MARK: Saving

    func saveAsset(output: String, style: SummaryStyle, format: OutputFormat, root: URL,
                   sourceRef: String?, model: String, fallbackTitle: String,
                   originalLink: String? = nil, videoTitle: String? = nil,
                   videoLength: String? = nil) throws -> Asset {
        let styleFolder = root.appendingPathComponent(style.name, isDirectory: true)
        try fm.createDirectory(at: styleFolder, withIntermediateDirectories: true)

        let created = Date()
        let displayTitle: String
        let baseName: String
        if let videoTitle, !videoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // YouTube: name the file after the original video title (FR-045).
            displayTitle = videoTitle
            baseName = "Youtube - \(DateUtil.dateStamp(created)) - \(Sanitizer.sanitizeTitle(videoTitle))"
        } else {
            let parsed = PromptBuilder.extractTitle(from: output, format: format)
            displayTitle = (parsed?.isEmpty == false ? parsed! : fallbackTitle)
            baseName = "\(DateUtil.assetTimestamp(created)) - \(Sanitizer.sanitizeTitle(displayTitle))"
        }
        let filename = Sanitizer.uniqueFilename(baseName: baseName, ext: format.fileExtension, in: styleFolder)
        let fileURL = styleFolder.appendingPathComponent(filename)

        let createdISO = DateUtil.iso(created)
        let content: String
        switch format {
        case .markdown:
            var fmatter = Frontmatter()
            fmatter["title"] = displayTitle
            fmatter["style"] = style.name
            fmatter["created"] = createdISO
            if let s = sourceRef { fmatter["source"] = s }
            if let len = videoLength, !len.isEmpty { fmatter["length"] = len }   // original video length
            fmatter["model"] = model
            content = FrontmatterCodec.serialize(.init(frontmatter: fmatter, body: output))
        case .html:
            var pairs: [(key: String, value: String)] = [
                ("title", displayTitle),
                ("style", style.name),
                ("created", createdISO),
                ("source", sourceRef ?? ""),
                ("model", model),
            ]
            if let len = videoLength, !len.isEmpty { pairs.append(("length", len)) }   // original video length
            var html = HTMLMetaCodec.embed(pairs, into: output)
            if let link = originalLink {
                html = HTMLMetaCodec.insertSourceLink(link, into: html)   // visible centered grey link
            }
            content = html
        }

        try content.data(using: .utf8)!.write(to: fileURL, options: .atomic)
        return Asset(url: fileURL, title: displayTitle, styleName: style.name,
                     created: created, sourceRef: sourceRef, format: format)
    }

    // MARK: Archiving

    func archiveFile(_ url: URL, root: URL) throws -> String {
        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let stamped = "\(DateUtil.archiveTimestamp())__\(base)"   // datetime prefix (FR-026)
        let filename = Sanitizer.uniqueFilename(baseName: stamped, ext: ext, in: sourceDir)
        let dest = sourceDir.appendingPathComponent(filename)
        do {
            try fm.copyItem(at: url, to: dest)   // copy, never move (spec FR-3)
        } catch {
            // If copy fails (e.g. permissions), continue without blocking summarization.
            return ""
        }
        return "source/\(dest.lastPathComponent)"
    }

    func archiveTranscript(_ transcript: String, title: String, root: URL, originalURL: URL) throws -> String {
        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        // Name the archived YouTube transcript after the video title (FR-045).
        let base = "Youtube - \(DateUtil.dateStamp()) - \(Sanitizer.sanitizeTitle(title))"
        let filename = Sanitizer.uniqueFilename(baseName: base, ext: "txt", in: sourceDir)
        let dest = sourceDir.appendingPathComponent(filename)
        let header = "Source: \(originalURL.absoluteString)\n\n"
        try (header + transcript).data(using: .utf8)!.write(to: dest, options: .atomic)
        return "source/\(dest.lastPathComponent)"
    }
}
