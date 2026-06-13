# Full Video Player (VLCKit) — Setup

This branch (`feature/full-video-player`) adds a libVLC-backed player that plays
**MP4, MKV, AVI, WEBM** and most other formats with seeking — far beyond what
AVFoundation opens natively.

The player code is in `Views/DetailView.swift`, guarded by
`#if canImport(VLCKit)`. Until you add the VLCKit package the app still builds
and falls back to the AVKit player; once VLCKit is present, the full player
activates automatically.

## 1. Add the VLCKit package

**Swift Package Manager (recommended):**

1. Xcode ▸ **File ▸ Add Package Dependencies…**
2. Enter the VLCKit Swift package URL:
   `https://code.videolan.org/videolan/VLCKit.git`
   (use the latest `4.0`-series release/branch that publishes a Swift package).
3. Add the **VLCKit** product to the **MP4toolsPlus** target.

If SPM packaging isn't available for your VLCKit version, use CocoaPods instead
(`pod 'VLCKit'`) or drag the prebuilt **VLCKit.xcframework** into the project and
add it to *Frameworks, Libraries, and Embedded Content* (set to *Embed & Sign*).

> Module name: the code uses `import VLCKit` (macOS). If your VLCKit distribution
> exposes a different module name, update the `import` and the two
> `#if canImport(...)` lines in `DetailView.swift` to match.

## 2. Build & run

Build (⌘B). Drop an MKV/AVI/WEBM file — it should now play inline with a
play/pause button and a seek scrubber.

## 3. Notes for distribution

- **App size:** VLCKit bundles libVLC and its plugins — expect **+60–150 MB**.
  This is the tradeoff for native all-format playback.
- **License:** VLCKit/libVLC is **LGPLv2.1+**. You may ship it with a
  proprietary app provided you (a) keep it as a replaceable dynamic
  framework (Embed & Sign, do not statically merge), (b) include its license
  and attribution, and (c) offer its source. Add an entry to
  `THIRD-PARTY-LICENSES.md` alongside the FFmpeg one.
- **Signing / notarization:** the embedded `VLCKit.xcframework` (and its
  dylibs/plugins) must be signed with your Developer ID and Hardened Runtime.
  Xcode's *Embed & Sign* handles this; the existing
  `com.apple.security.cs.disable-library-validation` entitlement already allows
  loading it. Re-run `build_and_notarize.sh` and confirm notarization passes
  (it will flag any unsigned nested binary).

## Architecture

- `VideoPreview` — routes to `FullVideoPlayer` (VLCKit present) or
  `AVPlayerPreview` (fallback).
- `FullVideoPlayer` — SwiftUI view: VLC video output + transport bar.
- `VLCDrawable` — `NSViewRepresentable` hosting libVLC's drawable `NSView`.
- `VLCPlayerController` — `@MainActor ObservableObject` wrapping
  `VLCMediaPlayer`; polls playback position on a timer (robust across VLCKit
  versions whose delegate signatures differ) and publishes `isPlaying`,
  `position`, `timeText`, `durationText`.
