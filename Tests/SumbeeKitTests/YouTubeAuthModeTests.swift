import XCTest
@testable import SumbeeKit

/// The yt-dlp args each YouTube auth mode contributes (FR-060). Normal must add nothing so the
/// default fetch is byte-for-byte unchanged (SC-004); cookie/client modes add their flags.
final class YouTubeAuthModeTests: XCTestCase {
    func testNormalAddsNoArgs() {
        XCTAssertEqual(YouTubeAuthMode.normal.ytDlpArgs(playerClient: .android), [])
        XCTAssertFalse(YouTubeAuthMode.normal.usesBrowserCookies)
    }

    func testClientTweakUsesSelectedPlayerClient() {
        XCTAssertEqual(YouTubeAuthMode.clientTweak.ytDlpArgs(playerClient: .android),
                       ["--extractor-args", "youtube:player_client=android"])
        XCTAssertEqual(YouTubeAuthMode.clientTweak.ytDlpArgs(playerClient: .webSafari),
                       ["--extractor-args", "youtube:player_client=web_safari"])
        XCTAssertFalse(YouTubeAuthMode.clientTweak.usesBrowserCookies)
    }

    func testChromeCookies() {
        XCTAssertEqual(YouTubeAuthMode.cookiesChrome.ytDlpArgs(playerClient: .android),
                       ["--cookies-from-browser", "chrome"])
        XCTAssertTrue(YouTubeAuthMode.cookiesChrome.usesBrowserCookies)
    }

    func testSafariCookies() {
        XCTAssertEqual(YouTubeAuthMode.cookiesSafari.ytDlpArgs(playerClient: .android),
                       ["--cookies-from-browser", "safari"])
        XCTAssertTrue(YouTubeAuthMode.cookiesSafari.usesBrowserCookies)
    }

    // Raw values are the persisted form; they must stay stable across releases.
    func testStableRawValuesAndCases() {
        XCTAssertEqual(YouTubeAuthMode.allCases.count, 4)
        XCTAssertEqual(YouTubeAuthMode.normal.rawValue, "normal")
        XCTAssertEqual(YouTubeAuthMode.clientTweak.rawValue, "clientTweak")
        XCTAssertEqual(YouTubeAuthMode.cookiesChrome.rawValue, "cookiesChrome")
        XCTAssertEqual(YouTubeAuthMode.cookiesSafari.rawValue, "cookiesSafari")
    }
}
