import Foundation

/// Minimal wrapper around `Process` for invoking system binaries (unzip, yt-dlp).
/// Always called off the main actor. Reads stdout/stderr concurrently to avoid pipe deadlock.
public enum ProcessRunner {
    public struct Result {
        public let status: Int32
        public let stdout: Data
        public let stderr: Data
        public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
        public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
    }

    public enum RunError: Error, CustomStringConvertible {
        case launchFailed(String)
        public var description: String {
            switch self { case .launchFailed(let m): return "Failed to launch process: \(m)" }
        }
    }

    public static func run(_ launchPath: String,
                           _ arguments: [String],
                           environment: [String: String]? = nil) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Read stderr concurrently so a full stderr buffer can't block the stdout read.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            throw RunError.launchFailed(error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        group.wait()

        return Result(status: process.terminationStatus, stdout: outData, stderr: errData)
    }
}
