import XCTest
@testable import SumbeeKit

final class YouTubeServiceTests: XCTestCase {
    // Regression: the exact yt-dlp 429 we hit must be a retryable rate-limit, not a hard .failed.
    func testClassifyRateLimitFromRealError() {
        let stderr = "ERROR: Unable to download video subtitles for 'en-ar': HTTP Error 429: Too Many Requests"
        XCTAssertEqual(YouTubeService.classify(stderr: stderr), .rateLimited)
    }

    func testClassifyRateLimitFromMessage() {
        XCTAssertEqual(YouTubeService.classify(stderr: "ERROR: too many requests, slow down"), .rateLimited)
    }

    func testClassifyNoCaptions() {
        XCTAssertEqual(
            YouTubeService.classify(stderr: "WARNING: There are no subtitles for the requested languages"),
            .noCaptions)
    }

    func testClassifyPrivateVideo() {
        XCTAssertEqual(
            YouTubeService.classify(stderr: "ERROR: Private video. Sign in if you've been granted access"),
            .privateVideo)
    }

    func testClassifyNetworkFallback() {
        XCTAssertEqual(YouTubeService.classify(stderr: "ERROR: <urlopen error timed out>"), .network)
    }
}
