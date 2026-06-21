import Foundation

/// Fast, offline, order-of-magnitude token estimate for geek mode's prompt preview (FR-039).
/// Deliberately a heuristic (~chars / 3.7) — an inspect-mode estimate, not a billing figure.
public enum TokenEstimator {
    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return Int((Double(text.count) / 3.7).rounded(.up))
    }
}
