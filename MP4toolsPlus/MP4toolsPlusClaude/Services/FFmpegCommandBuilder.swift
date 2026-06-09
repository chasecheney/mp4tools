//
//  FFmpegCommandBuilder.swift
//  MP4tools+
//
//  Pure functions that translate an `Operation` + selected tracks into an
//  ffmpeg argument vector. Keeping this free of side effects makes the
//  command logic easy to unit-test in isolation.
//

import Foundation

enum FFmpegCommandBuilder {

    /// Build args for a conversion/remux job.
    /// - Parameters:
    ///   - input: source file
    ///   - tracks: the user's (possibly edited) track selection
    ///   - preset: encoding settings
    ///   - output: destination .mp4
    ///   - externalSubtitle: optional .srt/.ass to mux or burn
    static func convert(input: MediaFile,
                        tracks: [MediaTrack],
                        preset: Preset,
                        output: URL,
                        externalSubtitle: URL? = nil) -> [String] {
        var args = ["-y", "-i", input.url.path]

        // A second input for an external subtitle file, if present.
        if let sub = externalSubtitle, preset.subtitleMode != .none {
            args += ["-i", sub.path]
        }

        let selectedVideo = tracks.filter { $0.kind == .video && $0.isSelected }
        let selectedAudio = tracks.filter { $0.kind == .audio && $0.isSelected }
        let selectedSubs  = tracks.filter { $0.kind == .subtitle && $0.isSelected }

        // ---- Subtitle burn-in uses a filter and forces video re-encode ----
        let burning = preset.subtitleMode == .burn
            && (!selectedSubs.isEmpty || externalSubtitle != nil)

        // ---- Stream mapping ----
        for t in selectedVideo { args += ["-map", "0:\(t.streamIndex)"] }
        for t in selectedAudio { args += ["-map", "0:\(t.streamIndex)"] }
        if preset.subtitleMode == .mux {
            if externalSubtitle != nil {
                args += ["-map", "1:0"]
            } else {
                for t in selectedSubs { args += ["-map", "0:\(t.streamIndex)"] }
            }
        }

        // ---- Video filters (scale to target width, optional burn-in) ----
        var videoFilters: [String] = []
        if preset.videoWidth > 0 {
            // Scale to the requested width; "-2" derives an even height that
            // preserves the source aspect ratio.
            videoFilters.append("scale=\(preset.videoWidth):-2")
        }
        if burning {
            if externalSubtitle != nil {
                videoFilters.append("subtitles='\(escapeFilterPath(externalSubtitle!.path))'")
            } else if let first = selectedSubs.first {
                videoFilters.append("subtitles='\(escapeFilterPath(input.url.path))':si=\(first.streamIndex)")
            }
        }

        // ---- Video codec ----
        // Any filtering (scaling or burn-in) forces a re-encode even if the
        // preset asked to pass the video through untouched.
        let mustReencodeVideo = preset.videoTarget != .passthru || !videoFilters.isEmpty

        if mustReencodeVideo {
            let encoder = preset.videoTarget.encoder(hardware: preset.useHardwareAcceleration)
                ?? (preset.useHardwareAcceleration ? "h264_videotoolbox" : "libx264")
            args += ["-c:v", encoder]
            if preset.videoBitrate > 0 {
                args += ["-b:v", "\(preset.videoBitrate)k"]
            } else if preset.useHardwareAcceleration {
                args += ["-q:v", "55"]      // VideoToolbox quality (no CRF support)
            } else {
                args += ["-crf", "20"]      // libx264/libx265 quality fallback
            }
            if !videoFilters.isEmpty {
                args += ["-vf", videoFilters.joined(separator: ",")]
            }
        } else {
            args += ["-c:v", "copy"]
        }

        // ---- Audio codec / surround handling (per track) ----
        // Each selected audio stream carries its own conversion choice.
        // Output stream specifiers (`:a:0`, `:a:1`, …) follow the order the
        // audio streams were mapped above.
        for (outIndex, t) in selectedAudio.enumerated() {
            let target = t.audioConversion
            if let codec = target.ffmpegCodec {
                args += ["-c:a:\(outIndex)", codec]
                if let ch = target.channels { args += ["-ac:a:\(outIndex)", "\(ch)"] }
                if target == .ac3_51 { args += ["-b:a:\(outIndex)", "640k"] }
                if target == .aac_51 { args += ["-b:a:\(outIndex)", "384k"] }
            } else {
                args += ["-c:a:\(outIndex)", "copy"]
            }
        }

        // ---- Subtitle codec (soft mux into MP4 needs mov_text) ----
        if preset.subtitleMode == .mux {
            args += ["-c:s", "mov_text"]
        }

        // Faststart so MP4s stream/seek immediately.
        args += ["-movflags", "+faststart", output.path]
        return args
    }

    /// Split by maximum segment size (uses the segment muxer, stream copy).
    static func splitBySize(input: URL, maxBytes: Int64, outputPattern: String) -> [String] {
        ["-y", "-i", input.path,
         "-c", "copy", "-map", "0",
         "-f", "segment",
         "-fs", "\(maxBytes)",            // size limit per output file
         "-reset_timestamps", "1",
         outputPattern]
    }

    /// Trim a single segment by start/end time (lossless stream copy).
    static func splitByTime(input: URL, start: Double, end: Double, output: URL) -> [String] {
        ["-y",
         "-ss", String(format: "%.3f", start),
         "-to", String(format: "%.3f", end),
         "-i", input.path,
         "-c", "copy", "-map", "0",
         output.path]
    }

    /// Join multiple files via the concat demuxer. `listFile` is a temp file
    /// containing `file '<path>'` lines; caller is responsible for writing it.
    static func join(listFile: URL, output: URL) -> [String] {
        ["-y", "-f", "concat", "-safe", "0",
         "-i", listFile.path,
         "-c", "copy", output.path]
    }

    /// Extract chosen tracks into individual elementary files.
    static func extract(input: URL, track: MediaTrack, output: URL) -> [String] {
        ["-y", "-i", input.path,
         "-map", "0:\(track.streamIndex)",
         "-c", "copy", output.path]
    }

    /// Adjust the pixel/sample aspect ratio without re-encoding pixels.
    static func adjustPAR(input: URL, numerator: Int, denominator: Int, output: URL) -> [String] {
        ["-y", "-i", input.path,
         "-c", "copy",
         "-bsf:v", "h264_metadata=sample_aspect_ratio=\(numerator)/\(denominator)",
         output.path]
    }

    /// Escape characters that are special inside an ffmpeg filtergraph path.
    private static func escapeFilterPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
