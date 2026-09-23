# LeLeVC_YouTube Downloader

Version **1.0** — a Windows ReaScript by **LeLeVC** for downloading a single YouTube video or audio track and importing it into REAPER.

This software is distributed under the LeLeVC Free Use and No-Sale License. See [LICENSE.md](LICENSE.md). External tools are downloaded separately and retain their own licenses.

## Requirements

- Windows x64, Windows PowerShell 5.1 with Windows Forms, and an internet connection.
- REAPER with Lua ReaScript support. Import was previously tested in REAPER 7.80; other versions have not been certified.
- A writable script folder and download destination.
- yt-dlp, FFmpeg, FFprobe and Deno. The included installer can download them on first use. No Python installation, SWS or ReaImGui is required by the script.
- A REAPER media decoder that supports the downloaded format. Decoder support varies with the REAPER installation.

This release is Windows-only. It does not provide macOS or Linux support. The automatic installer targets x64 tool builds.

## Installation

1. Extract the complete ZIP into a permanent, writable folder. Keep these four files together:
   - `LeLeVC_YouTube Downloader.lua`
   - `YouTube-link-dialog.ps1`
   - `YouTube-downloader.ps1`
   - `Install-tools.ps1`
2. In REAPER, open **Actions > Show action list > New action > Load ReaScript** and select `LeLeVC_YouTube Downloader.lua`.
3. Run the action. If required tools are missing, choose **Download required tools** in the installer. It downloads upstream binaries, checks SHA-256 values, and saves notices under `tools/licenses`.
4. Alternatively, put `yt-dlp.exe`, `ffmpeg.exe`, `ffprobe.exe` and `deno.exe` in a `tools` subfolder beside the script. Executables available through Windows PATH can also be used.

Windows may block scripts extracted from an internet download. If you trust the source, check the ZIP's **Properties > Unblock** before extracting. Managed computers may enforce PowerShell restrictions that the script cannot override.

## Use

The same window contains three pages: link and settings, format selection, and progress.

Paste a YouTube link or select a title or URL from the ten-entry history. With **Go to the next step after pasting or choosing a link** enabled, either history column advances automatically. With it disabled, click **Continue**. Right-click either column for **Copy title** or **Copy URL**. Delete removes one entry; Clear history removes all entries.

Click a format on the second page to start downloading. **Use automatic quality** skips this page and selects Best available - Auto. **Paste YouTube link from clipboard on startup** reads the clipboard only when enabled.

## Formats

| Choice | Result |
| --- | --- |
| Video | 360p through 2160p, or Best available; Auto, AV1, VP9 or H.264 where offered |
| Audio - Original | Best available audio stream, retaining its codec and container; it is not necessarily WAV or MP3 |
| Audio - WAV (24-bit) | Audio decoded to 24-bit PCM WAV |
| Audio - FLAC (24-bit) | Audio converted to 24-bit FLAC |
| Cover | Thumbnail encoded as a fixed 640 × 360, 1 fps H.264 video; audio is copied without re-encoding |

Converting YouTube audio to WAV or FLAC does not restore information already lost in the source audio. Cover resizes the thumbnail to 640 × 360, so its aspect ratio may change.

Auto lets yt-dlp select an available video codec within the selected height limit. Video mode currently requests AAC audio and merges/remuxes streams into MP4. Selecting a codec does not transcode the video to that codec. H.264 is not offered for the explicit 1440p and 2160p presets. Availability depends on the video; a lower resolution may be selected, with a warning after download. Best available is not a promise of a particular resolution.

Filenames use the YouTube title with Windows-safe substitutions and add format information such as resolution, codec and fps. Cover uses `[static]`; converted audio includes its format and sample rate. An existing matching output may be reused.

Links containing `t=` or `start=` request downloading from that time to the end. There is no start/end range selector. Section downloads use FFmpeg and can be much slower than full downloads; boundaries and timestamps are not guaranteed sample-accurate.

## Destination and import

- Saved project: the default destination is its `Downloaded` subfolder. You can change the subfolder name and optionally save a second copy elsewhere.
- Unsaved project: defaults to the Windows Downloads folder or your remembered choice. Use **Browse...** to choose another folder.
- Import position: timeline start (time zero), edit cursor captured when downloading starts, or the end of the track selected at that time. The end of that track is calculated when the file is ready.
- Mute after import: None, Item, Track, or Item and track. Track mute affects the entire destination track, including existing items.
- If the active project changes or the destination track is removed, the file is kept and the script reports that manual import is needed.

## Progress, closing and updates

The progress bar is for the current stage. Separate video and audio downloads have separate progress values. Normal yt-dlp downloads can show downloaded bytes and transfer speed. FFmpeg section downloads show output size and processing speed in multiples of real time, not network MB/s. Displayed KB/MB/GB sizes currently use powers of 1024; approximate totals are marked `~`.

**Back** on the progress page stops the current download and returns to the first page without closing the window. You can change automatic options and start another download in that same window. Returning does not automatically paste or submit the link again.

Cancel or the window close button requests cancellation, stops the worker process tree and ends REAPER polling. Completed imports are not undone. Partial downloads and temporary job folders may remain after cancellation. **Close when finished** remembers its choice and closes after a clean successful import; warnings and errors remain visible.

Use **Tool updates** on the first page to check installed tools against upstream versions and update selected tools. YouTube changes may require an updated yt-dlp. Update failures do not necessarily mean a tool is current.

## Existing users and the new name

The script was previously named Lech_Reaper YouTube Downloader. Load the new Lua file as a new REAPER action and reassign any shortcut or toolbar button as needed. The old action still points to the old file and will not rename itself.

The release deliberately retains the old REAPER ExtState section `Lech_Reaper YouTube Downloader` for history, cached titles and folder preferences, and `%LOCALAPPDATA%\Lech_Reaper YouTube Downloader` for other settings and window geometry. No migration is needed. Old and new copies share these preferences and the existing single-window lock. Close the old copy before starting the new one. The public ZIP contains no personal settings or history.

## Limitations and troubleshooting

- Single-video URLs only; playlists and live streams are not supported. No account/cookie or DRM workflow is provided.
- A visible window and an active worker are expected during a download; closing the window cancels rather than deliberately continuing in the background.
- Some error and warning messages remain in Polish in 1.0.
- High-DPI, mixed-monitor scaling and all format combinations have not been exhaustively tested.
- If an old pre-5.9.07 instance is still running, REAPER may ask to terminate it. Updating the files does not replace code already loaded by a running instance.
- If downloading fails, use Tool updates, retry, and consult the reported job log. If a file downloads but cannot be imported, check REAPER's decoder support or choose another format.

Job logs are stored in `%TEMP%\REAPER-YT-*`. They can contain local paths, source URLs and temporary media URLs. Review and redact them before sharing a bug report. Include script, Windows, REAPER and tool versions, selected options, and steps to reproduce the problem.

## License and credits

The license terms allow free use in professional and commercial productions, modification, and free redistribution with LeLeVC attribution and a change notice. Selling the script or modified versions, including within a paid bundle, requires separate permission. These restrictions do not apply to selling recordings, videos or other outputs made using the script. The full terms are in [LICENSE.md](LICENSE.md).

This is a custom source-available license, not MIT or a blanket prohibition of commercial use. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the separate external-tool licenses. This project is not affiliated with or endorsed by REAPER, Cockos, YouTube, Google or the tool authors. Download only material you are permitted to download and use; the script license does not grant rights to YouTube content.

See [CHANGELOG.md](CHANGELOG.md) for the version history.
