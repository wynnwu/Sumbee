import Foundation

/// Resolve existing ancestors before appending new files: resolving only a nonexistent leaf
/// does not reliably resolve its parent symlinks on macOS.
enum MeetingLibraryPath {
    static func directory(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    static func sameRoot(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.resolvingSymlinksInPath().path == second.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func resolve(_ relative: String, in root: URL) throws -> URL {
        guard MeetingDocument.safeRelativePath(relative) else { throw MeetingDataError.invalidRecord }
        let base = directory(root).resolvingSymlinksInPath().standardizedFileURL
        var resolved = base
        for component in relative.split(separator: "/") {
            resolved = resolved.appendingPathComponent(String(component)).resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(base.path + "/") else { throw MeetingDataError.invalidRecord }
        }
        return resolved
    }
}
