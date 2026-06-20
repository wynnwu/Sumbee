import XCTest
@testable import SumbeeKit

final class ModelCatalogTests: XCTestCase {
    func testOpusRejectsTemperatureUsesEffort() {
        let caps = ModelCatalog.capabilities(for: "claude-opus-4-8")
        XCTAssertFalse(caps.supportsTemperature, "Opus 4.8 must NOT receive temperature (it 400s)")
        XCTAssertTrue(caps.supportsEffort)
        XCTAssertTrue(caps.supportsAdaptiveThinking)
        XCTAssertTrue(caps.effortLevels.contains("xhigh"))
    }

    func testSonnetSupportsTemperatureAndEffort() {
        let caps = ModelCatalog.capabilities(for: "claude-sonnet-4-6")
        XCTAssertTrue(caps.supportsTemperature)
        XCTAssertTrue(caps.supportsEffort)
    }

    func testHaikuSupportsTemperatureNoEffort() {
        let caps = ModelCatalog.capabilities(for: "claude-haiku-4-5")
        XCTAssertTrue(caps.supportsTemperature)
        XCTAssertFalse(caps.supportsEffort, "Haiku 4.5 must NOT receive effort (it errors)")
    }

    func testUnknownModelGetsConservativeDefault() {
        let caps = ModelCatalog.capabilities(for: "some-future-model")
        XCTAssertTrue(caps.supportsTemperature)
        XCTAssertFalse(caps.supportsEffort)
        XCTAssertFalse(caps.supportsAdaptiveThinking)
    }

    func testCustomOpusFamilyIdRejectsTemperature() {
        // A custom (non-preset) Opus 4.7 id must still NOT receive temperature (avoids a 400).
        let caps = ModelCatalog.capabilities(for: "claude-opus-4-7")
        XCTAssertFalse(caps.supportsTemperature)
        XCTAssertTrue(caps.supportsEffort)
        XCTAssertTrue(caps.supportsAdaptiveThinking)

        XCTAssertFalse(ModelCatalog.capabilities(for: "claude-fable-5").supportsTemperature)
    }

    func testDefaultModelIsLatestOpus() {
        XCTAssertEqual(ModelCatalog.defaultModelID, "claude-opus-4-8")
        XCTAssertTrue(ModelCatalog.isPreset("claude-opus-4-8"))
        XCTAssertFalse(ModelCatalog.isPreset("custom-thing"))
    }
}
