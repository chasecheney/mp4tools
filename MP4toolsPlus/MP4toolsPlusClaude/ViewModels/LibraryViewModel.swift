//
//  LibraryViewModel.swift
//  MP4tools+
//
//  Manages the set of imported media files: drag-and-drop / open-panel
//  intake, async probing, selection, and per-track edits.
//

import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var files: [MediaFile] = []
    @Published var selectedFileID: MediaFile.ID?
    @Published var inspectionError: String?
    @Published var isImporting = false

    private let inspector = MediaInspector()

    /// File types the app accepts via drag-drop / open panel.
    static let acceptedTypes: [UTType] = [
        .mpeg4Movie, .quickTimeMovie, .movie, .video, .avi,
        UTType(filenameExtension: "mkv") ?? .movie,
        UTType(filenameExtension: "webm") ?? .movie,
        UTType(filenameExtension: "ogm") ?? .movie
    ]

    var selectedFile: MediaFile? {
        files.first { $0.id == selectedFileID }
    }

    // MARK: - Intake

    /// Add one or more URLs, probing each with ffprobe.
    func importFiles(_ urls: [URL]) {
        Task {
            isImporting = true
            defer { isImporting = false }
            for url in urls {
                // Skip duplicates already in the library.
                guard !files.contains(where: { $0.url == url }) else { continue }
                do {
                    let media = try await inspector.inspect(url: url)
                    files.append(media)
                    if selectedFileID == nil { selectedFileID = media.id }
                } catch {
                    inspectionError = error.localizedDescription
                }
            }
        }
    }

    /// Present a native open panel (also wired to the ⌘O menu command).
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.acceptedTypes
        if panel.runModal() == .OK {
            importFiles(panel.urls)
        }
    }

    func remove(_ file: MediaFile) {
        files.removeAll { $0.id == file.id }
        if selectedFileID == file.id { selectedFileID = files.first?.id }
    }

    // MARK: - Track editing

    /// Toggle a track's selection within a given file.
    func setTrack(_ trackID: MediaTrack.ID, selected: Bool, in fileID: MediaFile.ID) {
        guard let fIdx = files.firstIndex(where: { $0.id == fileID }),
              let tIdx = files[fIdx].tracks.firstIndex(where: { $0.id == trackID })
        else { return }
        files[fIdx].tracks[tIdx].isSelected = selected
    }

    /// Set the per-track audio conversion target for one audio track.
    func setAudioConversion(_ target: AudioTarget,
                            for trackID: MediaTrack.ID,
                            in fileID: MediaFile.ID) {
        guard let fIdx = files.firstIndex(where: { $0.id == fileID }),
              let tIdx = files[fIdx].tracks.firstIndex(where: { $0.id == trackID })
        else { return }
        files[fIdx].tracks[tIdx].audioConversion = target
    }

    /// Apply a preset's preferred-language rule to auto-select audio/subtitle
    /// tracks for the currently selected file.
    func applyAutoSelection(using preset: Preset, to fileID: MediaFile.ID) {
        guard let fIdx = files.firstIndex(where: { $0.id == fileID }) else { return }
        let prefs = Set(preset.preferredLanguages)
        for i in files[fIdx].tracks.indices {
            switch files[fIdx].tracks[i].kind {
            case .video:
                files[fIdx].tracks[i].isSelected = true
            case .audio:
                let lang = files[fIdx].tracks[i].language ?? ""
                files[fIdx].tracks[i].isSelected = prefs.isEmpty || prefs.contains(lang)
                // Seed the per-track conversion from the preset's stereo or
                // surround rule, chosen by the source track's channel count.
                let channels = files[fIdx].tracks[i].channels
                files[fIdx].tracks[i].audioConversion =
                    preset.audioTarget(forChannels: channels)
            case .subtitle:
                let lang = files[fIdx].tracks[i].language ?? ""
                files[fIdx].tracks[i].isSelected =
                    preset.subtitleMode != .none && prefs.contains(lang)
            default:
                files[fIdx].tracks[i].isSelected = false
            }
        }
    }
}
