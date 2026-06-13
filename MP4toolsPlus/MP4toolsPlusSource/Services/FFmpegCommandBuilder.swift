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

        let sourceVideoCodec = input.tracks(of: .video).first?.codec.lowercased() ?? ""

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
            // QuickTime / Preview only play HEVC in MP4 when tagged hvc1
            // (ffmpeg defaults to hev1, which macOS refuses).
            if encoder.contains("hevc") || encoder.contains("265") {
                args += ["-tag:v", "hvc1"]
            }
            if !videoFilters.isEmpty {
                args += ["-vf", videoFilters.joined(separator: ",")]
            }
        } else {
            args += ["-c:v", "copy"]
            if isHEVC(sourceVideoCodec) {
                args += ["-tag:v", "hvc1"]
            }
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
            } else if isMP4CompatibleAudio(t.codec) {
                args += ["-c:a:\(outIndex)", "copy"]
            } else {
                // Copy was requested, but this codec (e.g. Vorbis/FLAC/Opus)
                // isn't valid in MP4 and would produce an unplayable file —
                // fall back to AAC so the track plays.
                args += ["-c:a:\(outIndex)", "aac", "-b:a:\(outIndex)", "256k"]
            }
            // Per-track name. In MP4 the track name lives in `handler_name`
            // (the mov muxer drops a plain `title` tag), so write both: title
            // for tools/containers that read it, handler_name for MP4 players.
            let title = t.customTitle.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                args += ["-metadata:s:a:\(outIndex)", "handler_name=\(title)",
                         "-metadata:s:a:\(outIndex)", "title=\(title)"]
            }
        }

        // ---- Subtitle codec (soft mux into MP4 needs mov_text) ----
        if preset.subtitleMode == .mux {
            args += ["-c:s", "mov_text"]
            // Name each muxed internal subtitle track (handler_name persists in MP4).
            if externalSubtitle == nil {
                for (outIndex, t) in selectedSubs.enumerated() {
                    let title = t.customTitle.trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty {
                        args += ["-metadata:s:s:\(outIndex)", "handler_name=\(title)",
                                 "-metadata:s:s:\(outIndex)", "title=\(title)"]
                    }
                }
            }
        }

        // Faststart so MP4s stream/seek immediately.
        args += ["-movflags", "+faststart", output.path]
        return args
    }

    /// Split by maximum segment size (uses the segment muxer, stream copy).
    static func splitBySize(input: URL, maxBytes: Int64, outputPattern: String,
                            hevc: Bool = false) -> [String] {
        ["-y", "-i", input.path,
         "-c", "copy", "-map", "0"]
        + hevcTag(hevc)
        + ["-f", "segment",
           "-fs", "\(maxBytes)",          // size limit per output file
           "-reset_timestamps", "1",
           outputPattern]
    }

    /// Trim a single segment by start/end time (lossless stream copy).
    static func splitByTime(input: URL, start: Double, end: Double, output: URL,
                            hevc: Bool = false) -> [String] {
        ["-y",
         "-ss", String(format: "%.3f", start),
         "-to", String(format: "%.3f", end),
         "-i", input.path,
         "-c", "copy", "-map", "0"]
        + hevcTag(hevc)
        + [output.path]
    }

    /// Join multiple files via the concat demuxer. `listFile` is a temp file
    /// containing `file '<path>'` lines; caller is responsible for writing it.
    static func join(listFile: URL, output: URL, hevc: Bool = false) -> [String] {
        ["-y", "-f", "concat", "-safe", "0",
         "-i", listFile.path,
         "-c", "copy"]
        + hevcTag(hevc)
        + [output.path]
    }

    /// Extract chosen tracks into individual elementary files.
    static func extract(input: URL, track: MediaTrack, output: URL) -> [String] {
        ["-y", "-i", input.path,
         "-map", "0:\(track.streamIndex)",
         "-c", "copy", output.path]
    }

    /// Adjust the display aspect ratio without re-encoding pixels.
    ///
    /// We set the container-level aspect ratio (`-aspect`) rather than rewriting
    /// the bitstream SAR with a per-codec metadata filter. The MP4 muxer derives
    /// its `pasp`/track aspect from the demuxer's stream metadata and overrides
    /// any bitstream-filter SAR change, so `h264_metadata`/`hevc_metadata` have
    /// no visible effect here. `-aspect` is codec-agnostic, works with stream
    /// copy, and is honored by players (verified: 16:9 → 4:3).
    static func adjustPAR(input: URL, numerator: Int, denominator: Int,
                          output: URL, hevc: Bool = false) -> [String] {
        ["-y", "-i", input.path,
         "-c", "copy",
         "-aspect", "\(numerator):\(denominator)"]
        + hevcTag(hevc)
        + [output.path]
    }

    // MARK: - Helpers

    /// `-tag:v hvc1` so QuickTime/Preview accept copied HEVC (ffmpeg would
    /// otherwise keep the `hev1` tag macOS refuses). Empty for non-HEVC.
    private static func hevcTag(_ hevc: Bool) -> [String] {
        hevc ? ["-tag:v", "hvc1"] : []
    }

    /// True if `codec` is HEVC / H.265.
    static func isHEVC(_ codec: String) -> Bool {
        let c = codec.lowercased()
        return c.contains("hevc") || c.contains("265")
    }

    /// Audio codecs that are valid (and QuickTime-playable) inside MP4.
    /// Anything else must be transcoded rather than copied.
    static func isMP4CompatibleAudio(_ codec: String) -> Bool {
        let c = codec.lowercased()
        return ["aac", "ac3", "eac3", "mp3", "alac"].contains { c.contains($0) }
    }

    /// Escape characters that are special inside an ffmpeg filtergraph path.
    private static func escapeFilterPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
