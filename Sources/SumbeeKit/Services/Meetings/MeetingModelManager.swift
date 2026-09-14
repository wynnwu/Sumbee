import Foundation

/// This handle contains only verified local paths. Constructed by verification, never by inference.
struct VerifiedMeetingModels: Sendable {
    let directory: URL
    let manifest: MeetingModelManifest
    fileprivate init(directory: URL, manifest: MeetingModelManifest) {
        self.directory = directory
        self.manifest = manifest
    }
}

/// Owns explicit installation; local verification has no downloader and never repairs files implicitly.
actor MeetingModelManager {
    typealias Download = @Sendable (URL) async throws -> URL
    typealias Progress = @Sendable (Int64, Int64) -> Void
    private struct Active: Codable { let directory: String }
    let root: URL
    let manifest: MeetingModelManifest
    private var installing = false

    static var defaultRoot: URL {
        // Verification hook: exercise installed-app setup against an isolated model cache.
        if let path = ProcessInfo.processInfo.environment["SUMBEE_MODEL_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sumbee/models", isDirectory: true)
    }

    init(root: URL = defaultRoot, manifest: MeetingModelManifest) {
        self.root = root
        self.manifest = manifest
    }

    func verifiedInstallation() throws -> VerifiedMeetingModels {
        try manifest.validate()
        let marker = root.appendingPathComponent("active.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { throw MeetingModelError.notInstalled }
        let active = try JSONDecoder().decode(Active.self, from: Data(contentsOf: marker))
        guard UUID(uuidString: active.directory) != nil else { throw MeetingModelError.invalidManifest }
        return try verify(directory: root.appendingPathComponent(active.directory, isDirectory: true))
    }

    /// Also supports a developer-supplied already-downloaded model directory, without network access.
    func verify(directory: URL) throws -> VerifiedMeetingModels {
        try manifest.validate()
        let base = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for asset in manifest.assets {
            try Task.checkCancellation()
            let file = directory.appendingPathComponent(asset.path)
            guard file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.size] as? NSNumber)?.int64Value == asset.byteCount,
                  try MeetingFileDigest.sha256(file) == asset.sha256.lowercased() else {
                throw MeetingModelError.verification(asset.path)
            }
        }
        return VerifiedMeetingModels(directory: directory, manifest: manifest)
    }

    func install(progress: @escaping Progress = { _, _ in }) async throws -> VerifiedMeetingModels {
        try await install(download: { url in
            let (temporary, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: temporary)
                throw MeetingModelError.downloadFailed
            }
            return temporary
        }, removeDownloads: true, progress: progress)
    }

    func install(download: @escaping Download, removeDownloads: Bool = false,
                 progress: @escaping Progress = { _, _ in }) async throws -> VerifiedMeetingModels {
        guard !installing else { throw MeetingModelError.installInProgress }
        try manifest.validate()
        installing = true
        defer { installing = false }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let staging = root.appendingPathComponent(".install-" + id, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var completed: Int64 = 0
        progress(0, manifest.downloadBytes)
        for asset in manifest.assets {
            try Task.checkCancellation()
            let downloaded = try await download(asset.url)
            defer { if removeDownloads { try? fm.removeItem(at: downloaded) } }
            try Task.checkCancellation()
            let output = staging.appendingPathComponent(asset.path)
            try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: downloaded, to: output)
            completed += asset.byteCount
            progress(completed, manifest.downloadBytes)
        }
        _ = try verify(directory: staging)
        try Task.checkCancellation()
        let final = root.appendingPathComponent(id, isDirectory: true)
        try fm.moveItem(at: staging, to: final)
        do {
            try JSONEncoder().encode(Active(directory: id)).write(to: root.appendingPathComponent("active.json"), options: .atomic)
        } catch {
            try? fm.removeItem(at: final)
            throw error
        }
        // Keep previous installs: an inference job may still hold a verified handle to one.
        return VerifiedMeetingModels(directory: final, manifest: manifest)
    }
}
