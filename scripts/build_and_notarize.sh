#!/usr/bin/env bash
#
# build_and_notarize.sh — archive, sign (Developer ID), notarize, and staple
# MP4tools+ for direct distribution.
#
# Prereqs (one-time):
#   - Apple Developer Program membership + "Developer ID Application" cert
#   - A stored notary profile:
#       xcrun notarytool store-credentials "MP4TOOLS_NOTARY" \
#         --apple-id you@example.com --team-id YOURTEAMID --password <app-specific-pw>
#
# Usage:
#   scripts/build_and_notarize.sh
#
set -euo pipefail

# ---- Config -----------------------------------------------------------------
PROJECT="MP4toolsPlus/MP4toolsPlus.xcodeproj"
SCHEME="MP4toolsPlus"
APP_NAME="MP4tools+"                 # product name as it appears in build output
NOTARY_PROFILE="MP4TOOLS_NOTARY"
EXPORT_OPTS="scripts/ExportOptions.plist"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/MP4toolsPlus.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/MP4toolsPlus.zip"
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/.."   # repo root
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▶︎ Archiving…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" archive

echo "▶︎ Exporting Developer ID app…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT_DIR"

# If you bundle ffmpeg/ffprobe, make sure they are signed with hardened runtime.
for bin in ffmpeg ffprobe; do
  RES="$APP_PATH/Contents/Resources/$bin"
  if [[ -f "$RES" ]]; then
    echo "▶︎ Verifying signature on bundled $bin…"
    codesign -dv --verbose=4 "$RES" 2>&1 | grep -q "runtime" \
      || echo "  ⚠️  $bin is not hardened-runtime signed — notarization may fail."
  fi
done

echo "▶︎ Zipping for notarization…"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "▶︎ Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶︎ Stapling ticket to the app…"
xcrun stapler staple "$APP_PATH"

echo "▶︎ Verifying Gatekeeper acceptance…"
spctl -a -vvv -t exec "$APP_PATH" || true
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "✅ Done. Notarized app at: $APP_PATH"
echo "   Next: scripts/make_dmg.sh to package a .dmg."
