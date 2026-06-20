import Foundation

/// Converts a WebVTT caption file into clean transcript text: strips cue numbers,
/// timestamp lines, and inline tags; de-duplicates the rolling/overlapping lines that
/// auto-generated captions produce; optionally injects coarse `(mm:ss)` markers.
public enum VTTParser {

    public static func parse(_ vtt: String,
                             includeTimestamps: Bool = true,
                             interval: TimeInterval = 30) -> String {
        let normalized = vtt.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var out: [String] = []
        var lastLine = ""
        var lastStampEmitted = -interval
        var i = 0

        while i < lines.count {
            let line = lines[i]
            if line.contains("-->") {
                let start = parseStart(line)
                i += 1
                var cueLines: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    cueLines.append(clean(lines[i]))
                    i += 1
                }
                for cl in cueLines where !cl.isEmpty {
                    if cl == lastLine { continue }       // collapse rolling repeats
                    if includeTimestamps, let s = start, s >= lastStampEmitted + interval {
                        out.append("(\(mmss(s)))")
                        lastStampEmitted = s
                    }
                    out.append(cl)
                    lastLine = cl
                }
            } else {
                i += 1
            }
        }

        return out.joined(separator: "\n")
    }

    // MARK: Helpers

    static func clean(_ raw: String) -> String {
        var s = stripTags(raw)
        s = decodeEntities(s)
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func stripTags(_ s: String) -> String {
        var result = ""
        var inTag = false
        for ch in s {
            if ch == "<" { inTag = true }
            else if ch == ">" { inTag = false }
            else if !inTag { result.append(ch) }
        }
        return result
    }

    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&#39;", with: "'")
         .replacingOccurrences(of: "&apos;", with: "'")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    /// Parse the start time from a cue line: "HH:MM:SS.mmm --> ..." or "MM:SS.mmm --> ...".
    static func parseStart(_ line: String) -> TimeInterval? {
        guard let arrow = line.range(of: "-->") else { return nil }
        let head = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let token = head.split(separator: " ").first.map(String.init) ?? head
        return seconds(fromTimestamp: token)
    }

    static func seconds(fromTimestamp ts: String) -> TimeInterval? {
        // Forms: HH:MM:SS.mmm | MM:SS.mmm  (also tolerate comma decimals)
        let cleaned = ts.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":").map(String.init)
        guard !parts.isEmpty else { return nil }
        var total: TimeInterval = 0
        for part in parts {
            guard let v = Double(part) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    static func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let secs = total % 60
        return "\(minutes):" + String(format: "%02d", secs)
    }
}
