# StillMD (MarkdownPreviewer)

A lightweight, preview-only Markdown viewer for macOS.

## Project Docs

- Agent entry point: `AGENTS.md`
- Design constitution: `DESIGN.md`
- Implementation rules: `docs/rules/`

Internal project rules are maintained in Japanese. The public README remains English.

## System Requirements

- macOS 15.5+
- Xcode 16+

## Build

```bash
swift build
```

Or open the project in Xcode and build with ⌘B.

## Usage

- Open `.md` files via File > Open or ⌘O
- Drag & drop `.md` files onto the window or Dock icon
- Set as default app for `.md` files in Finder (Get Info > Open With)
- Auto-reloads when the file is saved externally
- Follows system light/dark mode

## Features

- GitHub Flavored Markdown (tables, task lists, strikethrough, autolinks)
- Syntax highlighting for fenced code blocks
- Relative path resolution for images and links
- Scroll position preservation on reload
- One window per file with duplicate detection

## Tech Stack

- SwiftUI + WKWebView
- [marked.js](https://github.com/markedjs/marked) — Markdown → HTML
- [highlight.js](https://highlightjs.org/) — syntax highlighting

## License

MIT
