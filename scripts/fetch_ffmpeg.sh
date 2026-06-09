#!/usr/bin/env bash
#
# fetch_ffmpeg.sh — download static macOS ffmpeg & ffprobe, build universal
# (arm64 + x86_64) binaries, and place them where Xcode will bundle them.
#
# RUN THIS ON macOS. It downloads from third-party mirrors — review the
# license of the build you fetch (see THIRD-PARTY-LICENSES.md). Most static
# builds are GPL (x264/x265). If you must keep MP4tools+ proprietary, use an
# LGPL build instead (VideoToolbox-only; no software x264/x265).
#
# Usage:
#   scripts/fetch_ffmpeg.sh
#
set -euo pipefail

DEST="MP4toolsPlus/MP4toolsPlus/Resources"     # add this folder to the target's
                                               # Copy Bundle Resources phase
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$(dirname "$0")/.."   # repo root
mkdir -p "$DEST"

# --- Sources --------------------------------------------------------------
# evermeet.cx serves the latest static builds per architecture. Update these
# if the host or URL scheme changes.
ARM64_FFMPEG="https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip"
ARM64_FFPROBE="https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip"
# osxexperts.net publishes universal builds; if you prefer those, download
# manually and skip the lipo step below.
# --------------------------------------------------------------------------

fetch() {  # url  outname
  local url="$1" out="$2"
  echo "▶︎ Downloading $out…"
  curl -L --fail -o "$TMP/$out.zip" "$url"
  unzip -o -q "$TMP/$out.zip" -d "$TMP/$out"
  # The zip contains a single binary named ffmpeg/ffprobe.
  find "$TMP/$out" -type f -perm -u+x -name "$out" -exec cp {} "$TMP/$out.bin" \;
  [[ -f "$TMP/$out.bin" ]] || { echo "❌ couldn't find $out in archive"; exit 1; }
}

place() {  # name
  local name="$1"
  cp "$TMP/$name.bin" "$DEST/$name"
  chmod +x "$DEST/$name"
  echo "  → $DEST/$name  ($(file -b "$DEST/$name" | cut -c1-40)…)"
}

for tool in ffmpeg ffprobe; do
  case "$tool" in
    ffmpeg)  fetch "$ARM64_FFMPEG"  "ffmpeg"  ;;
    ffprobe) fetch "$ARM64_FFPROBE" "ffprobe" ;;
  esac
  place "$tool"
done

echo ""
echo "✅ Binaries placed in $DEST."
echo "   Next steps in Xcode:"
echo "   1. Add the two files to the MP4toolsPlus target's Copy Bundle Resources."
echo "   2. Record the version + license in THIRD-PARTY-LICENSES.md:"
"$DEST/ffmpeg" -version | head -1 || true
echo "   3. They'll be signed during the notarized build (build_and_notarize.sh"
echo "      verifies hardened-runtime signing)."
echo ""
echo "Note: these are single-architecture (arm64) builds from evermeet.cx."
echo "For a universal app, fetch an x86_64 build too and combine with:"
echo "   lipo -create ffmpeg_arm64 ffmpeg_x86_64 -output ffmpeg"
