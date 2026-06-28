import Foundation

/// A YouTube playlist the user fetched, kept around so it can be reopened without re-fetching
/// (FR-076). Per-video "done" status is NOT stored - it is derived live from the library so it stays
/// accurate as the user summarizes more over time (FR-078).
public struct SavedPlaylist: Identifiable, Codable, Equatable, Sendable {
    /// Stable id: the playlist's `list=` id when present, else the URL string. Survives a refresh.
    public var id: String
    public var url: URL
    /// The YouTube playlist's title (falls back to a generic label).
    public var title: String
    public var entries: [PlaylistEntry]
    public var fetchedAt: Date

    public init(id: String, url: URL, title: String, entries: [PlaylistEntry], fetchedAt: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.entries = entries
        self.fetchedAt = fetchedAt
    }

    /// The `list=` id for a playlist URL, used as the stable id (falls back to the URL string).
    public static func listID(for url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "list" })?.value ?? url.absoluteString
    }
}
