import Foundation

/// How Sumbee authenticates yt-dlp caption fetches against YouTube's "Sign in to confirm you're not
/// a bot" gate (FR-059/060). Each mode contributes extra yt-dlp arguments; `.normal` adds none, so
/// the default invocation is unchanged.
public enum YouTubeAuthMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Today's behavior: no extra args. Most private; no cookies are read.
    case normal
    /// Force a non-web player client (no login). Often slips past the gate for public videos; a
    /// heuristic YouTube changes over time.
    case clientTweak
    /// Use the user's Chrome login via `--cookies-from-browser chrome`.
    case cookiesChrome
    /// Use the user's Safari login via `--cookies-from-browser safari`.
    case cookiesSafari

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .clientTweak: return "Client tweak (no login)"
        case .cookiesChrome: return "Browser cookies: Chrome"
        case .cookiesSafari: return "Browser cookies: Safari"
        }
    }

    /// Extra arguments this mode contributes to a yt-dlp caption fetch.
    public var ytDlpArgs: [String] {
        switch self {
        case .normal:
            return []
        case .clientTweak:
            // `android` is the most widely cited no-login client for slipping past the bot gate.
            // Kept a single, documented constant (not a long client list) so one renamed client
            // can't fail the whole fetch. Heuristic; see docs/swift-macos-learnings.md #19.
            return ["--extractor-args", "youtube:player_client=android"]
        case .cookiesChrome:
            return ["--cookies-from-browser", "chrome"]
        case .cookiesSafari:
            return ["--cookies-from-browser", "safari"]
        }
    }

    /// True for the modes that read the user's browser cookies (drives the permission/privacy note).
    public var usesBrowserCookies: Bool {
        self == .cookiesChrome || self == .cookiesSafari
    }
}
