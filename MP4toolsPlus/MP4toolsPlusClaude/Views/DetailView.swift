//
//  DetailView.swift
//  MP4tools+
//
//  The working area for a selected file: video preview, track selection,
//  preset picker, and the action buttons that enqueue jobs.
//

import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

struct DetailView: View {
    let file: MediaFile

    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var presetStore: PresetStore
    @EnvironmentObject private var jobQueue: JobQueueViewModel

    @State private var selectedPresetID: Preset.ID?
    @State private var externalSubtitle: URL?
    @State private var showOperationSheet = false

    private var selectedPreset: Preset? {
        presetStore.presets.first { $0.id == selectedPresetID }
            ?? presetStore.presets.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VideoPreview(url: file.url)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                presetRow

                TrackTableView(file: file)

                subtitleRow

                actionRow
            }
            .padding(20)
        }
        .navigationTitle(file.displayName)
        .navigationSubtitle(file.formatName ?? "")
        .sheet(isPresented: $showOperationSheet) {
            OperationSheet(file: file)
                .environmentObject(jobQueue)
        }
    }

    // MARK: - Preset picker

    private var presetRow: some View {
        HStack {
            Picker("Preset", selection: Binding(
                get: { selectedPresetID ?? presetStore.presets.first?.id },
                set: { selectedPresetID = $0 })) {
                ForEach(presetStore.presets) { preset in
                    Text(preset.name).tag(Optional(preset.id))
                }
            }
            .frame(maxWidth: 320)

            Button("Auto-select tracks") {
                if let preset = selectedPreset {
                    library.applyAutoSelection(using: preset, to: file.id)
                }
            }
            .help("Choose tracks based on the preset's preferred languages")

            Spacer()
        }
    }

    // MARK: - External subtitle

    private var subtitleRow: some View {
        HStack {
            Image(systemName: "captions.bubble")
            if let sub = externalSubtitle {
                Text(sub.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Button("Remove") { externalSubtitle = nil }
            } else {
                Button("Add External Subtitle…") { chooseSubtitle() }
                    .help("Add an .srt or .ass file to mux or burn in")
            }
            Spacer()
        }
        .font(.callout)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                startConversion()
            } label: {
                Label("Convert to MP4", systemImage: "arrow.right.circle.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(selectedPreset == nil)

            Button("More Operations…") { showOperationSheet = true }
                .help("Split, join, extract tracks, or adjust aspect ratio")

            Spacer()
        }
    }

    // MARK: - Helpers

    private func startConversion() {
        guard let preset = selectedPreset else { return }
        let output = OutputNaming.suggest(for: file.url, suffix: "-converted", ext: "mp4")
        jobQueue.enqueue(
            source: currentFile,
            operation: .convert(preset: preset),
            selectedTracks: currentFile.tracks,
            output: output,
            externalSubtitle: externalSubtitle
        )
    }

    /// The freshest copy of the file (track edits live in the library VM).
    private var currentFile: MediaFile {
        library.files.first { $0.id == file.id } ?? file
    }

    private func chooseSubtitle() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "ass") ?? .plainText,
            UTType(filenameExtension: "ssa") ?? .plainText
        ]
        if panel.runModal() == .OK { externalSubtitle = panel.url }
    }
}

/// Lightweight AVKit preview so users can verify their selections.
struct VideoPreview: View {
    let url: URL
    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .background(Color.black)
    }
}
