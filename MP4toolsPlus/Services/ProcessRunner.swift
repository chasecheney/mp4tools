//
//  ProcessRunner.swift
//  MP4tools+
//
//  A thin async/await wrapper around `Foundation.Process`. Streams stderr
//  line-by-line so callers can parse progress, and resolves with the full
//  output and exit code on completion.
//

import Foundation

struct ProcessResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    var didSucceed: Bool { exitCode == 0 }
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .launchFailed(let m): return "Could not start the helper tool: \(m)"
        case .cancelled:           return "The operation was cancelled."
        }
    }
}

/// Runs external command-line tools off the main thread.
actor ProcessRunner {

    /// Run `executable` with `arguments`. `onStderrLine` is invoked for each
    /// line written to standard error (used for live progress parsing).
    func run(executable: URL,
             arguments: [String],
             onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> ProcessResult {

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Accumulators guarded by the actor's serial executor.
        var stdoutData = Data()
        var stderrBuffer = Data()
        var stderrText = ""

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
            stderrText += String(decoding: chunk, as: UTF8.self)

            // Emit complete lines (ffmpeg uses both \n and \r for progress).
            while let range = stderrBuffer.firstRange(of: Data([0x0a]))
                ?? stderrBuffer.firstRange(of: Data([0x0d])) {
                let lineData = stderrBuffer.subdata(in: stderrBuffer.startIndex..<range.lowerBound)
                stderrBuffer.removeSubrange(stderrBuffer.startIndex..<range.upperBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    onStderrLine?(line)
                }
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutData.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        // Wait for completion without blocking the actor thread.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in cont.resume() }
            }
        } onCancel: {
            process.terminate()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutPipe.fileHandleForReading.readabilityHandler = nil

        if Task.isCancelled { throw ProcessRunnerError.cancelled }

        let stdout = String(decoding: stdoutData, as: UTF8.self)
        return ProcessResult(exitCode: process.terminationStatus,
                             standardOutput: stdout,
                             standardError: stderrText)
    }
}
