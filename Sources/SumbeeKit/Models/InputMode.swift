import Foundation

/// Top-level input mode chosen in the left rail (FR-068). Surfaces the existing `StyleChannel`
/// split as navigation: Transcripts shows file drop zones, YouTube hosts the URL/playlist input.
public enum InputMode: String, CaseIterable, Identifiable, Sendable {
    case transcripts
    case youtube
    case meetings

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .transcripts: return "Transcripts"
        case .youtube: return "YouTube"
        case .meetings: return "Meetings"
        }
    }

    /// SF Symbol for the rail.
    public var icon: String {
        switch self {
        case .transcripts: return "doc.text"
        case .youtube: return "play.rectangle.fill"
        case .meetings: return "waveform"
        }
    }
}
