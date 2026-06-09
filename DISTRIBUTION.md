# Distributing MP4tools+

This guide covers releasing MP4tools+ to the public as a **signed, notarized direct download (.dmg)** — the path that suits an app which shells out to `ffmpeg`. The Mac App Store and "require Homebrew" alternatives are summarized at the end.

> What this requires from you: a Mac, Xcode, and a paid **Apple Developer Program** membership ($99/yr) with a **Developer ID Application** certificate. Notarization and signing cannot be done without these.

---

## 0. One-time setup

1. **Enroll** in the Apple Developer Program → https://developer.apple.com/programs/
2. In Xcode → **Settings ▸ Accounts**, add your Apple ID, then **Manage Certificates ▸ +
   ▸ Developer ID Application**. This is the certificate Gatekeeper checks for downloaded apps (not "Apple Development", which is for local testing only).
3. Create an **app-specific password** for notarization:
   - https://account.apple.com → Sign-In & Security ▸ App-Specific Passwords ▸ generate one (label it e.g. "notarytool").
4. Find your **Team ID**: https://developer.apple.com/account → Membership details.
5. Store credentials in the notary keychain profile once (used by `notarytool`):

   ```sh
   xcrun notarytool store-credentials "MP4TOOLS_NOTARY" \
     --apple-id "you@example.com" \
     --team-id "YOURTEAMID" \
     --password "abcd-efgh-ijkl-mnop"   # the app-specific password
   ```

---

## 1. Release configuration (in Xcode)

Set these on the **MP4toolsPlus** target before building. See `RELEASE_CHECKLIST.md` for the full list; the essentials:

- **General ▸ Identity**: set **Version** (e.g. `1.0`) and **Build** (e.g. `1`). Increment Build on every upload.
- **Signing & Capabilities**:
  - Team: your team. Signing Certificate: **Developer ID Application**.
  - **Hardened Runtime: ON** (required for notarization).
  - App Sandbox: **OFF** for direct distribution (the app spawns `ffmpeg`; sandbox blocks that). If you keep sandbox on you must ship a privileged helper — see App Store notes.
- **Build Settings**:
  - `ENABLE_HARDENED_RUNTIME = YES`
  - `CODE_SIGN_IDENTITY = Developer ID Application`
  - `MACOSX_DEPLOYMENT_TARGET = 14.0` (or your minimum)
- **Info**: set `LSApplicationCategoryType` (e.g. `public.app-category.video`).

### Entitlements for a bundled ffmpeg under Hardened Runtime

If you bundle `ffmpeg`/`ffprobe` inside the app (recommended for public users), the hardened runtime needs:

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

This lets the app launch helper executables that are signed by you but aren't part of the main binary. Sign the bundled binaries too (step 2).

---

## 2. Bundle and sign ffmpeg (if bundling)

Public users won't have Homebrew, so bundle static `ffmpeg` and `ffprobe`:

1. Download static macOS builds (universal arm64+x86_64 preferred) — e.g. from https://evermeet.cx/ffmpeg/ or https://www.osxexperts.net/. **Confirm the build's license** (most are GPL — see `THIRD-PARTY-LICENSES.md`).
2. Drag `ffmpeg` and `ffprobe` into the Xcode project's **Resources** group; ensure they're in **Copy Bundle Resources** and marked executable.
3. They must be signed with hardened runtime. Xcode signs bundle resources during the build, but verify after archiving:

   ```sh
   codesign -dv --verbose=4 "MP4tools+.app/Contents/Resources/ffmpeg"
   ```

   If needed, sign manually before packaging:

   ```sh
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: Your Name (TEAMID)" \
     "MP4tools+.app/Contents/Resources/ffmpeg" \
     "MP4tools+.app/Contents/Resources/ffprobe"
   ```

`BinaryLocator` already prefers a bundled copy over a Homebrew one, so no code change is needed.

---

## 3. Archive, export, notarize, staple

The scripted version is `scripts/build_and_notarize.sh`. Manually:

```sh
# Archive
xcodebuild -project MP4toolsPlus/MP4toolsPlus.xcodeproj \
  -scheme MP4toolsPlus -configuration Release \
  -archivePath build/MP4toolsPlus.xcarchive archive

# Export a Developer ID app (uses ExportOptions.plist)
xcodebuild -exportArchive \
  -archivePath build/MP4toolsPlus.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export

# Zip for notarization
ditto -c -k --keepParent "build/export/MP4tools+.app" "build/MP4toolsPlus.zip"

# Submit & wait
xcrun notarytool submit "build/MP4toolsPlus.zip" \
  --keychain-profile "MP4TOOLS_NOTARY" --wait

# Staple the ticket onto the .app
xcrun stapler staple "build/export/MP4tools+.app"
```

If notarization fails, get the log:

```sh
xcrun notarytool log <submission-id> --keychain-profile "MP4TOOLS_NOTARY"
```

Most failures are unsigned/legacy-signed nested binaries (the bundled ffmpeg) — re-sign them with `--options runtime --timestamp`.

---

## 4. Package the DMG

`scripts/make_dmg.sh` builds a drag-to-Applications DMG. Then **staple the DMG too**:

```sh
xcrun stapler staple "build/MP4tools+-1.0.dmg"
```

---

## 5. Verify like a real user

Before publishing, confirm Gatekeeper acceptance on a clean machine (or after removing the quarantine-free copy):

```sh
spctl -a -vvv -t install "build/MP4tools+-1.0.dmg"      # should say "accepted / Notarized Developer ID"
codesign --verify --deep --strict --verbose=2 "MP4tools+.app"
```

Then actually download the DMG via a browser (so it gets the quarantine flag), open it, drag to Applications, and launch. It should open with no warning.

---

## 6. Publish

- Host the `.dmg` on your site or a **GitHub Release**.
- Provide a SHA-256 checksum: `shasum -a 256 MP4tools+-1.0.dmg`.
- Consider a simple appcast (e.g. **Sparkle**) for auto-updates later.

---

## Alternative: Mac App Store

Viable but materially harder because **App Sandbox is mandatory** and a sandboxed app cannot spawn an arbitrary `ffmpeg` process. Options:

- Re-implement the encode/remux work against **AVFoundation / VideoToolbox** APIs instead of ffmpeg (large rewrite, loses MKV/format breadth).
- Ship ffmpeg as a **sandbox-compatible XPC/privileged helper** — complex and subject to review scrutiny.
- License review will also flag GPL ffmpeg (App Store terms conflict with GPL). You'd need an **LGPL** build of ffmpeg configured without GPL components.

For these reasons most ffmpeg-based Mac apps ship **outside** the App Store.

## Alternative: require Homebrew ffmpeg

Smallest app, no bundling/licensing burden: ship the app and require `brew install ffmpeg`. `BinaryLocator` already finds `/opt/homebrew/bin` and `/usr/local/bin`. Downsides: friction for non-technical users, and it still won't work under App Sandbox. Good for a developer-audience release; weak for general public.
