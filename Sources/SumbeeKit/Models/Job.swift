import Foundation

/// A unit of summarization work shown in the UI. Transient (not persisted).
public struct Job: Identifiable, Equatable {
    public enum Input: Equatable, Sendable {
        case file(URL)
        case youtube(URL)
        /// Re-run a saved summary from its archived source (FR-037); optional model/format override.
        case regenerate(summaryURL: URL, override: ModelOverride?)
    }

    public enum Phase: Equatable, Sendable {
        case queued
        case extracting
        case fetching       // YouTube captions
        case summarizing
        case saving
        case done(URL)      // resulting asset URL
        case failed(String)
        case cancelled
        case waitingRetry(Date)   // auto-retry scheduled at this time

        public var isTerminal: Bool {
            switch self {
            case .done, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    public let id: UUID
    public var input: Input
    public var displayName: String
    public var styleID: UUID
    public var styleName: String
    public var phase: Phase
    /// Rolling preview of streamed output / status detail.
    public var preview: String
    /// How many times this job has been attempted (for backoff scheduling).
    public var attempt: Int = 0
    /// Cached extracted/archived input so retries don't re-extract or re-archive.
    public var prepared: PreparedInput? = nil
    /// When an auto-retry is scheduled (mirrors `.waitingRetry`).
    public var nextRetryAt: Date? = nil

    public init(id: UUID = UUID(),
                input: Input,
                displayName: String,
                styleID: UUID,
                styleName: String,
                phase: Phase = .queued,
                preview: String = "") {
        self.id = id
        self.input = input
        self.displayName = displayName
        self.styleID = styleID
        self.styleName = styleName
        self.phase = phase
        self.preview = preview
    }

    public var phaseLabel: String {
        switch phase {
        case .queued: return "Queued"
        case .extracting: return "Reading"
        case .fetching: return "Fetching captions"
        case .summarizing: return "Summarizing"
        case .saving: return "Saving"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .waitingRetry: return "Waiting to retry"
        }
    }
}
