import Foundation

/// What request parameters a given model accepts. Treated as *data* so new models can be
/// added without touching the request builder (spec FR-013 / SC-010).
public struct ModelCapabilities: Equatable, Sendable {
    public var supportsTemperature: Bool
    public var supportsEffort: Bool
    public var effortLevels: [String]
    public var supportsAdaptiveThinking: Bool
    public var maxOutputCeiling: Int
    /// Approximate context window in tokens, used only for a rough oversized-input warning.
    public var approxContextTokens: Int

    public init(supportsTemperature: Bool,
                supportsEffort: Bool,
                effortLevels: [String],
                supportsAdaptiveThinking: Bool,
                maxOutputCeiling: Int,
                approxContextTokens: Int = 200_000) {
        self.supportsTemperature = supportsTemperature
        self.supportsEffort = supportsEffort
        self.effortLevels = effortLevels
        self.supportsAdaptiveThinking = supportsAdaptiveThinking
        self.maxOutputCeiling = maxOutputCeiling
        self.approxContextTokens = approxContextTokens
    }

    /// Conservative defaults for an unknown/custom model id: allow temperature (widely
    /// accepted by older/most models), no effort, no adaptive thinking, modest ceiling.
    public static let conservativeDefault = ModelCapabilities(
        supportsTemperature: true,
        supportsEffort: false,
        effortLevels: [],
        supportsAdaptiveThinking: false,
        maxOutputCeiling: 8192,
        approxContextTokens: 200_000
    )

    /// Profile for the Opus 4.7+ / Fable / Mythos family: rejects temperature, uses effort +
    /// adaptive thinking. Used for custom ids in that family so we never send a 400-inducing param.
    public static let opusFamily = ModelCapabilities(
        supportsTemperature: false,
        supportsEffort: true,
        effortLevels: ModelCatalog.opusEffortLevels,
        supportsAdaptiveThinking: true,
        maxOutputCeiling: 128_000,
        approxContextTokens: 1_000_000
    )
}

/// A selectable model preset.
public struct ModelPreset: Identifiable, Equatable, Sendable {
    public var id: String          // the model id string
    public var displayName: String
    public var capabilities: ModelCapabilities

    public init(id: String, displayName: String, capabilities: ModelCapabilities) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

/// The set of shipped model presets and the capability lookup.
///
/// Capabilities reflect the current Anthropic Messages API: the Opus 4.7/4.8 family
/// rejects `temperature`/`budget_tokens` and uses `output_config.effort` + adaptive
/// thinking; Sonnet 4.6 / Haiku 4.5 accept `temperature`; Haiku 4.5 has no `effort`.
public enum ModelCatalog {
    public static let opusEffortLevels = ["low", "medium", "high", "xhigh", "max"]
    public static let sonnetEffortLevels = ["low", "medium", "high", "max"]

    public static let presets: [ModelPreset] = [
        ModelPreset(
            id: "claude-opus-4-8",
            displayName: "Claude Opus 4.8 (latest)",
            capabilities: ModelCapabilities(
                supportsTemperature: false,
                supportsEffort: true,
                effortLevels: opusEffortLevels,
                supportsAdaptiveThinking: true,
                maxOutputCeiling: 128_000,
                approxContextTokens: 1_000_000
            )
        ),
        ModelPreset(
            id: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            capabilities: ModelCapabilities(
                supportsTemperature: true,
                supportsEffort: true,
                effortLevels: sonnetEffortLevels,
                supportsAdaptiveThinking: true,
                maxOutputCeiling: 64_000,
                approxContextTokens: 1_000_000
            )
        ),
        ModelPreset(
            id: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            capabilities: ModelCapabilities(
                supportsTemperature: true,
                supportsEffort: false,
                effortLevels: [],
                supportsAdaptiveThinking: false,
                maxOutputCeiling: 64_000,
                approxContextTokens: 200_000
            )
        ),
    ]

    public static let defaultModelID = "claude-opus-4-8"

    /// Model id families (substrings) that REJECT `temperature`/`budget_tokens` and use
    /// `output_config.effort` + adaptive thinking (Opus 4.7+, Fable, Mythos). A custom id in
    /// one of these families must NOT be sent temperature, or the API returns 400.
    static let noTemperatureFamilies = ["opus-4-7", "opus-4-8", "opus-4-9", "fable", "mythos"]

    /// Capabilities for any model id - exact preset match, then a family heuristic for custom
    /// ids, else a conservative default. Treating capabilities as data keeps the request
    /// builder forward-compatible (FR-013 / SC-010).
    public static func capabilities(for modelID: String) -> ModelCapabilities {
        if let preset = presets.first(where: { $0.id == modelID }) {
            return preset.capabilities
        }
        let id = modelID.lowercased()
        if noTemperatureFamilies.contains(where: { id.contains($0) }) {
            return .opusFamily
        }
        return .conservativeDefault
    }

    /// True when `modelID` is one of the known presets (vs. a custom id).
    public static func isPreset(_ modelID: String) -> Bool {
        presets.contains { $0.id == modelID }
    }
}
