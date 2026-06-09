//
//  DropZoneView.swift
//  MP4tools+
//
//  The empty-state hero shown when no file is selected: a large, inviting
//  drag-and-drop target.
//

import SwiftUI

struct DropZoneView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text("Drop a video here")
                .font(.title2.weight(.semibold))

            Text("MKV, MP4, WEBM, OGM, AVI and more.\nMost files convert in minutes with no quality loss.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Choose File…") { library.presentOpenPanel() }
                .controlSize(.large)
                .padding(.top, 4)

            if library.isImporting {
                ProgressView("Reading file…")
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .padding(40)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                if !urls.isEmpty { library.importFiles(urls) }
            }
            return true
        }
    }
}
