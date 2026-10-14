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

    func testOpus55PresetRejectsTemperature() {
        // Regression: Opus 5.5 (the current flagship) 400s on `temperature` like the rest of
        // the Opus/Claude-5 line; it must resolve to effort + adaptive thinking, no temperature.
        let caps = ModelCatalog.capabilities(for: "claude-opus-5-5")
        XCTAssertFalse(caps.supportsTemperature, "Opus 5.5 must NOT receive temperature (it 400s)")
        XCTAssertTrue(caps.supportsEffort)
        XCTAssertTrue(caps.supportsAdaptiveThinking)
        XCTAssertTrue(caps.effortLevels.contains("xhigh"))
        XCTAssertTrue(ModelCatalog.isPreset("claude-opus-5-5"))
    }

    func testCustomClaude5IdsRejectTemperature() {
        // Custom (non-preset) Claude 5 ids must also avoid the temperature 400, while the
        // `*-4-*` ids that still accept it keep supporting it.
        for id in ["claude-opus-5", "claude-sonnet-5-5", "claude-sonnet-5", "claude-haiku-5-5"] {
            XCTAssertFalse(ModelCatalog.capabilities(for: id).supportsTemperature,
                           "\(id) must NOT receive temperature (it 400s)")
        }
        XCTAssertTrue(ModelCatalog.capabilities(for: "claude-sonnet-4-6").supportsTemperature)
        XCTAssertTrue(ModelCatalog.capabilities(for: "claude-haiku-4-5").supportsTemperature)
    }

    func testDefaultModelIsLatestOpus() {
        XCTAssertEqual(ModelCatalog.defaultModelID, "claude-opus-5-5")
        XCTAssertTrue(ModelCatalog.isPreset("claude-opus-5-5"))
        XCTAssertTrue(ModelCatalog.isPreset("claude-opus-4-8"))
        XCTAssertFalse(ModelCatalog.isPreset("custom-thing"))
    }
}
