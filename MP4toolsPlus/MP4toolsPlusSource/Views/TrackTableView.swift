//
//  TrackTableView.swift
//  MP4tools+
//
//  A grouped table letting the user toggle which video / audio / subtitle
//  tracks get processed.
//

import SwiftUI

struct TrackTableView: View {
    let file: MediaFile
    @EnvironmentObject private var library: LibraryViewModel

    /// Always read the live copy so toggles reflect immediately.
    private var liveFile: MediaFile {
        library.files.first { $0.id == file.id } ?? file
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracks")
                .font(.headline)

            ForEach(TrackKind.allCases) { kind in
                let tracks = liveFile.tracks(of: kind)
                if !tracks.isEmpty {
                    section(title: title(for: kind), kind: kind, tracks: tracks)
                }
            }
        }
    }

    private func title(for kind: TrackKind) -> String {
        switch kind {
        case .video:    return "Video"
        case .audio:    return "Audio"
        case .subtitle: return "Subtitles"
        case .attachment: return "Attachments"
        case .data:     return "Data"
        }
    }

    private func section(title: String, kind: TrackKind, tracks: [MediaTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(tracks) { track in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: Binding(
                        get: { track.isSelected },
                        set: { library.setTrack(track.id, selected: $0, in: file.id) }
                    )) {
                        HStack {
                            Image(systemName: kind.symbolName)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(track.summary)
                            Spacer()
                            Text("#\(track.streamIndex)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    // Per-track audio conversion choice.
                    if kind == .audio {
                        audioConversionPicker(for: track)
                            .padding(.leading, 24)
                            .disabled(!track.isSelected)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// A compact picker letting the user convert this audio track to
    /// AAC (2 channel), AAC (5.1), AC3 (5.1), or leave it as-is.
    private func audioConversionPicker(for track: MediaTrack) -> some View {
        Picker("Convert to", selection: Binding(
            get: { track.audioConversion },
            set: { library.setAudioConversion($0, for: track.id, in: file.id) }
        )) {
            ForEach(Array(AudioTarget.allCases.reversed())) { target in
                Text(target.label).tag(target)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .labelsHidden()
        .frame(maxWidth: 200, alignment: .leading)
    }
}
