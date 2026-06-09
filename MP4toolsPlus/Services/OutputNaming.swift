//
//  OutputNaming.swift
//  MP4tools+
//
//  Generates non-colliding output URLs next to the source file (or in the
//  user's configured default folder).
//

import Foundation

enum OutputNaming {
    /// Suggest an output URL like `Movie-converted.mp4`, avoiding overwrites.
    static func suggest(for source: URL, suffix: String, ext: String) -> URL {
        let folder: URL
        let configured = UserDefaults.standard.string(forKey: "mp4tools.outputFolder")
        if let configured, !configured.isEmpty {
            folder = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            folder = source.deletingLastPathComponent()
        }

        let base = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
