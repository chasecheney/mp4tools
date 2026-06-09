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
        // 1. Bundled binary (preferred — self-contained app).
        if let bundled = Bundle.main.url(forResource: tool, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        // 2. Known on-disk install locations.
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw BinaryLocatorError.notFound(tool)
    }

    static var ffmpeg: URL { get throws { try url(for: "ffmpeg") } }
    static var ffprobe: URL { get throws { try url(for: "ffprobe") } }
}
