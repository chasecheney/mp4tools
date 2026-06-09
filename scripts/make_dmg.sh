#!/usr/bin/env bash
#
# make_dmg.sh — package the notarized MP4tools+.app into a drag-to-Applications
# DMG, then staple the notarization ticket to the DMG itself.
#
# Run AFTER build_and_notarize.sh.
#
# Usage:
#   scripts/make_dmg.sh [version]
#   scripts/make_dmg.sh 1.0
#
set -euo pipefail

VERSION="${1:-1.0}"
APP_NAME="MP4tools+"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/export/$APP_NAME.app"
STAGE="$BUILD_DIR/dmg-stage"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

cd "$(dirname "$0")/.."   # repo root

if [[ ! -d "$APP_PATH" ]]; then
  echo "❌ $APP_PATH not found. Run scripts/build_and_notarize.sh first." >&2
  exit 1
fi

echo "▶︎ Staging DMG contents…"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"          # drag-to-install target
# Include the license notices in the DMG.
cp THIRD-PARTY-LICENSES.md "$STAGE/" 2>/dev/null || true

echo "▶︎ Building DMG…"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "▶︎ Stapling notarization ticket to the DMG…"
xcrun stapler staple "$DMG_PATH" || \
  echo "  ⚠️  Stapling the DMG failed (the .app inside is still stapled; this is non-fatal)."

echo "▶︎ Checksum:"
shasum -a 256 "$DMG_PATH"

echo "✅ Done: $DMG_PATH"
echo "   Test it: download via a browser, open, drag to Applications, launch."
