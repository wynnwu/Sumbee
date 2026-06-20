# Contract: Internal Service Surface (AppState ⇄ SumbeeKit)

There is no process boundary (native app), but the same discipline as the source's
"narrow typed IPC" applies: the UI talks to services only through these protocols. This
keeps views dumb and the core testable.

## SummarizationEngine

```swift
protocol SummarizationEngine {
    /// File path: extract → archive → prompt → stream → title → save. Emits progress.
    func summarizeFile(_ url: URL, style: SummaryStyle,
                       settings: AppSettings, apiKey: String,
                       progress: @escaping (JobUpdate) -> Void) async throws -> Asset
    /// YouTube: fetch captions → clean → archive → prompt → stream → title → save.
    func summarizeYouTube(_ url: URL, style: SummaryStyle,
                          settings: AppSettings, apiKey: String,
                          progress: @escaping (JobUpdate) -> Void) async throws -> Asset
}
```

`JobUpdate` carries `phase` and optional streamed-text preview. Both methods are
cancellable via task cancellation.

## JobQueue

```swift
@MainActor protocol JobQueueing {
    func enqueueFiles(_ urls: [URL], style: SummaryStyle)   // one job per file
    func enqueueYouTube(_ url: URL, style: SummaryStyle)
    func cancel(_ jobID: UUID)
    var jobs: [Job] { get }                                  // observable
}
```

Sequential execution; one job's failure never cancels the rest (FR-006/SC-004).

## LibraryStore

```swift
protocol LibraryStoring {
    func scan(root: URL) throws -> Library            // styles + assets + source group
    func startWatching(root: URL, onChange: @escaping () -> Void)
    func stopWatching()
    func assets(in styleFolder: URL) throws -> [Asset]
}
```

A folder counts as a style iff it contains `style-definition/style-definition.md`;
`source/` and the `style-definition/` subfolder are excluded from asset listings.

## StyleStore

```swift
protocol StyleStoring {
    func loadStyles(root: URL) throws -> [SummaryStyle]
    func create(_ style: SummaryStyle, root: URL) throws
    func update(_ style: SummaryStyle, root: URL) throws       // rewrite definition
    func rename(_ style: SummaryStyle, to newName: String, root: URL) throws  // move folder
    func delete(_ style: SummaryStyle, root: URL) throws       // remove definition, keep assets
    func seedDefaults(root: URL) throws                        // §10 styles
}
```

## KeychainStore

```swift
protocol KeychainStoring {
    func save(_ key: String) throws
    func load() -> String?
    func remove() throws
    var hasKey: Bool { get }
}
```

## YouTubeService

```swift
protocol YouTubeServicing {
    func locate() -> URL?                                  // discover yt-dlp
    func fetchTranscript(_ url: URL, language: String,
                         ytDlp: URL) async throws -> (transcript: String, meta: VideoMeta)
    func update(into appSupport: URL) async throws -> URL  // download latest yt-dlp
}
```

Pure helpers used by the above (`TextExtractor`, `PromptBuilder`, `FrontmatterCodec`,
`HTMLMetaCodec`, `Sanitizer`, `VTTParser`, `ModelCatalog`) are independently unit-tested
and have no UI or network coupling.
