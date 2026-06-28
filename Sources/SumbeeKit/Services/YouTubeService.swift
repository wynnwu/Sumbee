import Foundation

public struct VideoMeta: Equatable, Sendable {
    public var videoID: String
    public var title: String
    public var channel: String?
    public var durationSeconds: Int?
    public var uploadDate: String?       // "YYYY-MM-DD"

    public var durationString: String? {
        guard let d = durationSeconds, d > 0 else { return nil }
        let h = d / 3600, m = (d % 3600) / 60, s = d % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

public enum YouTubeError: Error, Equatable {
    case toolMissing
    case invalidURL
    case noCaptions
    case privateVideo
    case unavailable
    case ageRestricted
    case regionLocked
    case liveStream
    case network
    case rateLimited
    case signInRequired
    case failed(String)

    public var userMessage: String {
        switch self {
        case .toolMissing: return "yt-dlp isn’t installed. Add it in Settings to summarize YouTube videos."
        case .invalidURL: return "That doesn’t look like a YouTube URL."
        case .noCaptions: return "This video has no captions. Try another video (audio transcription is a future feature)."
        case .privateVideo: return "This video is private."
        case .unavailable: return "This video is unavailable or was deleted."
        case .ageRestricted: return "This video is age-restricted and can’t be fetched."
        case .regionLocked: return "This video isn’t available in your region."
        case .liveStream: return "Live streams aren’t supported."
        case .network: return "Network problem reaching YouTube."
        case .rateLimited: return "YouTube is rate-limiting requests (HTTP 429). Retrying with backoff."
        case .signInRequired:
            return "YouTube wants to confirm you’re not a bot. Try Settings ▸ YouTube: Download / Update yt-dlp (often fixes it), turn off any VPN, or switch the YouTube access mode to browser cookies, then Run queue."
        case .failed(let m): return "Couldn’t fetch captions: \(m)"
        }
    }
}

public protocol YouTubeServicing: Sendable {
    func locate(customPath: String?) -> URL?
    func fetchTranscript(_ url: URL, language: String, ytDlp: URL, authMode: YouTubeAuthMode) async throws -> (transcript: String, meta: VideoMeta)
    func fetchPlaylist(_ url: URL, authMode: YouTubeAuthMode, ytDlp: URL) async throws -> (title: String?, entries: [PlaylistEntry], complete: Bool)
    func update(into appSupport: URL) async throws -> URL
}

public struct YouTubeService: YouTubeServicing {
    public init() {}

    // MARK: Discovery

    public func locate(customPath: String?) -> URL? {
        let fm = FileManager.default
        if let custom = customPath, !custom.isEmpty, fm.isExecutableFile(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        var candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            installURL().path,
        ]
        // PATH lookup.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                candidates.append("\(dir)/yt-dlp")
            }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Where the app installs its own copy via "Update yt-dlp".
    public func installURL() -> URL {
        AppSettings.appSupportDirectory.appendingPathComponent("bin/yt-dlp")
    }

    // MARK: URL validation

    public static func validate(urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }
        let okHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com"]
        guard okHosts.contains(host) else { return nil }
        if host == "youtu.be" { return url }
        if url.path == "/watch" || url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/live/") { return url }
        return nil
    }

    /// Accepts a YouTube *playlist* URL (path `/playlist` with a `list` id). A `watch?v=…&list=…`
    /// link is treated as a single video by `validate`, not a playlist (FR-071, v1).
    public static func validatePlaylist(urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed), let host = comps.host?.lowercased() else { return nil }
        let okHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
        guard okHosts.contains(host), comps.path == "/playlist" else { return nil }
        guard let list = comps.queryItems?.first(where: { $0.name == "list" })?.value, !list.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    // MARK: Fetch

    public func fetchTranscript(_ url: URL, language: String, ytDlp: URL, authMode: YouTubeAuthMode) async throws
        -> (transcript: String, meta: VideoMeta) {
        try await Task.detached(priority: .userInitiated) {
            try Self.runFetch(url: url, language: language, ytDlp: ytDlp, authMode: authMode)
        }.value
    }

    // MARK: Playlist enumeration (FR-071)

    public func fetchPlaylist(_ url: URL, authMode: YouTubeAuthMode, ytDlp: URL) async throws
        -> (title: String?, entries: [PlaylistEntry], complete: Bool) {
        try await Task.detached(priority: .userInitiated) {
            try Self.runFlatPlaylist(url: url, ytDlp: ytDlp, authMode: authMode)
        }.value
    }

    private static let playlistTemplate = "%(playlist_index)s|||%(id)s|||%(title)s|||%(url)s|||%(playlist_title)s"

    private static func runFlatPlaylist(url: URL, ytDlp: URL, authMode: YouTubeAuthMode) throws
        -> (title: String?, entries: [PlaylistEntry], complete: Bool) {
        // One request, no download; honors the auth mode (cookies) for private playlists.
        let args = ["--flat-playlist", "--no-warnings", "--ignore-errors", "--print", playlistTemplate]
            + authMode.ytDlpArgs
            + [url.absoluteString]
        let result: ProcessRunner.Result
        do { result = try ProcessRunner.run(ytDlp.path, args) }
        catch { throw YouTubeError.failed(error.localizedDescription) }

        let entries = parseFlatPlaylist(result.stdoutString)
        if entries.isEmpty {
            if result.status != 0 { throw classify(stderr: result.stderrString) }
            throw YouTubeError.failed("No videos found in that playlist.")
        }
        // `--ignore-errors` makes yt-dlp exit non-zero when it skipped unavailable videos, so a
        // non-zero status means this enumeration is PARTIAL. The caller merges partial results
        // rather than replacing, so a transient failure can't drop kept videos (FR-077).
        return (parsePlaylistTitle(result.stdoutString), entries, result.status == 0)
    }

    /// The parent playlist title from `%(playlist_title)s` (the 5th `|||` field), if present.
    static func parsePlaylistTitle(_ stdout: String) -> String? {
        for raw in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = raw.components(separatedBy: "|||")
            guard f.count >= 5 else { continue }
            let t = f[4].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, t != "NA" { return t }
        }
        return nil
    }

    /// Parse `--flat-playlist --print "%(playlist_index)s|||%(id)s|||%(title)s|||%(url)s"` output.
    /// Skips blank/malformed lines and `NA` ids; derives a watch URL from the id if `url` is missing.
    static func parseFlatPlaylist(_ stdout: String) -> [PlaylistEntry] {
        var out: [PlaylistEntry] = []
        for raw in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = raw.components(separatedBy: "|||")
            guard f.count >= 4 else { continue }
            let id = f[1].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, id != "NA" else { continue }
            // Always use the canonical watch URL derived from the id. yt-dlp's url field (f[3]) can
            // carry &list=/&index= params that would defeat exact-URL matching downstream, so we
            // don't trust it (it also accepts "NA"/relative strings as a non-nil URL).
            guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { continue }
            let index = Int(f[0].trimmingCharacters(in: .whitespaces)) ?? (out.count + 1)
            let title = f[2].trimmingCharacters(in: .whitespaces)
            out.append(PlaylistEntry(index: index, videoID: id,
                                     title: (title.isEmpty || title == "NA") ? id : title, url: url))
        }
        return out
    }

    private static func runFetch(url: URL, language: String, ytDlp: URL, authMode: YouTubeAuthMode) throws
        -> (transcript: String, meta: VideoMeta) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("summarizer-yt-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let printTemplate = "%(id)s|||%(title)s|||%(channel)s|||%(duration)s|||%(upload_date)s"
        // Request only the requested language and its common variants, NOT "\(language).*", which
        // also matches every auto-translated track (en-ar, en-fr, …) and makes yt-dlp download
        // dozens of subtitle files per video, hammering YouTube into HTTP 429.
        let subLangs = "\(language),\(language)-orig,\(language)-US,\(language)-GB"
        let args = [
            "--no-warnings",
            "--skip-download",
            "--write-subs", "--write-auto-subs",
            "--sub-langs", subLangs,
            "--sub-format", "vtt",
            "--convert-subs", "vtt",
            "--retries", "3",                // ride out transient HTTP errors within one run
            "--extractor-retries", "3",
            "--sleep-requests", "1",         // space out requests so we don't trip rate limits
            "--no-simulate",                 // required so --print still writes the subs
            "--print", printTemplate,
            "-o", tmp.appendingPathComponent("%(id)s.%(ext)s").path,
        ]
        // Auth mode (FR-060): Normal adds nothing; client tweak / cookies append their flags.
        + authMode.ytDlpArgs
        + [url.absoluteString]

        let result: ProcessRunner.Result
        do {
            result = try ProcessRunner.run(ytDlp.path, args)
        } catch {
            throw YouTubeError.failed(error.localizedDescription)
        }

        if result.status != 0 {
            throw classify(stderr: result.stderrString)
        }

        let meta = parseMeta(result.stdoutString, fallbackURL: url)

        // Find the best .vtt in the temp dir (manual subs win the filename when present).
        let vttFiles = (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "vtt" } ?? []
        guard !vttFiles.isEmpty else { throw YouTubeError.noCaptions }

        let chosen = vttFiles.first { $0.lastPathComponent.contains(".\(language).") } ?? vttFiles[0]
        guard let raw = try? String(contentsOf: chosen, encoding: .utf8) else {
            throw YouTubeError.noCaptions
        }
        let transcript = VTTParser.parse(raw)
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw YouTubeError.noCaptions
        }
        return (transcript, meta)
    }

    static func parseMeta(_ stdout: String, fallbackURL: URL) -> VideoMeta {
        let line = stdout.split(separator: "\n").last.map(String.init) ?? ""
        let parts = line.components(separatedBy: "|||")
        func field(_ i: Int) -> String? {
            guard i < parts.count else { return nil }
            let v = parts[i].trimmingCharacters(in: .whitespaces)
            return (v.isEmpty || v == "NA") ? nil : v
        }
        let id = field(0) ?? videoID(from: fallbackURL) ?? "video"
        let title = field(1) ?? id
        let channel = field(2)
        let duration = field(3).flatMap { Double($0) }.map { Int($0) }
        let upload = field(4).flatMap { formatUploadDate($0) }
        return VideoMeta(videoID: id, title: title, channel: channel,
                         durationSeconds: duration, uploadDate: upload)
    }

    static func formatUploadDate(_ raw: String) -> String? {
        guard raw.count == 8 else { return raw }
        let y = raw.prefix(4), m = raw.dropFirst(4).prefix(2), d = raw.dropFirst(6).prefix(2)
        return "\(y)-\(m)-\(d)"
    }

    static func videoID(from url: URL) -> String? {
        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.dropFirst().first
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let v = comps?.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        if url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/live/") {
            return url.pathComponents.dropFirst(2).first
        }
        return nil
    }

    static func classify(stderr: String) -> YouTubeError {
        let s = stderr.lowercased()
        if s.contains("private video") { return .privateVideo }
        if s.contains("age") && s.contains("confirm") { return .ageRestricted }
        if s.contains("not available in your") || s.contains("blocked it in your country") { return .regionLocked }
        if s.contains("live event") || s.contains("is live") { return .liveStream }
        if s.contains("unavailable") || s.contains("removed") || s.contains("does not exist") { return .unavailable }
        if s.contains("no subtitles") || s.contains("there are no subtitles") { return .noCaptions }
        if s.contains("429") || s.contains("too many requests") { return .rateLimited }
        // Anti-bot gate (distinct from 429): needs user action, so it must not auto-retry. (FR-058)
        if s.contains("not a bot") || s.contains("sign in to confirm") { return .signInRequired }
        if s.contains("urlopen error") || s.contains("network") || s.contains("timed out") || s.contains("resolve") {
            return .network
        }
        return .failed(stderr.split(separator: "\n").last.map(String.init) ?? "unknown error")
    }

    // MARK: Update / install

    public func update(into appSupport: URL) async throws -> URL {
        let binDir = appSupport.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let dest = binDir.appendingPathComponent("yt-dlp")
        let release = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

        let (tmpURL, response) = try await URLSession.shared.download(from: release)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw YouTubeError.network
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return dest
    }
}
