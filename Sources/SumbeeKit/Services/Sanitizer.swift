import Foundation

/// Filename sanitization and collision handling for saved assets.
public enum Sanitizer {
    /// Characters illegal/awkward in filenames on macOS (and cross-platform-friendly).
    private static let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")

    /// Sanitize a model-generated title into a safe filename component:
    /// strip illegal characters, collapse whitespace, trim, and cap length.
    public static func sanitizeTitle(_ raw: String, maxLength: Int = 80) -> String {
        // Replace illegal characters with a space.
        let scalars = raw.unicodeScalars.map { illegal.contains($0) ? " " : Character($0) }
        var cleaned = String(scalars)

        // Replace control/newline characters with spaces.
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
                         .replacingOccurrences(of: "\r", with: " ")
                         .replacingOccurrences(of: "\t", with: " ")

        // Collapse runs of whitespace to single spaces.
        let collapsed = cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        var result = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)

        // Avoid leading dots (hidden files) and trailing dots/spaces (Finder dislikes).
        while result.hasPrefix(".") { result.removeFirst() }
        result = result.trimmingCharacters(in: .whitespaces)

        if result.count > maxLength {
            result = String(result.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        }

        return result.isEmpty ? "Untitled" : result
    }

    /// Return a filename that does not collide with existing files in `directory`,
    /// appending " (2)", " (3)", … before the extension as needed.
    ///
    /// `baseName` is the name WITHOUT extension; `ext` is without the leading dot.
    public static func uniqueFilename(baseName: String,
                                      ext: String,
                                      in directory: URL,
                                      fileManager: FileManager = .default) -> String {
        func candidate(_ suffix: String) -> String {
            let stem = baseName + suffix
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        var suffix = ""
        var counter = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate(suffix)).path) {
            suffix = " (\(counter))"
            counter += 1
        }
        return candidate(suffix)
    }
}
