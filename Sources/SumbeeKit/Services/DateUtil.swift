import Foundation

/// Centralized date formatting for filenames and metadata (filesystem-safe, local time).
public enum DateUtil {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// "yyyy-MM-dd" - date-only, used for YouTube file naming ("Youtube - <date> - <title>").
    public static func dateStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// "yyyy-MM-dd HHmm" - used as the asset filename prefix.
    public static func assetTimestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f.string(from: date)
    }

    /// "yyyy-MM-dd_HHmmss" - used in archived source filenames (no spaces/colons).
    public static func archiveTimestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: date)
    }

    /// ISO-8601 with local offset, e.g. "2026-06-20T14:32:05-07:00".
    public static func iso(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f.string(from: date)
    }
}
