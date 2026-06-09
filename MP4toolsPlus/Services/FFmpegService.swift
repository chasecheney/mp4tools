//
//  FFmpegService.swift
//  MP4tools+
//
//  High-level engine that executes an `Operation` end-to-end and reports
//  progress as a fraction (0...1) parsed from ffmpeg's stderr.
//

import Foundation

actor FFmpegService {
    private let runner = ProcessRunner()

    /// Run a job. `progress` is called on a background context; callers should
    /// hop to the main actor before touching UI state.
    func execute(source: MediaFile,
                 operation: Operation,
                 selectedTracks: [MediaTrack],
                 output: URL,
                 externalSubtitle: URL? = nil,
                 progress: @Sendable @escaping (Double) -> Void) async throws {

        let ffmpeg = try BinaryLocator.ffmpeg
        let totalDuration = source.durationSeconds ?? 0

        switch operation {
        case .convert(let preset):
            let args = FFmpegCommandBuilder.convert(
                input: source, tracks: selectedTracks, preset: preset,
                output: output, externalSubtitle: externalSubtitle)
            try await runReporting(ffmpeg, args, totalDuration, progress)

        case .splitBySize(let maxBytes):
            let pattern = output.deletingPathExtension().path + "_%03d.mp4"
            let args = FFmpegCommandBuilder.splitBySize(
                input: source.url, maxBytes: maxBytes, outputPattern: pattern)
            try await runReporting(ffmpeg, args, totalDuration, progress)

        case .splitByTime(let start, let end):
            let args = FFmpegCommandBuilder.splitByTime(
                input: source.url, start: start, end: end, output: output)
            try await runReporting(ffmpeg, args, end - start, progress)

        case .join(let additional):
            let list = try writeConcatList(first: source.url, rest: additional)
            defer { try? FileManager.default.removeItem(at: list) }
            let args = FFmpegCommandBuilder.join(listFile: list, output: output)
            try await runReporting(ffmpeg, args, totalDuration, progress)

        case .extractTracks(let trackIDs):
            let toExtract = selectedTracks.filter { trackIDs.contains($0.id) }
            for (i, track) in toExtract.enumerated() {
                let ext = Self.elementaryExtension(for: track)
                let dest = output.deletingPathExtension()
                    .appendingPathExtension("track\(track.streamIndex).\(ext)")
                let args = FFmpegCommandBuilder.extract(
                    input: source.url, track: track, output: dest)
                try await runReporting(ffmpeg, args, totalDuration) { p in
                    // Weight progress across the set of extractions.
                    progress((Double(i) + p) / Double(max(toExtract.count, 1)))
                }
            }

        case .adjustPAR(let num, let den):
            let args = FFmpegCommandBuilder.adjustPAR(
                input: source.url, numerator: num, denominator: den, output: output)
            try await runReporting(ffmpeg, args, totalDuration, progress)
        }
    }

    // MARK: - Helpers

    private func runReporting(_ ffmpeg: URL,
                              _ args: [String],
                              _ totalDuration: Double,
                              _ progress: @Sendable @escaping (Double) -> Void) async throws {
        let result = try await runner.run(executable: ffmpeg, arguments: args) { line in
            if let t = Self.parseProgressTime(line), totalDuration > 0 {
                progress(min(max(t / totalDuration, 0), 1))
            }
        }
        guard result.didSucceed else {
            throw NSError(domain: "FFmpegService", code: Int(result.exitCode),
                          userInfo: [NSLocalizedDescriptionKey:
                            Self.friendlyError(from: result.standardError)])
        }
        progress(1.0)
    }

    /// Parse `time=00:01:23.45` from an ffmpeg progress line into seconds.
    static func parseProgressTime(_ line: String) -> Double? {
        guard let range = line.range(of: "time=") else { return nil }
        let rest = line[range.upperBound...]
        let token = rest.prefix { !$0.isWhitespace }
        let parts = token.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2])
        else { return nil }
        return h * 3600 + m * 60 + s
    }

    /// Pull the last meaningful error line out of ffmpeg's verbose stderr.
    static func friendlyError(from stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map(String.init)
        if let err = lines.last(where: { $0.lowercased().contains("error")
            || $0.contains("Invalid") || $0.contains("No such") }) {
            return err.trimmingCharacters(in: .whitespaces)
        }
        return "Processing failed. See the log for details."
    }

    private func writeConcatList(first: URL, rest: [URL]) throws -> URL {
        let all = [first] + rest
        let body = all.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: "\n")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("concat-\(UUID().uuidString).txt")
        try body.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    private static func elementaryExtension(for track: MediaTrack) -> String {
        switch track.kind {
        case .video:
            return track.codec.contains("265") || track.codec.contains("hevc") ? "h265" : "h264"
        case .audio:
            switch track.codec {
            case let c where c.contains("aac"): return "aac"
            case let c where c.contains("ac3"): return "ac3"
            case let c where c.contains("dts"): return "dts"
            default: return "mka"
            }
        case .subtitle:
            return track.codec.contains("subrip") ? "srt" : "sub"
        default:
            return "bin"
        }
    }
}
