import XCTest
@testable import SumbeeKit

/// Live-watch toggle transitions (FR-053..FR-055): the bottom-bar Watch returns to the stream,
/// selecting a library item leaves the stream, and Watch is a no-op when nothing is streaming.
@MainActor
final class WatchModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Skip the Keychain read during AppState init (ad-hoc identity prompt risk; learnings #4).
        setenv("SUMBEE_SMOKE", "1", 1)
    }

    private func sampleAsset() -> Asset {
        Asset(url: URL(fileURLWithPath: "/tmp/sumbee-test/Sample.md"),
              title: "Sample", styleName: "Meetings", format: .markdown)
    }

    func testWatchStreamRequiresAnActiveStream() {
        let state = AppState()
        XCTAssertFalse(state.watchingStream)

        state.watchStream()                        // nothing streaming -> no-op
        XCTAssertFalse(state.watchingStream)

        state.streamingJobID = UUID()              // a stream now exists
        state.watchStream()
        XCTAssertTrue(state.watchingStream)
    }

    func testSelectingAnItemLeavesWatch() {
        let state = AppState()
        state.streamingJobID = UUID()
        state.watchStream()
        XCTAssertTrue(state.watchingStream)

        let asset = sampleAsset()
        state.selectAsset(asset)                   // user selection takes over the preview
        XCTAssertEqual(state.selectedAsset, asset)
        XCTAssertFalse(state.watchingStream)
    }

    func testWatchAgainAfterSelecting() {
        let state = AppState()
        state.streamingJobID = UUID()
        state.selectAsset(sampleAsset())           // navigated away
        XCTAssertFalse(state.watchingStream)

        state.watchStream()                        // bottom-bar Watch returns to the live stream
        XCTAssertTrue(state.watchingStream)
    }
}
