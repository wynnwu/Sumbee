import Foundation
import CryptoKit

struct MeetingModelManifest: Codable, Sendable {
    struct Repository: Codable, Sendable {
        let id: String
        let revision: String
        let license: String
    }
    struct Asset: Codable, Sendable {
        let path: String
        let url: URL
        let byteCount: Int64
        let sha256: String
    }
    struct RecognitionPolicy: Codable, Sendable {
        let id: String
        let embeddingFingerprint: String
        let minimumScore: Float
        let separation: Float
        let calibrationStatus: String
    }
    let schemaVersion: Int
    let id: String
    let sdkRevision: String
    let embeddingFingerprint: String
    let repositories: [Repository]
    let assets: [Asset]
    var recognitionPolicy: RecognitionPolicy? = nil

    var downloadBytes: Int64 { assets.reduce(0) { $0 + $1.byteCount } }

    static func resourceURL(name: String, extension ext: String) throws -> URL {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            // SwiftPM's generated accessor looks beside the .app, then in the developer's
            // absolute build directory. Installed apps use their signed Resources directory.
            guard let url = Bundle.main.url(forResource: "Sumbee_SumbeeKit", withExtension: "bundle"),
                  let bundle = Bundle(url: url) else { throw MeetingModelError.invalidManifest }
            resources = bundle
        } else { resources = .module }
        guard let url = resources.url(forResource: name, withExtension: ext) else {
            throw MeetingModelError.invalidManifest
        }
        return url
    }

    static func bundled() throws -> Self {
        let url = try resourceURL(name: "meeting-models", extension: "json")
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try manifest.validate()
        return manifest
    }

    static func notices() -> String {
        do { return try String(contentsOf: resourceURL(name: "meeting-notices", extension: "txt"), encoding: .utf8) }
        catch { return "Model and software notices could not be loaded. Reinstall the app to restore its bundled resources." }
    }

    func validate() throws {
        guard schemaVersion == 1, !id.isEmpty, !sdkRevision.isEmpty,
              !embeddingFingerprint.isEmpty, !assets.isEmpty,
              Set(assets.map(\.path)).count == assets.count else { throw MeetingModelError.invalidManifest }
        if let policy = recognitionPolicy {
            guard !policy.id.isEmpty, policy.embeddingFingerprint == embeddingFingerprint,
                  policy.minimumScore.isFinite, (0...1).contains(policy.minimumScore),
                  policy.separation.isFinite, policy.separation > 0, policy.separation <= 1 else {
                throw MeetingModelError.invalidManifest
            }
        }
        for asset in assets {
            let components = asset.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }),
                  asset.byteCount > 0, asset.sha256.count == 64,
                  asset.sha256.allSatisfy({ $0.isHexDigit }),
                  asset.url.scheme == "https", asset.url.host == "huggingface.co" else {
                throw MeetingModelError.invalidManifest
            }
        }
    }
}

enum MeetingModelError: LocalizedError {
    case notInstalled, invalidManifest, verification(String), installInProgress, downloadFailed
    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Install the meeting models to transcribe audio on this Mac."
        case .invalidManifest: return "The meeting model list is invalid. Reinstall the app before downloading models."
        case .verification(let file): return "Could not verify \(file). Install the meeting models again."
        case .installInProgress: return "Meeting models are already downloading."
        case .downloadFailed: return "Could not download the meeting models. Check your connection and try again."
        }
    }
}

/// Shared streaming checksum; large weights and recordings never need to fit in a Data buffer.
enum MeetingFileDigest {
    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
