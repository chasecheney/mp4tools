//
//  OperationSheet.swift
//  MP4tools+
//
//  A modal for the secondary operations: split, join, extract, adjust PAR.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OperationSheet: View {
    let file: MediaFile
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var jobQueue: JobQueueViewModel
    @Environment(\.dismiss) private var dismiss

    enum Op: String, CaseIterable, Identifiable {
        case splitSize = "Split by size"
        case splitTime = "Split by time"
        case join = "Join files"
        case extractTracks = "Extract tracks"
        case par = "Adjust aspect ratio"
        var id: String { rawValue }
    }

    @State private var op: Op = .splitSize
    @State private var maxMB: Double = 700
    @State private var startTime: Double = 0
    @State private var endTime: Double = 60
    @State private var parNum = 1
    @State private var parDen = 1
    @State private var joinURLs: [URL] = []

    private var liveFile: MediaFile {
        library.files.first { $0.id == file.id } ?? file
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(op.rawValue).font(.title2.weight(.semibold))

            Picker("Operation", selection: $op) {
                ForEach(Op.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Divider()

            Group {
                switch op {
                case .splitSize: splitSizeControls
                case .splitTime: splitTimeControls
                case .join:      joinControls
                case .extractTracks: extractControls
                case .par:       parControls
                }
            }
            .frame(minHeight: 120, alignment: .top)

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Start") { start() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }

    // MARK: - Controls

    private var splitSizeControls: some View {
        VStack(alignment: .leading) {
            Text("Maximum size per segment: \(Int(maxMB)) MB")
            Slider(value: $maxMB, in: 50...4000, step: 50)
            Text("Splits without re-encoding. Output: name_000.mp4, name_001.mp4…")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var splitTimeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Start (s)"); TextField("", value: $startTime, format: .number)
                    .frame(width: 80)
            }
            HStack {
                Text("End (s)"); TextField("", value: $endTime, format: .number)
                    .frame(width: 80)
            }
            if let d = liveFile.durationSeconds {
                Text("Clip length: \(LibrarySidebar.formatDuration(d))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var joinControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These files will be appended after \(file.displayName):")
                .font(.callout)
            ForEach(joinURLs, id: \.self) { Text("• \($0.lastPathComponent)").font(.caption) }
            Button("Add Files to Join…") { addJoinFiles() }
            Text("All inputs must share the same codecs for lossless joining.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var extractControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Each selected track is written as a separate file.")
                .font(.callout)
            ForEach(liveFile.tracks.filter { $0.isSelected }) { t in
                Label(t.summary, systemImage: t.kind.symbolName).font(.caption)
            }
        }
    }

    private var parControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pixel aspect ratio")
                TextField("", value: $parNum, format: .number).frame(width: 50)
                Text(":")
                TextField("", value: $parDen, format: .number).frame(width: 50)
            }
            Text("Common values — 1:1 (square), 16:11, 40:33.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Start

    private func start() {
        let base = liveFile
        switch op {
        case .splitSize:
            let bytes = Int64(maxMB * 1_000_000)
            enqueue(.splitBySize(maxBytes: bytes), suffix: "-part", ext: "mp4")
        case .splitTime:
            enqueue(.splitByTime(start: startTime, end: endTime), suffix: "-clip", ext: "mp4")
        case .join:
            enqueue(.join(additional: joinURLs), suffix: "-joined", ext: "mp4")
        case .extractTracks:
            let ids = base.tracks.filter { $0.isSelected }.map { $0.id }
            enqueue(.extractTracks(trackIDs: ids), suffix: "-extracted", ext: "mp4")
        case .par:
            enqueue(.adjustPAR(numerator: parNum, denominator: parDen),
                    suffix: "-par", ext: "mp4")
        }
        dismiss()
    }

    private func enqueue(_ operation: Operation, suffix: String, ext: String) {
        let output = OutputNaming.suggest(for: liveFile.url, suffix: suffix, ext: ext)
        jobQueue.enqueue(source: liveFile, operation: operation,
                         selectedTracks: liveFile.tracks, output: output)
    }

    private func addJoinFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = LibraryViewModel.acceptedTypes
        if panel.runModal() == .OK { joinURLs.append(contentsOf: panel.urls) }
    }
}
