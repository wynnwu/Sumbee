import Foundation

/// Aligns token timing to the original recognized text, preserving any unaligned text as untimed.
enum TranscriptAssembler {
    struct Output {
        var turns: [MeetingTurn]
        var speakers: [MeetingSpeaker]
    }

    static func assemble(_ recognition: MeetingRecognition) -> Output {
        guard !recognition.text.isEmpty else { return Output(turns: [], speakers: []) }
        let intervals = recognition.intervals.filter {
            $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start
        }.sorted { $0.start == $1.start ? $0.speakerKey < $1.speakerKey : $0.start < $1.start }
        var keys: [String] = []
        for interval in intervals where !keys.contains(interval.speakerKey) { keys.append(interval.speakerKey) }
        var speakers = keys.enumerated().map {
            MeetingSpeaker(genericLabel: "Speaker \($0.offset + 1)", clusterKeys: [$0.element])
        }
        let unknown = MeetingSpeaker(genericLabel: "Unknown speaker")
        let identities = Dictionary(uniqueKeysWithValues: zip(keys, speakers.map(\.id)))
        var turns: [MeetingTurn] = []

        func identity(start: Double?, end: Double?) -> UUID {
            guard let start, let end else { return unknown.id }
            var overlaps: [String: Double] = [:]
            for interval in intervals {
                let overlap = max(0, min(end, interval.end) - max(start, interval.start))
                if overlap > 0 { overlaps[interval.speakerKey, default: 0] += overlap }
            }
            let ranked = overlaps.sorted { $0.value > $1.value }
            guard let best = ranked.first, ranked.count == 1 || best.value - ranked[1].value > 0.0001 else { return unknown.id }
            return identities[best.key] ?? unknown.id
        }
        func append(_ text: String, start: Double?, end: Double?) {
            guard !text.isEmpty else { return }
            let speakerID = identity(start: start, end: end)
            if let last = turns.last, last.speakerID == speakerID,
               (last.start == nil) == (start == nil),
               last.text.count < 800,
               !(last.text.count >= 480 && ".!?".contains(last.text.trimmingCharacters(in: .whitespacesAndNewlines).last ?? " ")),
               start == nil || (start! - (last.end ?? start!) <= 1.5 && start! - (last.start ?? start!) < 30) {
                turns[turns.count - 1].text += text
                if let end { turns[turns.count - 1].end = max(last.end ?? end, end) }
            } else {
                turns.append(.init(text: text, start: start, end: end, speakerID: speakerID))
            }
        }

        // Preserve word boundaries while aggregating SentencePiece fragments.
        var words: [MeetingRecognition.Token] = []
        for token in recognition.tokens {
            let value = token.text.replacingOccurrences(of: "▁", with: " ")
            guard !value.isEmpty else { continue }
            if value.first?.isWhitespace == true || words.isEmpty {
                words.append(.init(text: value, start: token.start, end: token.end))
            } else {
                words[words.count - 1].text += value
                words[words.count - 1].end = token.end
            }
        }
        let original = recognition.text
        var cursor = original.startIndex
        for word in words {
            let needle = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty, let range = original.range(of: needle, range: cursor..<original.endIndex) else { continue }
            let gap = String(original[cursor..<range.lowerBound])
            var prefix = ""
            if gap.allSatisfy(\.isWhitespace) { prefix = gap }
            else { append(gap, start: nil, end: nil) }
            var start: Double?, end: Double?
            if let a = word.start, let b = word.end, a.isFinite, b.isFinite,
               a >= 0, b >= a, a <= recognition.duration {
                start = a
                end = min(b, recognition.duration)
            }
            append(prefix + String(original[range]), start: start, end: end)
            cursor = range.upperBound
        }
        append(String(original[cursor...]), start: nil, end: nil)
        if turns.contains(where: { $0.speakerID == unknown.id }) { speakers.append(unknown) }
        return Output(turns: turns, speakers: speakers)
    }
}
