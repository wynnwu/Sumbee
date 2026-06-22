import XCTest
@testable import SumbeeKit

final class StyleStoreTests: XCTestCase {
    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("styles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCreateAndLoadRoundTrip() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StyleStore()

        let style = SummaryStyle(name: "Meetings - General", channel: .file,
                                 prompt: "Summarize faithfully.", order: 1)
        try store.create(style, root: root)

        let loaded = try store.loadStyles(root: root)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Meetings - General")
        XCTAssertEqual(loaded[0].channel, .file)
        XCTAssertEqual(loaded[0].prompt, "Summarize faithfully.")
        XCTAssertEqual(loaded[0].id, style.id)
    }

    func testRenameKeepsStableID() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StyleStore()

        let style = SummaryStyle(name: "Old Name", channel: .file, prompt: "p", order: 1)
        try store.create(style, root: root)
        try store.rename(style, to: "New Name", root: root)

        let loaded = try store.loadStyles(root: root)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "New Name")
        XCTAssertEqual(loaded[0].id, style.id, "id must survive a rename")
    }

    func testDeleteKeepsFolderRemovesDefinition() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StyleStore()

        let style = SummaryStyle(name: "Keepme", channel: .file, prompt: "p", order: 1)
        try store.create(style, root: root)
        // Drop a fake asset in the folder.
        let assetURL = root.appendingPathComponent("Keepme/2026-06-20 1200 - note.md")
        try "summary".data(using: .utf8)!.write(to: assetURL)

        try store.delete(style, root: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path), "asset must be kept")
        XCTAssertEqual(try store.loadStyles(root: root).count, 0, "no longer a style")
    }

    func testSeedDefaultsCreatesFiveStyles() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StyleStore()
        try store.seedDefaults(root: root)
        let loaded = try store.loadStyles(root: root)
        XCTAssertEqual(loaded.count, 5)
        XCTAssertEqual(loaded.filter { $0.channel == .youtube }.count, 1)
        XCTAssertEqual(loaded.filter { $0.channel == .file }.count, 4)
    }
}
