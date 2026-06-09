# Release Checklist — MP4tools+

Work top to bottom for each public release. Detailed steps are in `DISTRIBUTION.md`.

## Versioning
- [ ] Bump **Version** (`CFBundleShortVersionString`, e.g. 1.0 → 1.1).
- [ ] Bump **Build** (`CFBundleVersion`) — must increase on every notarized upload.
- [ ] Update a `CHANGELOG` / GitHub Release notes.

## Target build settings (MP4toolsPlus target)
- [ ] `MACOSX_DEPLOYMENT_TARGET` = your minimum (e.g. 14.0).
- [ ] `ENABLE_HARDENED_RUNTIME = YES`.
- [ ] Signing Certificate = **Developer ID Application**; Team set.
- [ ] App Sandbox **OFF** for direct distribution (the app spawns ffmpeg).
- [ ] `INFOPLIST_KEY_LSApplicationCategoryType` = `public.app-category.video`.
- [ ] `PRODUCT_BUNDLE_IDENTIFIER` is your final reverse-DNS id and won't change.
- [ ] App icon present in `Assets.xcassets/AppIcon` (done).

## Entitlements (release)
- [ ] If **bundling ffmpeg**: add
      `com.apple.security.cs.disable-library-validation = true`
      so the hardened runtime can launch your signed helper binaries.
- [ ] Remove any iOS-only / CloudKit / push entitlements left from the template.

## ffmpeg
- [ ] Decide: **bundle** (self-contained) or **require Homebrew**.
- [ ] If bundling: add universal static `ffmpeg` + `ffprobe` to **Resources**
      (Copy Bundle Resources), confirm executable bit, and that they're signed
      with hardened runtime + secure timestamp.
- [ ] Record the ffmpeg **version** and **license** (GPL vs LGPL) in
      `THIRD-PARTY-LICENSES.md`.
- [ ] Confirm license strategy (see THIRD-PARTY-LICENSES.md):
      GPL build → MP4tools+ must be GPL + source offer; LGPL build → may stay
      proprietary; Homebrew → no distribution obligation.

## Legal / attribution
- [ ] `THIRD-PARTY-LICENSES.md` shipped (and inside the DMG).
- [ ] In-app FFmpeg attribution visible (Settings ▸ General ▸ About — done).
- [ ] (Optional) Add a `Credits.rtf` to Resources so it appears in the macOS
      **About MP4tools+** panel automatically.

## Build & notarize
- [ ] `scripts/build_and_notarize.sh` runs clean (archive → export → notarize → staple).
- [ ] `scripts/make_dmg.sh 1.x` produces a stapled DMG + SHA-256.

## Verify like a user
- [ ] `spctl -a -vvv -t install <dmg>` → "accepted, source=Notarized Developer ID".
- [ ] Download the DMG via a browser (gets quarantine flag), install, launch —
      opens with **no** Gatekeeper warning.
- [ ] Smoke test core flows: drag-drop, convert (HW + software), split, join,
      extract, aspect ratio; confirm outputs play in QuickTime/Preview.

## Publish
- [ ] Upload DMG to GitHub Release / website with checksum + notes.
- [ ] Tag the git commit (e.g. `git tag v1.0 && git push --tags`).
