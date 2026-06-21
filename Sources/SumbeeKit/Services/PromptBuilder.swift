import Foundation

/// Assembles the system prompt (style prompt + shared, format-aware output convention)
/// and the user message (transcript + optional video metadata). The convention is what
/// makes the per-style prompts format-agnostic and enables automatic titling (spec §7.4).
public enum PromptBuilder {

    public static func systemPrompt(style: SummaryStyle,
                                    format: OutputFormat,
                                    htmlStylingPrompt: String,
                                    globalPrompt: String = "") -> String {
        // Assembled order: shared global system prompt → style prompt → app output convention.
        var parts: [String] = []
        let global = globalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !global.isEmpty { parts.append(global) }
        parts.append(style.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        parts.append(convention(format: format, htmlStylingPrompt: htmlStylingPrompt))
        return parts.joined(separator: "\n\n")
    }

    public static func userMessage(transcript: String, videoMeta: VideoMeta? = nil) -> String {
        guard let meta = videoMeta else { return transcript }
        var header = "Video metadata:\n"
        header += "- Title: \(meta.title)\n"
        if let channel = meta.channel { header += "- Channel: \(channel)\n" }
        if let duration = meta.durationString { header += "- Duration: \(duration)\n" }
        if let date = meta.uploadDate { header += "- Uploaded: \(date)\n" }
        header += "\nTranscript (timestamps in (mm:ss) where available):\n\n"
        return header + transcript
    }

    /// The shared output convention, format-aware. Injected by the app, not stored per style.
    static func convention(format: OutputFormat, htmlStylingPrompt: String) -> String {
        switch format {
        case .markdown:
            return """
            Output format and structure:
            - Write in GitHub-flavored Markdown.
            - Begin your response with a single top-level title on the first line: \
            `# <a concise 4–8 word title>`, then the body. Use `##` for the section \
            headings described above.
            - Output only the summary document itself — no preamble, no sign-off, and no \
            commentary about the task or these instructions.
            - Never invent information that is not supported by the source; if something is \
            unclear or missing, say so plainly.
            """
        case .html:
            var s = """
            Output format and structure:
            - Produce a complete, self-contained HTML document (from `<!DOCTYPE html>` to \
            `</html>`).
            - Begin the document body with a single `<h1>` containing a concise 4–8 word \
            title, then the body. Map the sections described above onto `<h2>` headings.
            - Output only the HTML document — no Markdown code fences, no preamble, and no \
            commentary.
            - Never invent information that is not supported by the source; if something is \
            unclear or missing, say so plainly.
            """
            let styling = htmlStylingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !styling.isEmpty {
                s += "\n\nApply this consistent styling to the HTML (colors, fonts, layout):\n" + styling
            }
            return s
        }
    }

    /// Extract the document title from model output: first Markdown `#` line or first `<h1>`.
    /// Returns nil if none found (caller falls back to the source name).
    public static func extractTitle(from output: String, format: OutputFormat) -> String? {
        switch format {
        case .markdown:
            for rawLine in output.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("# ") {
                    return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                }
                if line.hasPrefix("#") && !line.hasPrefix("##") {
                    return line.dropFirst().trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        case .html:
            guard let open = output.range(of: "<h1", options: .caseInsensitive),
                  let gt = output.range(of: ">", range: open.upperBound..<output.endIndex),
                  let close = output.range(of: "</h1>", options: .caseInsensitive,
                                           range: gt.upperBound..<output.endIndex) else {
                return nil
            }
            let inner = String(output[gt.upperBound..<close.lowerBound])
            return stripTags(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func stripTags(_ s: String) -> String {
        var result = ""
        var inTag = false
        for ch in s {
            if ch == "<" { inTag = true }
            else if ch == ">" { inTag = false }
            else if !inTag { result.append(ch) }
        }
        return result
    }
}
