import Foundation

/// One video in a fetched YouTube playlist (FR-071), from `yt-dlp --flat-playlist`. `Codable` so a
/// fetched playlist can be persisted and reopened without re-fetching (FR-076).
public struct PlaylistEntry: Identifiable, Codable, Equatable, Sendable {
    /// 1-based position in the playlist.
    public let index: Int
    /// YouTube video id (stable; used for dedup and as the row id).
    public let videoID: String
    public let title: String
    /// Canonical watch URL (what the existing YouTube job accepts).
    public let url: URL

    public var id: String { videoID }

    public init(index: Int, videoID: String, title: String, url: URL) {
        self.index = index
        self.videoID = videoID
        self.title = title
        self.url = url
    }
}
