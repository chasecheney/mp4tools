//
//  MediaModels.swift
//  MP4tools+
//
//  Core value types describing a media file and its constituent tracks.
//  These are deliberately plain `Codable` structs so they can be cached,
//  persisted, and passed across actor boundaries safely.
//

import Foundation

/// The kind of a single stream inside a container.
enum TrackKind: String, Codable, CaseIterable, Identifiable {
    case video, audio, subtitle, attachment, data
    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .video:      return "film"
        case .audio:      return "speaker.wave.2"
        case .subtitle:   return "captions.bubble"
        case .attachment: return "paperclip"
        case .data:       return "doc"
        }
    }
}

/// A single stream (one row in the track-selection table).
struct MediaTrack: Identifiable, Codable, Hashable {
    let id: UUID
    /// The stream index as reported by ffprobe (used to build `-map` args).
    let streamIndex: Int
    let kind: TrackKind
    let codec: String
    let language: String?
    let title: String?

    // Video-specific
    let width: Int?
    let height: Int?
    let frameRate: Double?

    // Audio-specific
    let channels: Int?
    let channelLayout: String?
    let sampleRate: Int?

    /// Whether the user has selected this track for processing.
    var isSelected: Bool

    /// Per-track audio conversion choice. Only meaningful for audio tracks;
    /// `.copy` leaves the stream untouched (no re-encode).
    var audioConversion: AudioTarget

    /// Editable track name written to the output as title metadata. Seeded from
    /// the probed `title`; user-editable for audio and subtitle tracks.
    var customTitle: String

    init(id: UUID = UUID(),
         streamIndex: Int,
         kind: TrackKind,
         codec: String,
         language: String? = nil,
         title: String? = nil,
         width: Int? = nil,
         height: Int? = nil,
         frameRate: Double? = nil,
         channels: Int? = nil,
         channelLayout: String? = nil,
         sampleRate: Int? = nil,
         isSelected: Bool = true,
         audioConversion: AudioTarget = .copy,
         customTitle: String? = nil) {
        self.id = id
        self.streamIndex = streamIndex
        self.kind = kind
        self.codec = codec
        self.language = language
        self.title = title
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.isSelected = isSelected
        self.audioConversion = audioConversion
        self.customTitle = customTitle ?? title ?? ""
    }

    /// Human-friendly one-line summary shown in the UI.
    var summary: String {
        switch kind {
        case .video:
            let dims = (width != nil && height != nil) ? "\(width!)×\(height!)" : "—"
            let fps = frameRate.map { String(format: "%.3g fps", $0) } ?? ""
            return [codec.uppercased(), dims, fps].filter { !$0.isEmpty }.joined(separator: " · ")
        case .audio:
            let layout = channelLayout ?? channels.map { "\($0) ch" } ?? ""
            let lang = language.map { "[\($0)]" } ?? ""
            return [codec.uppercased(), layout, lang].filter { !$0.isEmpty }.joined(separator: " · ")
        case .subtitle:
            let lang = language.map { "[\($0)]" } ?? ""
            return [codec.uppercased(), lang, title ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        default:
            return codec.uppercased()
        }
    }
}

/// An external subtitle file (e.g. an .srt/.ass downloaded separately) the user
/// attaches to a media file. Shown alongside internal subtitle tracks.
struct ExternalSubtitle: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    /// Whether to include this subtitle in the conversion.
    var isSelected: Bool
    /// Track name written to the output (title / handler_name).
    var customTitle: String

    init(id: UUID = UUID(), url: URL, isSelected: Bool = true, customTitle: String? = nil) {
        self.id = id
        self.url = url
        self.isSelected = isSelected
        // Default the name to the file's base name (e.g. "Movie.en" → "Movie.en").
        self.customTitle = customTitle ?? url.deletingPathExtension().lastPathComponent
    }

    var displayName: String { url.lastPathComponent }
}

/// A media file dropped into the app, with its probed tracks.
struct MediaFile: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    var tracks: [MediaTrack]
    var durationSeconds: Double?
    var sizeBytes: Int64?
    /// Container format reported by ffprobe (e.g. "matroska,webm").
    var formatName: String?
    /// External subtitle files attached by the user.
    var externalSubtitles: [ExternalSubtitle]

    init(id: UUID = UUID(), url: URL, tracks: [MediaTrack] = [],
         durationSeconds: Double? = nil, sizeBytes: Int64? = nil,
         formatName: String? = nil, externalSubtitles: [ExternalSubtitle] = []) {
        self.id = id
        self.url = url
        self.tracks = tracks
        self.durationSeconds = durationSeconds
        self.sizeBytes = sizeBytes
        self.formatName = formatName
        self.externalSubtitles = externalSubtitles
    }

    var displayName: String { url.lastPathComponent }

    func tracks(of kind: TrackKind) -> [MediaTrack] {
        tracks.filter { $0.kind == kind }
    }
}
