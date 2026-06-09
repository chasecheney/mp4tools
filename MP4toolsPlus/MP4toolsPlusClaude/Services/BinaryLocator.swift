//
//  BinaryLocator.swift
//  MP4tools+
//
//  Resolves the paths to the ffmpeg and ffprobe binaries. The app prefers
//  copies bundled inside Resources (so it works on a clean machine), then
//  falls back to a Homebrew/system install discovered on disk.
//

import Foundation

enum BinaryLocatorError: LocalizedError {
    case notFound(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Could not find “\(name)”. Install it (e.g. `brew install ffmpeg`) or add it to the app bundle."
        }
    }
}

struct BinaryLocator {
    /// Common install locations to probe when no bundled copy exists.
    private static let searchPaths = [
        "/opt/homebrew/bin",   // Apple Silicon Homebrew
        "/usr/local/bin",      // Intel Homebrew
        "/usr/bin"
    ]

    static func url(for tool: String) throws -> URL {
        let fm = FileManager.default

        // 1. Bundled binary (preferred — self-contained app). Check the common
        //    locations a helper executable may live in inside the .app bundle.
        var bundledCandidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            bundledCandidates.append(res.appendingPathComponent(tool))
        }
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            bundledCandidates.append(exeDir.appendingPathComponent(tool)) // Contents/MacOS
        }
        if let helpers = Bundle.main.sharedSupportURL?
            .deletingLastPathComponent().appendingPathComponent("Helpers") {
            bundledCandidates.append(helpers.appendingPathComponent(tool)) // Contents/Helpers
        }
        if let viaResource = Bundle.main.url(forResource: tool, withExtension: nil) {
            bundledCandidates.append(viaResource)
        }
        for candidate in bundledCandidates where fm.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        // 2. Known on-disk install locations (developer / Homebrew fallback).
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(tool)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw BinaryLocatorError.notFound(tool)
    }

    static var ffmpeg: URL { get throws { try url(for: "ffmpeg") } }
    static var ffprobe: URL { get throws { try url(for: "ffprobe") } }
}
