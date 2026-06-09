//
//  MediaInspector.swift
//  MP4tools+
//
//  Uses ffprobe to read a media file's container + stream metadata and maps
//  the JSON output into our `MediaFile` model.
//

import Foundation

actor MediaInspector {
    private let runner = ProcessRunner()

    /// Probe a file on disk and return a populated `MediaFile`.
    func inspect(url: URL) async throws -> MediaFile {
        let ffprobe = try BinaryLocator.ffprobe
        let args = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            url.path
        ]
        let result = try await runner.run(executable: ffprobe, arguments: args)
        guard result.didSucceed else {
            throw NSError(domain: "MediaInspector", code: Int(result.exitCode),
                          userInfo: [NSLocalizedDescriptionKey:
                            "ffprobe could not read \(url.lastPathComponent)."])
        }
        let probe = try JSONDecoder().decode(FFProbeOutput.self,
                                             from: Data(result.standardOutput.utf8))
        return map(probe, url: url)
    }

    private func map(_ probe: FFProbeOutput, url: URL) -> MediaFile {
        let tracks: [MediaTrack] = probe.streams.compactMap { s in
            guard let kind = TrackKind(rawValue: s.codec_type) else { return nil }
            return MediaTrack(
                streamIndex: s.index,
                kind: kind,
                codec: s.codec_name ?? "unknown",
                language: s.tags?["language"],
                title: s.tags?["title"],
                width: s.width,
                height: s.height,
                frameRate: s.parsedFrameRate,
                channels: s.channels,
                channelLayout: s.channel_layout,
                sampleRate: s.sample_rate.flatMap(Int.init),
                // Default: pick first video, first audio, no subtitles.
                isSelected: kind == .video || kind == .audio
            )
        }
        return MediaFile(
            url: url,
            tracks: tracks,
            durationSeconds: probe.format.duration.flatMap(Double.init),
            sizeBytes: probe.format.size.flatMap(Int64.init),
            formatName: probe.format.format_name
        )
    }
}

// MARK: - ffprobe JSON shapes

private struct FFProbeOutput: Decodable {
    let streams: [Stream]
    let format: Format

    struct Stream: Decodable {
        let index: Int
        let codec_type: String
        let codec_name: String?
        let width: Int?
        let height: Int?
        let channels: Int?
        let channel_layout: String?
        let sample_rate: String?
        let r_frame_rate: String?
        let tags: [String: String]?

        /// ffprobe reports frame rate as a "num/den" string.
        var parsedFrameRate: Double? {
            guard let r = r_frame_rate else { return nil }
            let parts = r.split(separator: "/").compactMap { Double($0) }
            guard parts.count == 2, parts[1] != 0 else { return nil }
            return parts[0] / parts[1]
        }
    }

    struct Format: Decodable {
        let format_name: String?
        let duration: String?
        let size: String?
    }
}
