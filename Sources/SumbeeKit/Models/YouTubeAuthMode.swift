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

    /// Extra arguments this mode contributes to a yt-dlp caption fetch. `playerClient` is used only
    /// by `.clientTweak` (FR-060/063); other modes ignore it.
    public func ytDlpArgs(playerClient: YouTubePlayerClient) -> [String] {
        switch self {
        case .normal:
            return []
        case .clientTweak:
            return ["--extractor-args", "youtube:player_client=\(playerClient.rawValue)"]
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

    /// What to do when a fetch in THIS mode still hits the bot gate (FR-064/065/066). Pure so the
    /// escalation decision is unit-testable without the async job queue.
    public enum GateOutcome: Equatable {
        /// Normal: auto-retry the job once with Client tweak.
        case escalateToClientTweak
        /// Client tweak already tried (or explicitly chosen) and still gated: advise cookies.
        case adviseCookies
        /// A cookie mode is set and still gated: guide the user (sign-in / permission / update).
        case adviseCookieTrouble
    }

    public var gateOutcome: GateOutcome {
        switch self {
        case .normal: return .escalateToClientTweak
        case .clientTweak: return .adviseCookies
        case .cookiesChrome, .cookiesSafari: return .adviseCookieTrouble
        }
    }
}
