# Changelog

## 1.0 — first public version (prepared locally), 2026-09-23

- Added Back on the progress page to cancel the current job and return to link/settings without closing the window. A new download can then be started in the same window.
- Fixed installer crashes during tool downloads by avoiding recursive progress-event processing; verified a clean installation of yt-dlp, Deno, FFmpeg and FFprobe.
- Public display name changed to **LeLeVC_YouTube Downloader** and the entry file renamed to `LeLeVC_YouTube Downloader.lua`.
- Kept the existing settings, history and single-window identifiers for compatibility with the previous name.
- Kept all four runtime files together; excluded tool binaries, old launchers, personal data and development tests.
- Added English installation/use documentation, external-tool notices and the custom LeLeVC Free Use and No-Sale License.
- No new download features were added during release preparation. This is not a published release.

This public version is based on development version 0.5.9.09. The final functional change before packaging unified title/URL history selection: both advance only when automatic next-step navigation is enabled. The context menu offers Copy title and Copy URL.

## Earlier development changes

The following summary is reconstructed from development records; independent archived snapshots of every intermediate version were not available for comparison.

- **5.9.08:** FFmpeg section progress includes output size and processing speed; corrected closing/cancellation help text.
- **5.9.07:** closing or Cancel requests worker-tree termination and stops REAPER polling.
- **5.9.06:** fixed audio-only FFmpeg section progress parsing.
- **5.9.05:** added downloaded byte counts and transfer speed for normal yt-dlp progress.
- **5.9.04:** restored narrower windows (approximately 740 px minimum outer width) and adjusted the top row.
- **5.9.03:** initial text scaling and input-width adjustments.
- **5.9.01–5.9.02:** audio-only modes and history/navigation work preceded the current snapshot; exact per-version attribution is not asserted here.
