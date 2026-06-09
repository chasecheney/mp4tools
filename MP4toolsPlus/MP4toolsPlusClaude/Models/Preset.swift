//
//  Preset.swift
//  MP4tools+
//
//  Encoding presets. A preset bundles the decisions a user would otherwise
//  make by hand: whether to copy or re-encode, target codecs, audio
//  downmix/upmix behaviour, and default track-selection rules.
//

import Foundation

/// How to treat a stream: stream-copy (fast, lossless) or re-encode.
enum StreamMode: String, Codable, CaseIterable, Identifiable {
    case copy        // -c copy  (remux, no quality loss)
    case reencode    // transcode to the preset's target codec
    var id: String { rawValue }
    var label: String { self == .copy ? "Copy (no re-encode)" : "Re-encode" }
}

/// Target audio codec when re-encoding / converting surround sound.
enum AudioTarget: String, Codable, CaseIterable, Identifiable {
    case copy
    case ac3_51    // 5.1 AC-3
    case aac_51    // 5.1 AAC
    case aac_stereo
    var id: String { rawValue }

    var label: String {
        switch self {
        case .copy:       return "Copy original"
        case .ac3_51:     return "AC3 (5.1)"
        case .aac_51:     return "AAC (5.1)"
        case .aac_stereo: return "AAC (2 channel)"
        }
    }

    /// ffmpeg codec name and channel count for this target.
    var ffmpegCodec: String? {
        switch self {
        case .copy:       return nil
        case .ac3_51:     return "ac3"
        case .aac_51:     return "aac"
        case .aac_stereo: return "aac"
        }
    }
    var channels: Int? {
        switch self {
        case .copy:                  return nil
        case .ac3_51, .aac_51:       return 6
        case .aac_stereo:            return 2
        }
    }
}

/// How subtitles should be handled.
enum SubtitleMode: String, Codable, CaseIterable, Identifiable {
    case none        // drop subtitles
    case mux         // soft subtitles (mov_text in MP4)
    case burn        // hard-code the chosen subtitle into the video
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "No subtitles"
        case .mux:  return "Soft (mux)"
        case .burn: return "Burn in (hard-code)"
        }
    }
}

/// A reusable, named encoding configuration.
struct Preset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var videoMode: StreamMode
    /// Target H.264/H.265 codec when re-encoding (e.g. "libx264").
    var videoCodec: String
    /// Constant Rate Factor when re-encoding (lower = higher quality).
    var crf: Int
    var audioTarget: AudioTarget
    var subtitleMode: SubtitleMode
    /// Preferred language codes for auto-selection (e.g. ["eng"]).
    var preferredLanguages: [String]
    /// Whether this preset can run fully automated (no track UI).
    var isOneStep: Bool

    init(id: UUID = UUID(),
         name: String,
         videoMode: StreamMode = .copy,
         videoCodec: String = "libx264",
         crf: Int = 20,
         audioTarget: AudioTarget = .copy,
         subtitleMode: SubtitleMode = .none,
         preferredLanguages: [String] = ["eng"],
         isOneStep: Bool = false) {
        self.id = id
        self.name = name
        self.videoMode = videoMode
        self.videoCodec = videoCodec
        self.crf = crf
        self.audioTarget = audioTarget
        self.subtitleMode = subtitleMode
        self.preferredLanguages = preferredLanguages
        self.isOneStep = isOneStep
    }

    /// Factory defaults shipped with the app for common hardware.
    static let builtIns: [Preset] = [
        Preset(name: "Remux to MP4 (fastest, lossless)",
               videoMode: .copy, audioTarget: .copy,
               subtitleMode: .mux, isOneStep: true),
        Preset(name: "Apple TV 4K",
               videoMode: .copy, audioTarget: .ac3_51,
               subtitleMode: .mux, isOneStep: true),
        Preset(name: "iPhone (H.264, stereo)",
               videoMode: .reencode, videoCodec: "libx264", crf: 21,
               audioTarget: .aac_stereo, subtitleMode: .burn, isOneStep: true),
        Preset(name: "Surround → 5.1 AAC",
               videoMode: .copy, audioTarget: .aac_51,
               subtitleMode: .mux, isOneStep: true)
    ]
}
