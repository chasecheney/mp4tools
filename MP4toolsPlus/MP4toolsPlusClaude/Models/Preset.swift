//
//  Preset.swift
//  MP4tools+
//
//  Encoding presets. A preset bundles the decisions a user would otherwise
//  make by hand: whether to copy or re-encode, target codecs, audio
//  downmix/upmix behaviour, and default track-selection rules.
//

import Foundation

/// How the video track should be encoded.
enum VideoTarget: String, Codable, CaseIterable, Identifiable {
    case passthru    // -c:v copy (no re-encode)
    case h264        // H.264 / AVC
    case h265        // H.265 / HEVC
    var id: String { rawValue }

    var label: String {
        switch self {
        case .passthru: return "Passthru (no re-encode)"
        case .h264:     return "H.264"
        case .h265:     return "H.265 (HEVC)"
        }
    }

    /// The ffmpeg encoder name. `hardware` selects Apple VideoToolbox
    /// encoders (GPU/ASIC accelerated) instead of the software libx encoders.
    /// Returns nil for passthru.
    func encoder(hardware: Bool) -> String? {
        switch self {
        case .passthru: return nil
        case .h264:     return hardware ? "h264_videotoolbox" : "libx264"
        case .h265:     return hardware ? "hevc_videotoolbox" : "libx265"
        }
    }
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

    // Video
    var videoTarget: VideoTarget
    /// Use Apple VideoToolbox hardware-accelerated encoders when re-encoding.
    var useHardwareAcceleration: Bool
    /// Target video bitrate in kbps. 0 = let the encoder choose (quality-based).
    var videoBitrate: Int
    /// Output width in pixels. Height is derived to preserve aspect ratio.
    /// 0 = keep the source resolution.
    var videoWidth: Int

    // Audio — applied per source track by channel count.
    /// Conversion for stereo / mono (≤ 2 channel) source tracks.
    var audioTargetStereo: AudioTarget
    /// Conversion for surround (> 2 channel) source tracks.
    var audioTargetSurround: AudioTarget

    // Subtitles
    var subtitleMode: SubtitleMode

    /// Preferred language codes for auto-selection (e.g. ["eng"]).
    var preferredLanguages: [String]
    /// Whether this preset can run fully automated (no track UI).
    var isOneStep: Bool

    init(id: UUID = UUID(),
         name: String,
         videoTarget: VideoTarget = .passthru,
         useHardwareAcceleration: Bool = false,
         videoBitrate: Int = 0,
         videoWidth: Int = 0,
         audioTargetStereo: AudioTarget = .copy,
         audioTargetSurround: AudioTarget = .copy,
         subtitleMode: SubtitleMode = .none,
         preferredLanguages: [String] = ["eng"],
         isOneStep: Bool = false) {
        self.id = id
        self.name = name
        self.videoTarget = videoTarget
        self.useHardwareAcceleration = useHardwareAcceleration
        self.videoBitrate = videoBitrate
        self.videoWidth = videoWidth
        self.audioTargetStereo = audioTargetStereo
        self.audioTargetSurround = audioTargetSurround
        self.subtitleMode = subtitleMode
        self.preferredLanguages = preferredLanguages
        self.isOneStep = isOneStep
    }

    /// The conversion to apply to a source audio track with `channels`.
    func audioTarget(forChannels channels: Int?) -> AudioTarget {
        (channels ?? 2) > 2 ? audioTargetSurround : audioTargetStereo
    }

    /// Filename-safe form of the preset name, appended to outputs:
    /// "Apple TV 4K" → "apple-tv-4k".
    var fileSuffix: String {
        let lowered = name.lowercased()
        let dashed = lowered.replacingOccurrences(of: " ", with: "-")
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyz0123456789-_")
        let cleaned = String(dashed.unicodeScalars.filter { allowed.contains($0) })
        // Collapse repeated dashes and trim.
        let collapsed = cleaned.split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "preset" : collapsed
    }

    /// Factory defaults shipped with the app for common hardware.
    static let builtIns: [Preset] = [
        Preset(name: "Remux to MP4",
               videoTarget: .passthru,
               audioTargetStereo: .copy, audioTargetSurround: .copy,
               subtitleMode: .mux, isOneStep: true),
        Preset(name: "Apple TV 4K",
               videoTarget: .passthru,
               audioTargetStereo: .aac_stereo, audioTargetSurround: .ac3_51,
               subtitleMode: .mux, isOneStep: true),
        Preset(name: "iPhone",
               videoTarget: .h264, useHardwareAcceleration: true,
               videoBitrate: 4000, videoWidth: 1280,
               audioTargetStereo: .aac_stereo, audioTargetSurround: .aac_stereo,
               subtitleMode: .burn, isOneStep: true),
        Preset(name: "H.265 1080p",
               videoTarget: .h265, useHardwareAcceleration: true,
               videoBitrate: 6000, videoWidth: 1920,
               audioTargetStereo: .aac_stereo, audioTargetSurround: .aac_51,
               subtitleMode: .mux, isOneStep: true)
    ]
}
