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

    // Regression: the anti-bot gate must be its own (non-retryable) case, not generic .failed.
    func testClassifySignInBotCheck() {
        let stderr = "ERROR: [youtube] F9P_ixAEV0M: Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies for the authentication."
        XCTAssertEqual(YouTubeService.classify(stderr: stderr), .signInRequired)
    }

    func testClassifyUnknownStaysFailed() {
        guard case .failed = YouTubeService.classify(stderr: "ERROR: something totally unexpected") else {
            return XCTFail("expected .failed for an unrecognized error")
        }
    }
}
