import XCTest
@testable import SumbeeKit

final class ParticipantStoreTests: XCTestCase {
    func testRedirectChainsResolveAndCyclesOrFutureSchemasArePreserved() async throws {
        let (store, root) = try store()
        let a = try await store.add(name: "A"), b = try await store.add(name: "B"), c = try await store.add(name: "C")
        try await store.merge(a.id, into: b.id)
        try await store.merge(b.id, into: c.id)
        let names = try await store.resolvedNames()
        XCTAssertEqual(names[a.id], "C")
        XCTAssertEqual(names[b.id], "C")
        let path = root.appendingPathComponent(".meetings/participants.json")
        var catalog = try await store.load()
        catalog.retirements = [.init(id: a.id, destinationID: b.id), .init(id: b.id, destinationID: a.id)]
        let cyclic = try JSONEncoder().encode(catalog)
        try cyclic.write(to: path)
        do { try await store.rename(c.id, name: "Changed"); XCTFail() } catch { }
        XCTAssertEqual(try Data(contentsOf: path), cyclic)
        catalog.retirements = []
        catalog.schemaVersion = 2
        let future = try JSONEncoder().encode(catalog)
        try future.write(to: path)
        do { _ = try await store.add(name: "New"); XCTFail() } catch { }
        XCTAssertEqual(try Data(contentsOf: path), future)
    }
    private func store() throws -> (ParticipantStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (ParticipantStore(root: root), root)
    }

    func testSameNamesRemainDistinctAndMergeDeletionResolveAfterRestart() async throws {
        let (store, root) = try store()
        let first = try await store.add(name: " Alex ")
        let second = try await store.add(name: "Alex")
        XCTAssertNotEqual(first.id, second.id)
        try await store.merge(second.id, into: first.id)
        try await store.rename(first.id, name: "Alex Chen")
        let reopened = ParticipantStore(root: root)
        let names = try await reopened.resolvedNames()
        XCTAssertEqual(names[first.id], "Alex Chen")
        XCTAssertEqual(names[second.id], "Alex Chen")
        try await reopened.delete(first.id)
        let deletedNames = try await reopened.resolvedNames()
        XCTAssertNil(deletedNames[first.id])
        XCTAssertNil(deletedNames[second.id])
    }

    func testCorruptCatalogIsPreservedAndInvalidNamesAreRejected() async throws {
        let (store, root) = try store()
        do { _ = try await store.add(name: "   "); XCTFail() } catch { }
        _ = try await store.add(name: "Valid")
        let path = root.appendingPathComponent(".meetings/participants.json")
        let bad = Data("broken catalog".utf8)
        try bad.write(to: path)
        do { _ = try await store.add(name: "Another"); XCTFail() } catch { }
        XCTAssertEqual(try Data(contentsOf: path), bad)
    }
}
