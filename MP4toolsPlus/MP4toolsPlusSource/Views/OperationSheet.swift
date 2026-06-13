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
    @State private var startText = "00:00:00"
    @State private var endText = "00:01:00"
    @State private var parNum = 1
    @State private var parDen = 1
    @State private var joinURLs: [URL] = []

    /// Parsed start/end times in seconds, or nil when the text is invalid.
    private var startSeconds: Double? { Self.parseTimecode(startText) }
    private var endSeconds: Double? { Self.parseTimecode(endText) }

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
                    .disabled(!canStart)
            }
        }
        .padding(24)
        .frame(width: 720, height: 480)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter times as HH:MM:SS (MM:SS and plain seconds also accepted).")
                .font(.caption).foregroundStyle(.secondary)

            timeRow(label: "Start", text: $startText, seconds: startSeconds)
            timeRow(label: "End",   text: $endText,   seconds: endSeconds)

            if let s = startSeconds, let e = endSeconds, e > s {
                Text("Clip duration: \(Self.formatTimecode(e - s))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("End time must be after start time.")
                    .font(.caption).foregroundStyle(.red)
            }

            if let d = liveFile.durationSeconds {
                Text("Source length: \(Self.formatTimecode(d))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// One labelled HH:MM:SS field with a live "= N s" readout.
    private func timeRow(label: String, text: Binding<String>, seconds: Double?) -> some View {
        HStack {
            Text(label).frame(width: 44, alignment: .leading)
            TextField("00:00:00", text: text)
                .frame(width: 120)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            if let s = seconds {
                Text("= \(Int(s)) s").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("invalid").font(.caption).foregroundStyle(.red)
            }
            Spacer()
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
                Text("Display aspect ratio")
                TextField("", value: $parNum, format: .number)
                    .frame(width: 50).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text(":")
                TextField("", value: $parDen, format: .number)
                    .frame(width: 50).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Sets how the video is displayed, without re-encoding. Common values — 16:9, 4:3, 21:9, 1:1.")
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
            // Guard handled by the disabled Start button, but stay safe.
            guard let s = startSeconds, let e = endSeconds, e > s else { return }
            enqueue(.splitByTime(start: s, end: e), suffix: "-clip", ext: "mp4")
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

    // MARK: - Timecode helpers

    /// Parse "HH:MM:SS", "MM:SS", or plain seconds into a number of seconds.
    /// Returns nil if any component is non-numeric or there are too many.
    static func parseTimecode(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 3 else { return nil }
        let values = parts.map { Double($0) }
        guard !values.contains(where: { $0 == nil }) else { return nil }
        let nums = values.compactMap { $0 }
        guard nums.allSatisfy({ $0 >= 0 }) else { return nil }
        switch nums.count {
        case 1: return nums[0]                                   // SS
        case 2: return nums[0] * 60 + nums[1]                    // MM:SS
        default: return nums[0] * 3600 + nums[1] * 60 + nums[2]  // HH:MM:SS
        }
    }

    /// Format a number of seconds as zero-padded HH:MM:SS.
    static func formatTimecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d",
                      total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Whether the current inputs are valid enough to start the operation.
    private var canStart: Bool {
        switch op {
        case .splitTime:
            guard let s = startSeconds, let e = endSeconds else { return false }
            return e > s
        case .join:
            return !joinURLs.isEmpty
        default:
            return true
        }
    }
}
