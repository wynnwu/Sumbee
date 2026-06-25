import Foundation

/// App configuration (NOT styles, NOT the API key). Persisted as JSON under Application
/// Support; versioned for safe migration. See spec data-model.
public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    /// Library root folder (bookmark path). Stored as a path string.
    public var libraryRootPath: String
    public var model: String
    public var maxOutputTokens: Int
    public var temperature: Double
    /// Effort level (e.g. "high"); applied only to models that support it.
    public var effort: String?
    public var extendedThinking: Bool
    public var captionLanguage: String
    public var outputFormat: OutputFormat
    public var htmlStylingPrompt: String
    /// Shared prompt prepended in front of every style's prompt (FR-034). Empty = no-op.
    public var systemPrompt: String
    /// Sticky base font size for the preview pane (FR-036).
    public var previewFontSize: Double
    /// When on, preview the exact prompt + an estimated token count before sending (FR-039).
    public var geekMode: Bool
    /// User-set absolute path to a yt-dlp binary; nil = auto-discover.
    public var ytDlpPath: String?
    /// How yt-dlp authenticates against YouTube's anti-bot gate (FR-059). Default `.normal`.
    public var youtubeAuthMode: YouTubeAuthMode
    /// The yt-dlp player client used by Client tweak mode (FR-063). Default `.android`.
    public var youtubePlayerClient: YouTubePlayerClient

    public init(schemaVersion: Int = AppSettings.currentSchemaVersion,
                libraryRootPath: String = AppSettings.defaultLibraryRootPath,
                model: String = ModelCatalog.defaultModelID,
                maxOutputTokens: Int = 8192,   // headroom for verbose HTML output (FR-013)
                temperature: Double = 0.3,
                effort: String? = nil,
                extendedThinking: Bool = false,
                captionLanguage: String = "en",
                outputFormat: OutputFormat = .markdown,
                htmlStylingPrompt: String = "",
                systemPrompt: String = "",
                previewFontSize: Double = 16,
                geekMode: Bool = false,
                ytDlpPath: String? = nil,
                youtubeAuthMode: YouTubeAuthMode = .normal,
                youtubePlayerClient: YouTubePlayerClient = .android) {
        self.schemaVersion = schemaVersion
        self.libraryRootPath = libraryRootPath
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.effort = effort
        self.extendedThinking = extendedThinking
        self.captionLanguage = captionLanguage
        self.outputFormat = outputFormat
        self.htmlStylingPrompt = htmlStylingPrompt
        self.systemPrompt = systemPrompt
        self.previewFontSize = previewFontSize
        self.geekMode = geekMode
        self.ytDlpPath = ytDlpPath
        self.youtubeAuthMode = youtubeAuthMode
        self.youtubePlayerClient = youtubePlayerClient
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, libraryRootPath, model, maxOutputTokens, temperature, effort,
             extendedThinking, captionLanguage, outputFormat, htmlStylingPrompt, systemPrompt,
             previewFontSize, geekMode, ytDlpPath, youtubeAuthMode, youtubePlayerClient
    }

    /// Field-tolerant decoding: every key falls back to its default, so adding a new setting
    /// never fails to decode an older `config.json` (which would silently reset everything).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        libraryRootPath = try c.decodeIfPresent(String.self, forKey: .libraryRootPath) ?? d.libraryRootPath
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        maxOutputTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? d.maxOutputTokens
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? d.temperature
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? d.effort
        extendedThinking = try c.decodeIfPresent(Bool.self, forKey: .extendedThinking) ?? d.extendedThinking
        captionLanguage = try c.decodeIfPresent(String.self, forKey: .captionLanguage) ?? d.captionLanguage
        outputFormat = try c.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? d.outputFormat
        htmlStylingPrompt = try c.decodeIfPresent(String.self, forKey: .htmlStylingPrompt) ?? d.htmlStylingPrompt
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? d.systemPrompt
        previewFontSize = try c.decodeIfPresent(Double.self, forKey: .previewFontSize) ?? d.previewFontSize
        geekMode = try c.decodeIfPresent(Bool.self, forKey: .geekMode) ?? d.geekMode
        ytDlpPath = try c.decodeIfPresent(String.self, forKey: .ytDlpPath) ?? d.ytDlpPath
        youtubeAuthMode = try c.decodeIfPresent(YouTubeAuthMode.self, forKey: .youtubeAuthMode) ?? d.youtubeAuthMode
        youtubePlayerClient = try c.decodeIfPresent(YouTubePlayerClient.self, forKey: .youtubePlayerClient) ?? d.youtubePlayerClient
    }

    public static let currentSchemaVersion = 2

    public var libraryRootURL: URL {
        URL(fileURLWithPath: (libraryRootPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// `~/Sumbee Summaries` (a normal home folder) rather than `~/Documents/…`: `~/Documents`
    /// is TCC-protected, which silently blocks "Reveal in Finder" for unsigned/ad-hoc builds.
    /// A plain home-level folder has no such gate, so reveal works everywhere. (FR-031)
    public static var defaultLibraryRootPath: String {
        "~/Sumbee Summaries"
    }

    /// Pre-rename defaults, used only to detect installs eligible for one-time migration to the
    /// current default (oldest first): the original Documents location, then the interim name.
    public static var legacyLibraryRootPaths: [String] {
        ["~/Documents/Summaries", "~/Summarizer"]
    }

    // MARK: - Persistence

    /// `~/Library/Application Support/Sumbee/`
    public static var appSupportDirectory: URL {
        appSupportBase().appendingPathComponent("Sumbee", isDirectory: true)
    }

    /// Pre-rename support directory (`…/Summarizer`), migrated on first launch.
    static var legacyAppSupportDirectory: URL {
        appSupportBase().appendingPathComponent("Summarizer", isDirectory: true)
    }

    private static func appSupportBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    public static var configFileURL: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }

    /// Move the pre-rename support dir (config + bundled yt-dlp) to the new name, once.
    private static func migrateSupportDirectoryIfNeeded() {
        let fm = FileManager.default
        let old = legacyAppSupportDirectory, new = appSupportDirectory
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: old, to: new)
    }

    /// Load settings, returning defaults if absent or unreadable. Forward-compatible: a
    /// future schema version is read best-effort; unknown fields are ignored by Codable.
    public static func load() -> AppSettings {
        migrateSupportDirectoryIfNeeded()
        let url = configFileURL
        guard let data = try? Data(contentsOf: url) else { return AppSettings() }
        let decoder = JSONDecoder()
        guard var settings = try? decoder.decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        settings = migrateIfNeeded(settings)
        return settings
    }

    public func save() throws {
        let dir = AppSettings.appSupportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: AppSettings.configFileURL, options: .atomic)
    }

    private static func migrateIfNeeded(_ settings: AppSettings) -> AppSettings {
        var s = settings
        // v1 → v2: adopt the larger HTML-friendly max-token default for installs that still
        // hold the old 4096 default (leave deliberately-customized values alone).
        if s.schemaVersion < 2, s.maxOutputTokens == 4096 {
            s.maxOutputTokens = 8192
        }
        if s.schemaVersion < currentSchemaVersion { s.schemaVersion = currentSchemaVersion }
        return s
    }
}
