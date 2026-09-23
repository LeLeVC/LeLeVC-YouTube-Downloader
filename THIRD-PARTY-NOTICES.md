# External tools and licenses

The release ZIP contains only first-party source scripts and documentation. It does not contain yt-dlp, FFmpeg, FFprobe, Deno, REAPER, their libraries or downloaded media. The installer obtains tools separately on the user's computer. The LeLeVC license does not apply to those tools.

| Tool | Source used by installer | License notes |
| --- | --- | --- |
| yt-dlp.exe | [Official GitHub releases](https://github.com/yt-dlp/yt-dlp/releases) | The yt-dlp source uses the Unlicense, but bundled Windows executables include third-party code and are GPLv3+. Consult [upstream licensing](https://github.com/yt-dlp/yt-dlp#licensing) and its third-party notices. |
| FFmpeg / FFprobe | [Gyan release essentials build](https://www.gyan.dev/ffmpeg/builds/), linked from [FFmpeg downloads](https://ffmpeg.org/download.html) | License depends on the build and included components. The selected essentials distribution is identified by the installer as GPLv3. Check the downloaded archive's actual license and build configuration; see [FFmpeg legal information](https://ffmpeg.org/legal.html). |
| Deno | [Official GitHub releases](https://github.com/denoland/deno/releases) | Deno's own code uses the [MIT license](https://github.com/denoland/deno/blob/main/LICENSE.md); dependencies retain their applicable licenses. |

The installer validates upstream SHA-256 checksums and stores retrieved notices under `tools/licenses`. Checksums obtained from the same source as a binary check integrity but are not independent authentication. This release fetches some license texts from upstream default branches rather than a tag matching the binary. Therefore the saved notice collection should not be treated as a complete redistribution compliance package for arbitrary future tool versions.

Do not upload a locally populated `tools` folder as part of this source-only release. If you later redistribute tool binaries, review the exact versions, license texts, copyright notices and corresponding-source obligations first. LeLeVC's no-sale clause must not be applied to GPL/MIT/Unlicense-covered third-party code.

The script invokes external executables; it does not include their source code. The runtime tools may include further components with their own notices. REAPER is a separate product supplied by Cockos. YouTube content is subject to the rights of its owners and applicable service terms.

Sources reviewed on 2026-09-23. This file documents the packaging approach and does not certify legal compliance of later modified bundles.
