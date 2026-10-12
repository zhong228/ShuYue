# ShuYue (书悦)

<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon_1024_white_no_alpha.png" width="112" alt="ShuYue">
</p>

<p align="center">
  A serene open-source reader for iOS — EPUB3, comics, audiobooks, RSS, and open catalogs, rendered natively with CoreText.
</p>

<p align="center">
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-18.0%2B-000000?logo=apple&logoColor=white" alt="iOS 18.0+">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-MPL--2.0-blue" alt="MPL 2.0 License">
</p>

ShuYue (书悦) is an open-source iOS reading app for a high-quality local and open reading experience. One app for EPUB3, comics, audiobooks, RSS, and open catalogs — rendered natively with CoreText, no WebView.

## Features

| | |
|:--|:--|
| **Formats** | EPUB3 · TXT · CBZ Comics · Audiobook · PDF *(WIP)* |
| **Content** | Local Library · WebDAV · OPDS · RSS · Content Sources |
| **Reading** | Vertical Writing · Themes · Annotation · Bookmarks |
| **More** | Reading Statistics · iCloud Sync |

## Why CoreText, not WebView

Most readers wrap content in a WebView. ShuYue renders every page with CoreText, which gives precise pagination, true CJK vertical writing, frame-accurate text-to-speech sync, and native text selection — at native performance.

## Architecture

```
UI (SwiftUI)
  ↓
Reader (CoreText)
  ↓
Parser (EPUB / TXT / CBZ / RSS / Audio)
  ↓
Storage (Local-first)
  ↓
Sync (WebDAV / iCloud / OPDS)
```

## Download

**Latest release:** [ShuYue v1.1.0](https://github.com/zhong228/ShuYue/releases/download/v1.1.0/ShuYue-v1.1.0.ipa) (unsigned IPA)

## Build

**Requirements:** Xcode 16+ · iOS 18.0+ · Swift 6.0

```bash
git clone https://github.com/zhong228/ShuYue.git
cd ShuYue
open *.xcodeproj
```

Then select a simulator (or your device) and run. Self-built versions need their own signing configuration and bundle identifier. Publicly redistributed forks must use distinct app names, icons, and branding and must not imply official endorsement.

## Documentation

### User guides

- **Book sources (Legado-format):** [Guide index](docs/book-source/README.md) · [常见症状对照表](docs/book-source/troubleshooting.zh-Hans.md) — import, five-stage validation, rule debugger, syntax cheat sheet, differences from Legado, and symptom→fix troubleshooting.
- **Battery SVG templates:** [English](docs/reader-overlay/BatterySVG.en.md) · [简体中文](docs/reader-overlay/BatterySVG.zh-Hans.md) · [繁體中文](docs/reader-overlay/BatterySVG.zh-Hant.md) — template format, dynamic markers, supported SVG subset, and import troubleshooting.

### Developer reference

- [CoreText documentation](docs/coretext/README.md) — reader architecture, rendering pipeline, interaction, and vertical writing.
- [EPUB compatibility checklist](docs/epub-compatibility-checklist.md) — implementation and regression checklist.
- [Project architecture](Technotes/Architecture.md) — modules, data flow, and technical boundaries.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and the PR process.

## License

Source code is licensed under the [Mozilla Public License 2.0](LICENSE). The ShuYue name, app icon, logo, screenshots, and other brand assets are not licensed under the MPL; see [TRADEMARKS.md](TRADEMARKS.md). Versions released before a license change remain available under the license that applied when they were published; see [LICENSING.md](LICENSING.md).