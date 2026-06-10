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
import AVFoundation
import UniformTypeIdentifiers

struct DetailView: View {
    let file: MediaFile

    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var presetStore: PresetStore
    @EnvironmentObject private var jobQueue: JobQueueViewModel

    @State private var selectedPresetID: Preset.ID?
    @State private var externalSubtitle: URL?
    @State private var showOperationSheet = false
    @State private var editingPreset: Preset?

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
        .sheet(item: $editingPreset) { preset in
            PresetEditorSheet(presetID: preset.id)
                .environmentObject(presetStore)
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
            .frame(maxWidth: 280)

            // Create / edit / delete presets.
            Menu {
                Button("New Preset…") { createPreset() }
                if let preset = selectedPreset {
                    Button("Edit “\(preset.name)”…") { editingPreset = preset }
                    Divider()
                    Button("Delete “\(preset.name)”", role: .destructive) {
                        deletePreset(preset)
                    }
                    .disabled(presetStore.presets.count <= 1)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Create, edit, or delete presets")

            Button("Auto-select tracks") {
                if let preset = selectedPreset {
                    library.applyAutoSelection(using: preset, to: file.id)
                }
            }
            .help("Select tracks and seed audio conversion from this preset")

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
        // Append the preset name (lowercased, dashed) to the output file.
        let output = OutputNaming.suggest(
            for: file.url, suffix: "-" + preset.fileSuffix, ext: "mp4")
        jobQueue.enqueue(
            source: currentFile,
            operation: .convert(preset: preset),
            selectedTracks: currentFile.tracks,
            output: output,
            externalSubtitle: externalSubtitle
        )
    }

    // MARK: - Preset management

    private func createPreset() {
        let new = Preset(name: "New Preset")
        presetStore.add(new)
        selectedPresetID = new.id
        editingPreset = new
    }

    private func deletePreset(_ preset: Preset) {
        presetStore.delete(preset)
        selectedPresetID = presetStore.presets.first?.id
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

/// AVKit preview so users can verify their selections.
///
/// We wrap AVKit's AppKit `AVPlayerView` via `NSViewRepresentable` instead of
/// SwiftUI's `VideoPlayer`. SwiftUI's `VideoPlayer` crashed in optimized/release
/// builds inside `_AVKit_SwiftUI` while instantiating its generic view metadata
/// (`getSuperclassMetadata` → fatalError on file drop). `AVPlayerView` avoids
/// that code path and is the native macOS player view.
struct VideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Replace the player only when the source URL actually changes.
        let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url
        if currentURL != url {
            nsView.player = AVPlayer(url: url)
        }
    }
}

/// Modal wrapper that hosts the shared `PresetForm` with a Done button,
/// used by the preset dropdown's New/Edit actions.
struct PresetEditorSheet: View {
    let presetID: Preset.ID
    @EnvironmentObject private var store: PresetStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Preset").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            if let preset = store.presets.first(where: { $0.id == presetID }) {
                PresetForm(preset: preset)
                    .id(preset.id)
            } else {
                Text("This preset no longer exists.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 480, height: 560)
    }
}
