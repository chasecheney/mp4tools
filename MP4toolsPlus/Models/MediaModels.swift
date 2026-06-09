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
         isSelected: Bool = true) {
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

/// A media file dropped into the app, with its probed tracks.
struct MediaFile: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    var tracks: [MediaTrack]
    var durationSeconds: Double?
    var sizeBytes: Int64?
    /// Container format reported by ffprobe (e.g. "matroska,webm").
    var formatName: String?

    init(id: UUID = UUID(), url: URL, tracks: [MediaTrack] = [],
         durationSeconds: Double? = nil, sizeBytes: Int64? = nil,
         formatName: String? = nil) {
        self.id = id
        self.url = url
        self.tracks = tracks
        self.durationSeconds = durationSeconds
        self.sizeBytes = sizeBytes
        self.formatName = formatName
    }

    var displayName: String { url.lastPathComponent }

    func tracks(of kind: TrackKind) -> [MediaTrack] {
        tracks.filter { $0.kind == kind }
    }
}
