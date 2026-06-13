# Full Video Player (VLCKit) — Setup

This branch (`feature/full-video-player`) adds a libVLC-backed player that plays
**MP4, MKV, AVI, WEBM** and most other formats with seeking — far beyond what
AVFoundation opens natively.

The player code is in `Views/DetailView.swift`, guarded by
`#if canImport(VLCKit)`. Until you add the VLCKit package the app still builds
and falls back to the AVKit player; once VLCKit is present, the full player
activates automatically.

## 1. Add the VLCKit package

VideoLAN's own repo (`code.videolan.org/videolan/VLCKit.git`) is **not** a Swift
Package (native SPM support is still an open issue), so adding that URL fails
with *"contains invalid JSON."* Use a community SPM **wrapper** instead — its
module is named **`VLCKitSPM`** (which is what the code's `#if canImport(...)`
checks for).

**Swift Package Manager (recommended):**

1. Xcode ▸ **File ▸ Add Package Dependencies…**
2. Enter one of these wrapper URLs:
   - `https://github.com/tylerjonesio/vlckit-spm` — wraps **VLCKit 3.x** (stable;
     dependency rule *Up to Next Major* from `3.5.1`). Recommended for shipping.
   - `https://github.com/virtualox/vlckit-spm` — wraps **VLCKit 4.0.0-alpha**
     (newer, adds Picture-in-Picture, but alpha).
3. Add the **VLCKitSPM** product to the **MP4toolsPlus** target.

Alternatively use CocoaPods (`pod 'VLCKit'`) or drag the prebuilt
**VLCKit.xcframework** in and set it to *Embed & Sign* — but then the module is
`VLCKit`, so change `VLCKitSPM` → `VLCKit` in the two `#if canImport(...)` lines
and the `import` in `DetailView.swift`.

> The Swift types (`VLCMediaPlayer`, `VLCMedia`, `VLCTime`) are the same
> regardless of wrapper — only the module name differs.

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
