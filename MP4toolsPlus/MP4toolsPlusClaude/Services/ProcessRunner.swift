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

/// Thread-safe accumulator for a process's piped output.
///
/// `FileHandle.readabilityHandler` closures are invoked on arbitrary
/// background threads, so all mutable state is guarded by a lock. Marked
/// `@unchecked Sendable` because that locking — not the compiler — provides
/// the safety guarantee.
private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrBuffer = Data()
    private var stderrText = ""
    private let onStderrLine: (@Sendable (String) -> Void)?

    init(onStderrLine: (@Sendable (String) -> Void)?) {
        self.onStderrLine = onStderrLine
    }

    func appendStdout(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        stdoutData.append(chunk)
    }

    func appendStderr(_ chunk: Data) {
        // Emit each completed line outside the lock to avoid re-entrancy.
        var linesToEmit: [String] = []
        lock.lock()
        stderrBuffer.append(chunk)
        stderrText += String(decoding: chunk, as: UTF8.self)
        // ffmpeg ends progress lines with either \n or \r.
        while let range = stderrBuffer.firstRange(of: Data([0x0a]))
            ?? stderrBuffer.firstRange(of: Data([0x0d])) {
            let lineData = stderrBuffer.subdata(in: stderrBuffer.startIndex..<range.lowerBound)
            stderrBuffer.removeSubrange(stderrBuffer.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                linesToEmit.append(line)
            }
        }
        lock.unlock()
        for line in linesToEmit { onStderrLine?(line) }
    }

    var stdoutString: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: stdoutData, as: UTF8.self)
    }

    var stderrString: String {
        lock.lock(); defer { lock.unlock() }
        return stderrText
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

        let accumulator = OutputAccumulator(onStderrLine: onStderrLine)

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            accumulator.appendStderr(chunk)
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            accumulator.appendStdout(chunk)
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

        return ProcessResult(exitCode: process.terminationStatus,
                             standardOutput: accumulator.stdoutString,
                             standardError: accumulator.stderrString)
    }
}
