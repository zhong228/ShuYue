# 书悦 (ShuYue)

<div align="center">

  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon_1024_white_no_alpha.png" width="120" alt="书悦">

  <h3>A serene open-source reader for iOS</h3>

  <p>
    EPUB3 · TXT · CBZ · Audiobooks · RSS · OPDS · WebDAV · iCloud · Legado Sources
  </p>

  <p>
    <a href="README.zh-Hans.md">简体中文</a>
    ·
    <a href="README.zh-Hant.md">繁體中文</a>
    ·
    <a href="README.md">English</a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/iOS-18.0%2B-000000?logo=apple&logoColor=white" alt="iOS 18.0+">
    <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
    <img src="https://img.shields.io/badge/license-MPL--2.0-blue" alt="MPL 2.0 License">
  </p>

</div>

---

## Overview

书悦 (ShuYue) is an open-source iOS reading app designed for a high-quality local and open reading experience. One app for EPUB3, comics, audiobooks, RSS, and open catalogs — rendered natively with CoreText, no WebView.

## Features

### Supported Formats
- **EPUB3** — Full support with custom CSS and font injection
- **TXT** — Smart chapter detection and encoding auto-detection
- **CBZ** — Comics and manga with smooth scrolling
- **Audiobooks** — Native audio player with playback controls
- **PDF** *(Work in Progress)*

### Content Sources
- **Local Library** — Import and organize your own books
- **WebDAV** — Sync with your personal cloud storage
- **OPDS** — Browse public catalogs
- **RSS** — Subscribe to feeds and read articles
- **Content Sources (Legado)** — Import and use Legado-format book sources

### Reading Experience
- **CoreText Rendering** — Native performance, precise pagination
- **Vertical Writing** — True CJK vertical text layout
- **Themes** — Customizable reading themes
- **Annotations & Bookmarks** — Highlight, note, and bookmark
- **Text-to-Speech Sync** — Frame-accurate audio synchronization

### More
- **Reading Statistics** — Track your reading habits
- **iCloud Sync** — Seamless sync across devices
- **Widget** — Home screen reading progress widget
- **Pro Features** — Advanced customization options

## Why CoreText?

Most readers wrap content in a WebView. 书悦 renders every page with CoreText, which gives precise pagination, true CJK vertical writing, frame-accurate text-to-speech sync, and native text selection — at native performance.

## Architecture

```
┌─────────────────────────┐
│      UI (SwiftUI)       │
├─────────────────────────┤
│   Reader (CoreText)     │
├─────────────────────────┤
│ Parser (EPUB/TXT/CBZ)   │
├─────────────────────────┤
│   Storage (Local-first) │
├─────────────────────────┤
│  Sync (WebDAV/iCloud)   │
└─────────────────────────┘
```

## Download

<div align="center">

  **[Download ShuYue v1.3.4](https://github.com/zhong228/ShuYue/releases/download/v1.3.4/ShuYue-v1.3.4.ipa)** (unsigned IPA)

</div>

## Build

**Requirements:** Xcode 16+ · iOS 18.0+ · Swift 6.0

```bash
git clone https://github.com/zhong228/ShuYue.git
cd ShuYue
open *.xcodeproj
```

Then select a simulator (or your device) and run. Self-built versions need their own signing configuration and bundle identifier. Publicly redistributed forks must use distinct app names, icons, and branding and must not imply official endorsement.

## Documentation

### User Guides
- **[Book Sources Guide](docs/book-source/README.md)** — Import, five-stage validation, rule debugger, syntax cheat sheet, differences from Legado, and troubleshooting
- **[Battery SVG Templates](docs/reader-overlay/BatterySVG.en.md)** — Template format, dynamic markers, supported SVG subset

### Developer Reference
- **[CoreText Documentation](docs/coretext/README.md)** — Reader architecture, rendering pipeline, interaction, and vertical writing
- **[EPUB Compatibility Checklist](docs/epub-compatibility-checklist.md)** — Implementation and regression checklist
- **[Project Architecture](Technotes/Architecture.md)** — Modules, data flow, and technical boundaries

## Acknowledgements

书悦 is built upon the foundation of [Yuedu-reader](https://github.com/CHANG-JUI-LIN/Yuedu-reader) by CHANG-JUI-LIN, licensed under MPL-2.0.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and the PR process.

## License

Source code is licensed under the [Mozilla Public License 2.0](LICENSE). The 书悦 name, app icon, logo, screenshots, and other brand assets are not licensed under the MPL; see [TRADEMARKS.md](TRADEMARKS.md).

Versions released before a license change remain available under the license that applied when they were published; see [LICENSING.md](LICENSING.md).
