import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }

    /// Last meaningful error line (e.g. "ERROR: …" from yt-dlp).
    var errorSummary: String {
        let lines = stderr.split(separator: "\n").map(String.init)
        return lines.last(where: { $0.contains("ERROR") }) ?? lines.last ?? String(localized: "Unknown error (exit code \(status))")
    }
}

/// Runs external programs (yt-dlp) asynchronously and delivers their output line by line.
enum ProcessRunner {
    /// Homebrew paths first, so yt-dlp finds ffmpeg and deno.
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        env["PATH"] = (searchPaths + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        return env
    }

    static func findTool(_ name: String) -> URL? {
        for dir in searchPaths {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    static func run(_ executable: URL, arguments: [String],
                    onLine: (@Sendable (String) -> Void)? = nil) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        return try await withTaskCancellationHandler {
            async let out = collect(outPipe.fileHandleForReading, onLine)
            async let err = collect(errPipe.fileHandleForReading, onLine)
            let (stdout, stderr) = try await (out, err)
            process.waitUntilExit()
            try Task.checkCancellation()
            return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private static func collect(_ handle: FileHandle, _ onLine: (@Sendable (String) -> Void)?) async throws -> String {
        var lines: [String] = []
        for try await line in handle.bytes.lines {
            onLine?(line)
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
