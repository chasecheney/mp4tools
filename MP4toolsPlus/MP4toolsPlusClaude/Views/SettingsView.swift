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
        .frame(width: 720, height: 560)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("mp4tools.outputFolder") private var outputFolder = ""
    @AppStorage("mp4tools.openOnComplete") private var openOnComplete = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

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

            Section("About") {
                LabeledContent("Version", value: appVersion)
                // Required attribution when distributing with FFmpeg (LGPL/GPL).
                VStack(alignment: .leading, spacing: 4) {
                    Text("This software uses libraries from the FFmpeg project under the LGPLv2.1/GPLv2.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("ffmpeg.org", destination: URL(string: "https://ffmpeg.org")!)
                        .font(.caption)
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
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

            Group {
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
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
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
            if !draft.name.isEmpty {
                LabeledContent("Output suffix") {
                    Text("…-\(draft.fileSuffix).mp4")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Video") {
                Picker("Encoding", selection: $draft.videoTarget) {
                    ForEach(VideoTarget.allCases) { Text($0.label).tag($0) }
                }
                if draft.videoTarget != .passthru {
                    Toggle("Hardware accelerated encoding", isOn: $draft.useHardwareAcceleration)
                        .help("Use Apple VideoToolbox (GPU/ASIC) — much faster, slightly larger files")

                    LabeledContent("Bitrate (kbps)") {
                        TextField("", value: $draft.videoBitrate, format: .number)
                            .labelsHidden()
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Width (px)") {
                        TextField("", value: $draft.videoWidth, format: .number)
                            .labelsHidden()
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Set either to 0 to keep the source (automatic bitrate, original width). Height is derived to preserve aspect ratio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Audio") {
                Picker("Stereo / mono source", selection: $draft.audioTargetStereo) {
                    ForEach(AudioTarget.allCases) { Text($0.label).tag($0) }
                }
                Picker("Surround source", selection: $draft.audioTargetSurround) {
                    ForEach(AudioTarget.allCases) { Text($0.label).tag($0) }
                }
                Text("Each source audio track uses the rule matching its channel count.")
                    .font(.caption).foregroundStyle(.secondary)
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
