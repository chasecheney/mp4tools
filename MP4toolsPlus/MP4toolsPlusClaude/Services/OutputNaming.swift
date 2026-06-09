//
//  OutputNaming.swift
//  MP4tools+
//
//  Generates non-colliding output URLs next to the source file (or in the
//  user's configured default folder).
//

import Foundation

enum OutputNaming {
    /// Suggest an output URL like `Movie-converted.mp4`, avoiding overwrites
    /// by appending sequential numbering (`-2`, `-3`, …) when needed.
    static func suggest(for source: URL, suffix: String, ext: String) -> URL {
        let folder: URL
        let configured = UserDefaults.standard.string(forKey: "mp4tools.outputFolder")
        if let configured, !configured.isEmpty {
            folder = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            folder = source.deletingLastPathComponent()
        }

        let base = source.deletingPathExtension().lastPathComponent + suffix
        let desired = folder.appendingPathComponent(base).appendingPathExtension(ext)
        return uniqueURL(desired)
    }

    /// Return `desired` if no file exists there; otherwise append `-2`, `-3`, …
    /// before the extension until an unused path is found.
    ///
    /// Resolving this at the moment of writing (rather than only at enqueue)
    /// guarantees that sequentially-run jobs targeting the same name don't
    /// overwrite each other, since each prior job's file already exists by
    /// the time the next one is named.
    static func uniqueURL(_ desired: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: desired.path) else { return desired }

        let folder = desired.deletingLastPathComponent()
        let stem = desired.deletingPathExtension().lastPathComponent
        let ext = desired.pathExtension

        var counter = 2
        while true {
            let candidate = folder.appendingPathComponent("\(stem)-\(counter)")
                .appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    /// Unique base for the segment muxer, which writes `<stem>_000.<ext>`,
    /// `<stem>_001.<ext>`, … Bumps the stem until the first segment is free.
    static func uniqueSegmentBase(_ desired: URL) -> URL {
        let fm = FileManager.default
        let folder = desired.deletingLastPathComponent()
        let stem = desired.deletingPathExtension().lastPathComponent
        let ext = desired.pathExtension

        func firstSegmentExists(for stem: String) -> Bool {
            let first = folder.appendingPathComponent("\(stem)_000")
                .appendingPathExtension(ext)
            return fm.fileExists(atPath: first.path)
        }

        guard firstSegmentExists(for: stem) else { return desired }
        var counter = 2
        while firstSegmentExists(for: "\(stem)-\(counter)") { counter += 1 }
        return folder.appendingPathComponent("\(stem)-\(counter)")
            .appendingPathExtension(ext)
    }
}
