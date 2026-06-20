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
    /// User-set absolute path to a yt-dlp binary; nil = auto-discover.
    public var ytDlpPath: String?

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
                ytDlpPath: String? = nil) {
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
        self.ytDlpPath = ytDlpPath
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
