import XCTest
@testable import SumbeeKit

final class ShareContentTests: XCTestCase {
    func testRepoURLIsCanonical() {
        XCTAssertEqual(ShareContent.repoURLString, "https://github.com/wynnwu/Sumbee")
        XCTAssertEqual(ShareContent.repoURL.absoluteString, ShareContent.repoURLString)
    }

    func testShareCopyEndsWithLinkSoItSurvivesTruncation() {
        // Viral best practice: the link must be present (and last) so a clipped post still works.
        XCTAssertTrue(ShareContent.message.hasSuffix(ShareContent.repoURLString))
        XCTAssertTrue(ShareContent.tweet.contains(ShareContent.repoURLString))
    }

    func testTweetStaysWithinPlatformLimit() {
        // Keep the tweet comfortably under 280 chars so a quote/RT still fits.
        XCTAssertLessThanOrEqual(ShareContent.tweet.count, 280)
    }

    func testTwitterShareURLIsWellFormedAndEncodesText() throws {
        let url = try XCTUnwrap(ShareContent.twitterShareURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "twitter.com")
        XCTAssertEqual(components.path, "/intent/tweet")
        let text = components.queryItems?.first { $0.name == "text" }?.value
        XCTAssertEqual(text, ShareContent.tweet)
    }

    func testMailtoURLCarriesSubjectAndBody() throws {
        let url = try XCTUnwrap(ShareContent.mailtoURL)
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let subject = components.queryItems?.first { $0.name == "subject" }?.value
        let body = components.queryItems?.first { $0.name == "body" }?.value
        XCTAssertEqual(subject, ShareContent.emailSubject)
        XCTAssertEqual(body, ShareContent.message)
    }
}
