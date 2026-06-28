import Foundation

/// Persists saved playlists to `playlists.json` under Application Support (FR-076), mirroring the
/// `AppSettings` JSON pattern. Best-effort: a missing/unreadable file yields an empty list.
public struct PlaylistStore: Sendable {
    public init() {}

    private static var fileURL: URL {
        AppSettings.appSupportDirectory.appendingPathComponent("playlists.json")
    }

    public func load() -> [SavedPlaylist] {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return [] }
        return (try? JSONDecoder().decode([SavedPlaylist].self, from: data)) ?? []
    }

    public func save(_ playlists: [SavedPlaylist]) {
        let dir = AppSettings.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(playlists) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
