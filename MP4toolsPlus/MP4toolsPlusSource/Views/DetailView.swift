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
import Combine
import UniformTypeIdentifiers

struct DetailView: View {
    let file: MediaFile

    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var presetStore: PresetStore
    @EnvironmentObject private var jobQueue: JobQueueViewModel

    @State private var selectedPresetID: Preset.ID?
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

    // MARK: - External subtitles

    private var subtitleRow: some View {
        HStack {
            Image(systemName: "captions.bubble")
            Button("Add Subtitle File(s)…") { chooseSubtitles() }
                .help("Add .srt/.ass files. They appear under Subtitles, where you can toggle and name each one.")
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
            externalSubtitles: currentFile.externalSubtitles
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

    private func chooseSubtitles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "ass") ?? .plainText,
            UTType(filenameExtension: "ssa") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText
        ]
        if panel.runModal() == .OK {
            library.addExternalSubtitles(panel.urls, to: file.id)
        }
    }
}

/// In-app video preview.
///
/// When the VLCKit package is present, this uses a full libVLC-backed player
/// that plays MP4, MKV, AVI, WEBM, etc. with seeking. Without VLCKit it falls
/// back to AVKit's `AVPlayerView` (MP4/MOV/M4V only). The `#if canImport`
/// guard keeps the project compiling before the package is added.
struct VideoPreview: View {
    let url: URL

    var body: some View {
        #if canImport(VLCKitSPM)
        FullVideoPlayer(url: url)
        #else
        AVPlayerPreview(url: url)
        #endif
    }
}

/// AVKit fallback player (native macOS `AVPlayerView`).
///
/// Wraps AppKit's `AVPlayerView` rather than SwiftUI's `VideoPlayer`, which
/// crashed in optimized/release builds inside `_AVKit_SwiftUI` while
/// instantiating its generic view metadata (`getSuperclassMetadata` →
/// fatalError on file drop).
struct AVPlayerPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url
        if currentURL != url {
            nsView.player = AVPlayer(url: url)
        }
    }
}

#if canImport(VLCKitSPM)
import VLCKitSPM

/// Full video player backed by libVLC — plays MP4, MKV, AVI, WEBM and more,
/// with a play/pause control and a seek scrubber.
struct FullVideoPlayer: View {
    let url: URL
    @StateObject private var controller = VLCPlayerController()

    var body: some View {
        ZStack(alignment: .bottom) {
            VLCDrawable(controller: controller)
            transportBar
        }
        .background(Color.black)
        .onAppear { controller.open(url) }
        .onChange(of: url) { _, newURL in controller.open(newURL) }
        .onDisappear { controller.stop() }
    }

    private var transportBar: some View {
        HStack(spacing: 10) {
            Button(action: controller.togglePlay) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            Text(controller.timeText)
                .font(.caption.monospacedDigit())

            Slider(value: Binding(get: { controller.position },
                                  set: { controller.seek(to: $0) }),
                   in: 0...1)

            Text(controller.durationText)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55))
        .foregroundStyle(.white)
    }
}

/// Hosts libVLC's video output in an `NSView` drawable.
private struct VLCDrawable: NSViewRepresentable {
    let controller: VLCPlayerController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        controller.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Wraps `VLCMediaPlayer` and publishes playback state for the SwiftUI UI.
/// Playback position is polled on a timer to stay robust across VLCKit
/// versions (whose delegate signatures have changed between releases).
@MainActor
final class VLCPlayerController: ObservableObject {
    private let player = VLCMediaPlayer()
    private var timer: Timer?

    @Published var isPlaying = false
    @Published var position: Double = 0          // 0...1
    @Published var timeText = "0:00"
    @Published var durationText = "0:00"

    init() {
        // scheduledTimer fires on the current (main) run loop; assume main-actor
        // isolation so we can call the @MainActor `tick()` synchronously without
        // spawning a Task that would capture `self` in concurrent code.
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func attach(to view: NSView) {
        player.drawable = view
    }

    func open(_ url: URL) {
        player.media = VLCMedia(url: url)
        player.play()
    }

    func togglePlay() {
        player.isPlaying ? player.pause() : player.play()
    }

    func seek(to fraction: Double) {
        player.position = Float(fraction)
    }

    func stop() {
        player.stop()
    }

    private func tick() {
        isPlaying = player.isPlaying
        position = Double(player.position)
        timeText = player.time.stringValue
        if let length = player.media?.length.stringValue {
            durationText = length
        }
    }

    deinit {
        timer?.invalidate()
        player.stop()
    }
}
#endif

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
