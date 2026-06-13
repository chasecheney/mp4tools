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

            if !liveFile.externalSubtitles.isEmpty {
                externalSubtitlesSection
            }
        }
    }

    /// External subtitle files attached by the user, each with an include
    /// toggle, an editable name, and a remove button.
    private var externalSubtitlesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EXTERNAL SUBTITLES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(liveFile.externalSubtitles) { sub in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { sub.isSelected },
                            set: { library.setExternalSubtitle(sub.id, selected: $0, in: file.id) }
                        )) {
                            HStack {
                                Image(systemName: "captions.bubble")
                                    .foregroundStyle(.secondary).frame(width: 20)
                                Text(sub.displayName).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Spacer()
                        Button(role: .destructive) {
                            library.removeExternalSubtitle(sub.id, in: file.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this subtitle")
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "tag").font(.caption2).foregroundStyle(.tertiary)
                        TextField("Subtitle name (e.g. English, Forced)",
                                  text: Binding(
                                    get: { sub.customTitle },
                                    set: { library.setExternalSubtitleTitle(sub.id, title: $0, in: file.id) }))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(maxWidth: 320, alignment: .leading)
                    }
                    .padding(.leading, 24)
                    .disabled(!sub.isSelected)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

                    // Editable track name (audio & subtitle), written as title
                    // metadata in the output.
                    if kind == .audio || kind == .subtitle {
                        titleField(for: track)
                            .padding(.leading, 24)
                            .disabled(!track.isSelected)
                    }

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

    /// An editable name field for an audio/subtitle track, saved as the
    /// output track's title metadata.
    private func titleField(for track: MediaTrack) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextField("Track name (e.g. English, Director Commentary)",
                      text: Binding(
                        get: { track.customTitle },
                        set: { library.setTrackTitle($0, for: track.id, in: file.id) }))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 320, alignment: .leading)
        }
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
