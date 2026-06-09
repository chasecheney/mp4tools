# Third-Party Licenses & Attribution

MP4tools+ uses the following third-party software. If you distribute MP4tools+
with these components **bundled**, you must comply with their licenses — this
includes shipping these notices and honoring the source-code obligations below.

---

## FFmpeg (ffmpeg, ffprobe)

MP4tools+ uses FFmpeg (https://ffmpeg.org) to inspect and process media.

FFmpeg is free software licensed under the **GNU Lesser General Public License
(LGPL) version 2.1 or later**. However, **many prebuilt static FFmpeg binaries
are compiled with GPL components enabled** (e.g. `libx264`, `libx265`,
`--enable-gpl`), which makes that particular build **GPL v2 or later**.

**You must determine which license your bundled build falls under** and comply
accordingly. Check with:

```sh
ffmpeg -version        # look for "configuration:" — '--enable-gpl' means GPL
```

### Your obligations when bundling

Regardless of LGPL or GPL, when you distribute the FFmpeg binaries you must:

1. **Include this attribution** and the full license text with your app.
   Place `COPYING.GPLv2` / `COPYING.LGPLv2.1` (from the FFmpeg source) alongside
   this file, or inside the app bundle (e.g. `Contents/Resources/licenses/`).
2. **Offer the corresponding source code** for the exact FFmpeg version you
   ship — either by including it, or with a written offer pointing to the
   download (e.g. the release tag at https://git.ffmpeg.org/ffmpeg.git or the
   tarball from https://ffmpeg.org/download.html). Record the version:

   ```sh
   ffmpeg -version | head -1   # e.g. "ffmpeg version 7.1 ..."
   ```

3. If the build is **GPL** (x264/x265 etc.), then **MP4tools+ as distributed
   must also be offered under the GPL** (the GPL is "viral" across the combined
   distribution). If you want to keep MP4tools+ under your own proprietary
   terms, ship an **LGPL-only** FFmpeg build (configure without `--enable-gpl`
   and without GPL-only libraries) and link to it dynamically, or require the
   user to supply ffmpeg themselves (Homebrew path) so you are not distributing
   it.

> Practical summary:
> - **Bundling a GPL ffmpeg** → simplest technically, but MP4tools+ must be GPL and you must provide source.
> - **Bundling an LGPL ffmpeg** → you may keep MP4tools+ proprietary, but must allow users to replace the ffmpeg library and provide ffmpeg source.
> - **Not bundling (Homebrew)** → you aren't distributing ffmpeg, so these obligations fall away (still nice to attribute).

### Attribution text (also surfaced in the app's About box)

> This software uses libraries from the FFmpeg project under the LGPLv2.1/GPLv2.
> FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.

---

## Bundled binaries record

Fill in when you cut a release:

| Component | Version | License of this build | Source URL |
| --- | --- | --- | --- |
| ffmpeg  | (e.g. 7.1) | (LGPL / GPL) | https://ffmpeg.org/download.html |
| ffprobe | (e.g. 7.1) | (LGPL / GPL) | https://ffmpeg.org/download.html |
