# stillmd

<img src="assets/app-icon/stillmd-icon.png" alt="stillmd icon" width="160" />

A quiet, preview-only Markdown viewer for macOS.

stillmd is built for reading Markdown without turning the app itself into the main character. It opens local `.md` and `.markdown` files, follows external changes, and stays out of the way.

## Why stillmd

- Preview-only by design. stillmd is not a text editor.
- Minimal, calm UI that keeps the document in focus.
- Native macOS app built with SwiftUI and WKWebView.
- Fast enough for everyday notes, docs, and long-form Markdown reading.

## Features

- GitHub Flavored Markdown rendering
- Syntax highlighting for fenced code blocks
- Relative image and link resolution
- Auto-reload when a file changes on disk
- Scroll position preservation on reload
- One window per file with duplicate detection
- Built-in find (`⌘F`)
- Theme override: System, Light, Dark
- Adjustable reading scale

## Non-goals

- Editing Markdown files
- Adding sidebars, workspace panes, or heavy project management UI
- Replacing a full editor like VS Code, Zed, or Typora

## System Requirements

- macOS 15 or later
- Xcode 16 or later for local builds

## Install

### GitHub Releases

1. Download the latest `stillmd-<version>-macos.zip` from [Releases](https://github.com/Jtwulf/stillmd/releases).
2. Unzip the archive.
3. Move `stillmd.app` into `/Applications` or another folder you prefer.

This app is currently distributed without Developer ID signing and notarization.

If macOS blocks the first launch:

1. Control-click `stillmd.app`.
2. Choose `Open`.
3. Confirm the dialog.

Depending on your macOS settings, you may also need to allow the app from System Settings > Privacy & Security.

### Build From Source

```bash
swift build
swift test
./scripts/build-app.sh
```

To create a release-style archive locally:

```bash
./scripts/package-release.sh v0.1.0
```

## Usage

- Open a Markdown file with `File > Open…` or `⌘O`
- Drag and drop a `.md` file onto the window or Dock icon
- Set stillmd as the default app for `.md` files in Finder if you want
- Use `⌘F` to search inside the current preview
- Adjust theme and text scale in Settings

## Tech Stack

- SwiftUI
- WKWebView
- [marked](https://github.com/markedjs/marked)
- [highlight.js](https://highlightjs.org/)

## Project Docs

Public setup and usage live in this README.

Internal design and implementation docs remain in Japanese:

- [AGENTS.md](AGENTS.md)
- [DESIGN.md](DESIGN.md)
- [`docs/rules/`](docs/rules/)
- [`docs/plans/`](docs/plans/)

## Contributing

Issues and pull requests are welcome.

Before opening a PR:

- keep the app preview-only
- avoid adding noisy always-visible UI
- run `swift build` and `swift test`

Maintainers handle merges.

## Security

If you found a security issue, please read [.github/SECURITY.md](.github/SECURITY.md) before filing anything publicly.

## License

stillmd is released under the [MIT License](LICENSE).

Bundled third-party assets are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
