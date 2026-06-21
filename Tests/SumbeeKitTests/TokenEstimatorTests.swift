import XCTest
@testable import SumbeeKit

final class TokenEstimatorTests: XCTestCase {
    func testEmptyIsZero() {
        XCTAssertEqual(TokenEstimator.estimate(""), 0)
    }

    func testRoughlyCharsOverHeuristic() {
        XCTAssertEqual(TokenEstimator.estimate(String(repeating: "a", count: 370)), 100)  // 370 / 3.7
    }

    func testMonotonic() {
        XCTAssertGreaterThan(
            TokenEstimator.estimate("a much longer string with many more characters"),
            TokenEstimator.estimate("short"))
    }
}
