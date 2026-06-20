import Foundation

/// Where a style appears in the UI and how it is invoked.
public enum StyleChannel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Rendered as a drop zone that accepts transcript files.
    case file
    /// Rendered as a button under the YouTube URL field.
    case youtube

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .file: return "File (drop zone)"
        case .youtube: return "YouTube (button)"
        }
    }
}

/// Optional per-style overrides for generation. `nil` fields fall back to global settings.
public struct ModelOverride: Codable, Equatable, Sendable {
    public var model: String?
    public var temperature: Double?
    public var effort: String?
    public var maxOutputTokens: Int?
    public var outputFormat: OutputFormat?

    public init(model: String? = nil,
                temperature: Double? = nil,
                effort: String? = nil,
                maxOutputTokens: Int? = nil,
                outputFormat: OutputFormat? = nil) {
        self.model = model
        self.temperature = temperature
        self.effort = effort
        self.maxOutputTokens = maxOutputTokens
        self.outputFormat = outputFormat
    }

    /// True when nothing is overridden (used to omit the block on disk).
    public var isEmpty: Bool {
        model == nil && temperature == nil && effort == nil
            && maxOutputTokens == nil && outputFormat == nil
    }
}

/// The core configurable object. A style is a named prompt that also names a library folder.
///
/// Persisted on disk at `<root>/<name>/style-definition/style-definition.md` — the prompt is
/// the Markdown body, the rest is YAML frontmatter. The on-disk library, not config, is the
/// source of truth (see specs contract `file-layout.md`).
public struct SummaryStyle: Identifiable, Equatable, Sendable {
    /// Stable identifier; survives folder renames.
    public var id: UUID
    /// Display name AND folder name (e.g. "Meetings — General").
    public var name: String
    public var channel: StyleChannel
    /// The instruction text sent to the model (the shared output convention is appended by the app).
    public var prompt: String
    /// Sort order in the UI.
    public var order: Int
    /// Hide a style without deleting it.
    public var enabled: Bool
    public var modelOverride: ModelOverride?

    public init(id: UUID = UUID(),
                name: String,
                channel: StyleChannel,
                prompt: String,
                order: Int,
                enabled: Bool = true,
                modelOverride: ModelOverride? = nil) {
        self.id = id
        self.name = name
        self.channel = channel
        self.prompt = prompt
        self.order = order
        self.enabled = enabled
        self.modelOverride = modelOverride
    }
}
