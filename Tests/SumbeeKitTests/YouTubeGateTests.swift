import XCTest
@testable import SumbeeKit

/// The pure bot-gate escalation decision (FR-064/065/066) and the player-client model (FR-063).
final class YouTubeGateTests: XCTestCase {

    // The escalation ladder: Normal -> try Client tweak; Client tweak -> advise cookies;
    // cookies -> advise cookie trouble. This is what guarantees a one-shot, non-looping escalation.
    func testGateOutcomePerMode() {
        XCTAssertEqual(YouTubeAuthMode.normal.gateOutcome, .escalateToClientTweak)
        XCTAssertEqual(YouTubeAuthMode.clientTweak.gateOutcome, .adviseCookies)
        XCTAssertEqual(YouTubeAuthMode.cookiesChrome.gateOutcome, .adviseCookieTrouble)
        XCTAssertEqual(YouTubeAuthMode.cookiesSafari.gateOutcome, .adviseCookieTrouble)
    }

    // Escalating Normal -> Client tweak and re-evaluating must NOT escalate again (no loop).
    func testEscalationIsOneShot() {
        XCTAssertEqual(YouTubeAuthMode.normal.gateOutcome, .escalateToClientTweak)
        // After escalation the job's effective mode becomes clientTweak, which resolves to advice,
        // never back to escalation.
        XCTAssertEqual(YouTubeAuthMode.clientTweak.gateOutcome, .adviseCookies)
    }

    func testPlayerClientRawValuesAreYtDlpNames() {
        XCTAssertEqual(YouTubePlayerClient.android.rawValue, "android")
        XCTAssertEqual(YouTubePlayerClient.webSafari.rawValue, "web_safari")
        XCTAssertEqual(YouTubePlayerClient.tv.rawValue, "tv")
        XCTAssertEqual(YouTubePlayerClient.ios.rawValue, "ios")
        XCTAssertEqual(YouTubePlayerClient.mweb.rawValue, "mweb")
        XCTAssertEqual(YouTubePlayerClient.allCases.count, 5)
    }

    func testDefaultPlayerClientIsAndroid() {
        XCTAssertEqual(AppSettings().youtubePlayerClient, .android)
    }
}
