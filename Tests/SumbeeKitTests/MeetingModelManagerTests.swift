import XCTest
import CryptoKit
@testable import SumbeeKit

final class MeetingModelManagerTests: XCTestCase {
    func testRecognitionPolicyMustMatchTheEmbeddingFingerprint() throws {
        var manifest = manifest()
        manifest.recognitionPolicy = .init(id: "wrong", embeddingFingerprint: "another-model",
            minimumScore: 0.75, separation: 0.12, calibrationStatus: "test")
        XCTAssertThrowsError(try manifest.validate())
        manifest.recognitionPolicy = .init(id: "valid", embeddingFingerprint: manifest.embeddingFingerprint,
            minimumScore: 0.75, separation: 0.12, calibrationStatus: "test")
        XCTAssertNoThrow(try manifest.validate())
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func manifest(path: String = "asr/model.bin", contents: Data = Data("model".utf8)) -> MeetingModelManifest {
        MeetingModelManifest(schemaVersion: 1, id: "test", sdkRevision: "test-sdk",
            embeddingFingerprint: "test-embedding", repositories: [], assets: [
                .init(path: path, url: URL(string: "https://huggingface.co/test/resolve/pinned/model.bin")!,
                      byteCount: Int64(contents.count), sha256: SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined())
            ])
    }

    func testVerifiedInstallIsUsableWithoutDownloaderAndDetectsCorruption() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("download")
        try Data("model".utf8).write(to: input)
        let manager = MeetingModelManager(root: root.appendingPathComponent("models"), manifest: manifest())
        let installed = try await manager.install(download: { _ in input })
        let local = try await manager.verifiedInstallation()
        XCTAssertEqual(local.directory, installed.directory)
        try Data("wrong".utf8).write(to: installed.directory.appendingPathComponent("asr/model.bin"))
        do { _ = try await manager.verifiedInstallation(); XCTFail("Corrupt models must not load") }
        catch { XCTAssertTrue(error.localizedDescription.contains("verify")) }
    }

    func testFailedNewInstallPreservesPreviouslyActiveFiles() async throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("download")
        try Data("model".utf8).write(to: input)
        let storage = root.appendingPathComponent("models")
        let first = MeetingModelManager(root: storage, manifest: manifest())
        let old = try await first.install(download: { _ in input })
        let second = MeetingModelManager(root: storage, manifest: manifest(contents: Data("other".utf8)))
        do { _ = try await second.install(download: { _ in input }); XCTFail("Wrong hash should fail") }
        catch { }
        let retained = try await first.verifiedInstallation()
        XCTAssertEqual(retained.directory, old.directory)
        XCTAssertEqual(try Data(contentsOf: old.directory.appendingPathComponent("asr/model.bin")), Data("model".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: storage.path).contains { $0.hasPrefix(".install-") })
    }

    func testCancelledInstallNeverActivates() async throws {
        let root = try temporaryDirectory()
        let manager = MeetingModelManager(root: root, manifest: manifest())
        do {
            _ = try await manager.install(download: { _ in throw CancellationError() })
            XCTFail("Cancelled install should throw")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active.json").path))
    }

    func testManifestCannotEscapeInstallationRoot() async throws {
        let root = try temporaryDirectory()
        let manager = MeetingModelManager(root: root, manifest: manifest(path: "../outside"))
        do {
            _ = try await manager.install(download: { _ in XCTFail("Invalid manifest must fail before download"); return root })
            XCTFail("Traversal should fail")
        } catch { }
    }

    func testMissingInstallHasActionableError() async throws {
        let manager = MeetingModelManager(root: try temporaryDirectory(), manifest: manifest())
        do { _ = try await manager.verifiedInstallation(); XCTFail("Models aren't installed") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Install")) }
    }
}
