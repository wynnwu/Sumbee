import Foundation

/// The yt-dlp `player_client` used by `YouTubeAuthMode.clientTweak` (FR-063). The rawValue IS the
/// yt-dlp client name, so it doubles as the persisted form and the `--extractor-args` value. These
/// are no-login-friendly clients; which one slips past YouTube's bot gate is a moving target, so it
/// is user-selectable with Android preselected (see docs/swift-macos-learnings.md #19).
public enum YouTubePlayerClient: String, Codable, CaseIterable, Sendable, Identifiable {
    case android
    case webSafari = "web_safari"
    case tv
    case ios
    case mweb

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .android: return "Android (recommended)"
        case .webSafari: return "Safari (web)"
        case .tv: return "TV"
        case .ios: return "iOS"
        case .mweb: return "Mobile web"
        }
    }
}
