import XCTest
@testable import SumbeeKit

final class AnthropicErrorTests: XCTestCase {
    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                        statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    func testRetryableClassification() {
        XCTAssertTrue(AnthropicError.network("x").isRetryable)
        XCTAssertTrue(AnthropicError.overloaded.isRetryable)
        XCTAssertTrue(AnthropicError.rateLimited(retryAfter: 5).isRetryable)
        XCTAssertTrue(AnthropicError.unavailable("model").isRetryable)
        XCTAssertFalse(AnthropicError.invalidKey.isRetryable)
        XCTAssertFalse(AnthropicError.badRequest("x").isRetryable)
        XCTAssertFalse(AnthropicError.emptyResponse.isRetryable)
    }

    func testMapErrorStatuses() {
        XCTAssertEqual(AnthropicClient.mapError(status: 401, body: Data(), headers: response(401)), .invalidKey)
        XCTAssertEqual(AnthropicClient.mapError(status: 529, body: Data(), headers: response(529)), .overloaded)
        XCTAssertEqual(AnthropicClient.mapError(status: 500, body: Data(), headers: response(500)), .overloaded)

        // 403/404 (model unavailable / region / VPN-blocked) map to a retryable .unavailable.
        if case .unavailable = AnthropicClient.mapError(status: 403, body: Data(), headers: response(403)) {} else {
            XCTFail("403 should map to .unavailable")
        }
        if case .unavailable = AnthropicClient.mapError(status: 404, body: Data(), headers: response(404)) {} else {
            XCTFail("404 should map to .unavailable")
        }

        // 429 carries Retry-After.
        let rl = AnthropicClient.mapError(status: 429, body: Data(), headers: response(429, headers: ["retry-after": "7"]))
        XCTAssertEqual(rl, .rateLimited(retryAfter: 7))
    }
}
