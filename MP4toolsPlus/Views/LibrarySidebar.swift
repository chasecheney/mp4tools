//
//  LibrarySidebar.swift
//  MP4tools+
//
//  Native macOS sidebar listing imported files with codec/duration summary.
//

import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryViewModel

    var body: some View {
        List(selection: $library.selectedFileID) {
            Section("Library") {
                ForEach(library.files) { file in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(subtitle(for: file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "film")
                    }
                    .tag(file.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            library.remove(file)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if library.files.isEmpty {
                Text("No files yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func subtitle(for file: MediaFile) -> String {
        var parts: [String] = []
        if let v = file.tracks(of: .video).first,
           let w = v.width, let h = v.height {
            parts.append("\(w)×\(h)")
        }
        if let d = file.durationSeconds {
            parts.append(Self.formatDuration(d))
        }
        if let s = file.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
