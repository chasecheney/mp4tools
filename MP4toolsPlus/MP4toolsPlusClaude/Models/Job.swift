//
//  Job.swift
//  MP4tools+
//
//  A unit of processing work and the operations the app can perform.
//

import Foundation
import Combine

/// The kind of operation a job performs.
enum Operation: Codable, Hashable {
    case convert(preset: Preset)
    /// Split into chunks either by max size (bytes) or by time range.
    case splitBySize(maxBytes: Int64)
    case splitByTime(start: Double, end: Double)
    case join(additional: [URL])
    case extractTracks(trackIDs: [UUID])
    case adjustPAR(numerator: Int, denominator: Int)

    var label: String {
        switch self {
        case .convert(let p):     return "Convert · \(p.name)"
        case .splitBySize:        return "Split by size"
        case .splitByTime:        return "Split by time"
        case .join:               return "Join"
        case .extractTracks:      return "Extract tracks"
        case .adjustPAR:          return "Adjust pixel aspect ratio"
        }
    }
}

enum JobStatus: Equatable {
    case queued
    case running(progress: Double)   // 0.0 ... 1.0
    case completed(outputURL: URL)
    case failed(message: String)
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }
}

/// An observable job. Reference type so SwiftUI can track live progress.
@MainActor
final class Job: Identifiable, ObservableObject {
    let id = UUID()
    let source: MediaFile
    let operation: Operation
    let outputURL: URL

    @Published var status: JobStatus = .queued

    init(source: MediaFile, operation: Operation, outputURL: URL) {
        self.source = source
        self.operation = operation
        self.outputURL = outputURL
    }
}
