//
//  SettingsView.swift
//  MP4tools+
//
//  Native macOS Settings window (⌘,) with a Presets editor where users can
//  define one-step automated encoding + track-selection presets.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            PresetEditorView()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 420)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("mp4tools.outputFolder") private var outputFolder = ""
    @AppStorage("mp4tools.openOnComplete") private var openOnComplete = false

    var body: some View {
        Form {
            Toggle("Reveal output in Finder when a job completes", isOn: $openOnComplete)
            LabeledContent("Default output folder") {
                HStack {
                    Text(outputFolder.isEmpty ? "Same as source" : outputFolder)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { chooseFolder() }
                }
            }
        }
        .padding(20)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url.path
        }
    }
}

struct PresetEditorView: View {
    @EnvironmentObject private var store: PresetStore
    @State private var selection: Preset.ID?

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                ForEach(store.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .frame(minWidth: 180)

            if let id = selection,
               let preset = store.presets.first(where: { $0.id == id }) {
                PresetForm(preset: preset)
                    .id(preset.id)
            } else {
                Text("Select a preset")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let p = Preset(name: "New Preset")
                    store.add(p); selection = p.id
                } label: { Image(systemName: "plus") }

                Button {
                    if let id = selection,
                       let p = store.presets.first(where: { $0.id == id }) {
                        store.delete(p); selection = nil
                    }
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
            }
        }
    }
}

/// Editable form bound to a working copy; saves back to the store on change.
struct PresetForm: View {
    @EnvironmentObject private var store: PresetStore
    @State private var draft: Preset

    init(preset: Preset) { _draft = State(initialValue: preset) }

    var body: some View {
        Form {
            TextField("Name", text: $draft.name)

            Section("Video") {
                Picker("Mode", selection: $draft.videoMode) {
                    ForEach(StreamMode.allCases) { Text($0.label).tag($0) }
                }
                if draft.videoMode == .reencode {
                    Picker("Codec", selection: $draft.videoCodec) {
                        Text("H.264 (libx264)").tag("libx264")
                        Text("H.265 (libx265)").tag("libx265")
                    }
                    Stepper("Quality (CRF): \(draft.crf)", value: $draft.crf, in: 14...30)
                }
            }

            Section("Audio") {
                Picker("Target", selection: $draft.audioTarget) {
                    ForEach(AudioTarget.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Subtitles") {
                Picker("Mode", selection: $draft.subtitleMode) {
                    ForEach(SubtitleMode.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Automation") {
                Toggle("One-step (skip track UI)", isOn: $draft.isOneStep)
                TextField("Preferred languages (comma-separated)",
                          text: Binding(
                            get: { draft.preferredLanguages.joined(separator: ", ") },
                            set: { draft.preferredLanguages = $0
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty } }))
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft) { _, new in store.update(new) }
    }
}
