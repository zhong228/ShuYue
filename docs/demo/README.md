# Demo Media Guide

README media should show the product quickly and avoid turning the repository homepage into a maintenance note.

The README should not reference media files that do not exist yet. Product screenshots currently live in this directory so the README can use one compact media root.

## Current README Media

```text
docs/demo/
  cjk-vertical-toc.gif
  book-source-reading.gif
  library.png
  reader-menu.png
  highlights-annotations.png
  tts.png
  manga-reader.png
  rss-reader.png
  opds-webdav-import.png
  dark-mode.png
```

Use one primary GIF above the fold: CJK vertical reading plus right-opening table of contents. Keep it short: 5-10 seconds, 300-360 px wide in README, ideally under 10 MB.

The secondary GIF should show one online reading workflow. The current README uses `book-source-reading.gif`.

## Planned Product Media

### GIFs

```text
docs/demo/rss-reading.gif
docs/demo/web-normalization.gif
```

- `rss-reading.gif`: RSS feed list -> open article -> native reader view.
- `web-normalization.gif`: open or enter a web page -> extraction / normalization -> clean reader view.

Keep workflow GIFs short, about 4-6 seconds each. README should not show more than 2-3 GIFs total.

## Screenshot Roles

- `library.png`: bookshelf / library home, used as the product first impression.
- `reader-menu.png`: reader toolbar or settings menu, showing reading controls.
- `highlights-annotations.png`: highlight, bookmark, or annotation UI.
- `tts.png`: TTS playback state.
- `manga-reader.png`: local CBZ/ZIP or compatible source-based manga reading.
- `rss-reader.png`: RSS list or article reading view.
- `opds-webdav-import.png`: add-book, OPDS, or WebDAV import entry point.
- `dark-mode.png`: dark-mode reading screen.

Prefer iPhone portrait screenshots. Display screenshots at 240-280 px wide in README.

## Recording

Record the booted iPhone simulator:

```bash
xcrun simctl io booted recordVideo demo.mov
```

Stop with `Ctrl+C`.

## Convert to GIF

```bash
ffmpeg -i demo.mov -vf "fps=12,scale=640:-1:flags=lanczos" -loop 0 docs/demo/cjk-vertical-toc.gif
```

Smaller GIF:

```bash
ffmpeg -i demo.mov -vf "fps=10,scale=480:-1:flags=lanczos" -loop 0 docs/demo/cjk-vertical-toc.gif
```

For workflow GIFs, prefer the smaller version:

```bash
ffmpeg -i demo.mov -vf "fps=10,scale=480:-1:flags=lanczos" -loop 0 docs/demo/rss-reading.gif
```

## MP4 Fallback

If a GIF is too large, put an MP4 in `docs/demo/` or a release asset and link it through a screenshot:

When adding an MP4 fallback to README, link a stable screenshot to the generated MP4 path and keep the screenshot `alt` text specific to the workflow.

```bash
ffmpeg -i demo.mov -vf "scale=720:-2" -c:v libx264 -crf 28 -preset slow -pix_fmt yuv420p docs/demo/cjk-vertical-toc.mp4
```
