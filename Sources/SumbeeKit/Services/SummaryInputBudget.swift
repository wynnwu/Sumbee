import Foundation

/// The single prompt/budget path for preview, execution, and retry.
enum SummaryInputBudget {
    struct Assembly {
        var system: String
        var user: String
        var model: String
        var capabilities: ModelCapabilities
        var maxTokens: Int
        var truncated: Bool
    }

    static func assemble(_ prepared: PreparedInput, style: SummaryStyle, settings: AppSettings) throws -> Assembly {
        if prepared.kind == .meeting {
            guard let root = prepared.libraryRoot, MeetingLibraryPath.sameRoot(root, settings.libraryRootURL) else {
                throw MeetingSummaryError.wrongLibrary
            }
        }
        let format = style.modelOverride?.outputFormat ?? settings.outputFormat
        var system = PromptBuilder.systemPrompt(style: style, format: format,
            htmlStylingPrompt: settings.htmlStylingPrompt, globalPrompt: settings.systemPrompt)
        if prepared.kind == .meeting { system += "\n\n" + PromptBuilder.meetingContext }
        let model = style.modelOverride?.model ?? settings.model
        let caps = ModelCatalog.capabilities(for: model)
        let output = min(max(style.modelOverride?.maxOutputTokens ?? settings.maxOutputTokens, 256), caps.maxOutputCeiling)
        let allowed = max(8000, caps.approxContextTokens * 4 - (output + 4000) * 4 - system.count)
        var text = prepared.text
        var truncated = false
        if prepared.kind == .meeting {
            // Keep the estimate conservative for non-ASCII text instead of treating each character
            // as a quarter token. Exact tokenization remains the provider's responsibility.
            let estimated = max(TokenEstimator.estimate(system + text), (system.utf8.count + text.utf8.count + 2) / 3)
            guard text.count <= allowed, estimated + output + 4000 <= caps.approxContextTokens else {
                throw MeetingSummaryError.oversized(allowed)
            }
        } else if text.count > allowed {
            text = String(text.prefix(allowed)) + "\n\n[NOTE: transcript truncated to fit the model's context window.]"
            truncated = true
        }
        return Assembly(system: system, user: PromptBuilder.userMessage(transcript: text, videoMeta: prepared.videoMeta),
            model: model, capabilities: caps, maxTokens: output, truncated: truncated)
    }
}
