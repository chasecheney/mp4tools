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
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
