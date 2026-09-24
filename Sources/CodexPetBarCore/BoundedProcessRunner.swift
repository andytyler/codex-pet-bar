import Darwin
import Foundation

public struct BoundedProcessResult: Sendable {
    public let exitCode: Int32
    public let output: String
    public let error: String
    public let failure: String?
}

public enum BoundedProcessRunner {
    /// File-backed capture drains both streams as the child writes them, without
    /// pipe-buffer deadlocks or reads waiting for EOF after a failed launch.
    public static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 60
    ) -> BoundedProcessResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-pet-process-\(UUID().uuidString)")
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            FileManager.default.createFile(atPath: errorURL.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            let errorHandle = try FileHandle(forWritingTo: errorURL)
            defer { try? outputHandle.close(); try? errorHandle.close() }
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = outputHandle
            process.standardError = errorHandle
            let exited = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in exited.signal() }
            do {
                try process.run()
            } catch {
                return .init(exitCode: 1, output: "", error: "", failure: error.localizedDescription)
            }
            let timedOut = exited.wait(timeout: .now() + max(0.01, timeout)) == .timedOut
            if timedOut && process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 1) == .timedOut && process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = exited.wait(timeout: .now() + 1)
                }
            }
            return .init(
                exitCode: process.isRunning ? -1 : process.terminationStatus,
                output: readCapture(outputURL),
                error: readCapture(errorURL),
                failure: timedOut ? "The installer timed out after \(Int(timeout)) seconds. Try again from Integrations." : nil
            )
        } catch {
            return .init(exitCode: 1, output: "", error: "", failure: error.localizedDescription)
        }
    }

    private static func readCapture(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let limit = 1_048_576
        let data = (try? handle.read(upToCount: limit + 1)) ?? Data()
        let suffix = data.count > limit ? "\n[Output truncated]" : ""
        return String(decoding: data.prefix(limit), as: UTF8.self) + suffix
    }
}
