# Claude Monitor

A lightweight macOS menu bar app that monitors Claude Code instances, MCP servers, and PostCSS workers in real time — and auto-kills runaway processes before they crash your Mac.

Built after spending an afternoon debugging a [`@tailwindcss/postcss` memory leak](https://blog.my-monkey.fr/posts/mcp-servers-crash-mac/) that spawned 2261 workers in 50 seconds.

## Features

- 🤖 Real-time count of Claude Code instances and MCP servers in the menu bar
- ⚠️ Visual warning when PostCSS workers go above threshold
- 📊 RAM usage with color-coded progress bar (green/orange/red)
- 📋 Top apps by memory consumption with mini bars
- 🔪 One-click kill for PostCSS workers or all MCP servers
- ⚙️ Auto-kill with configurable thresholds (workers count + RAM)
- 🔄 Refreshes every 5 seconds
- 💾 Minimal footprint (~10 MB RSS, native Swift)

## Install

```bash
git clone https://github.com/my-monkeys/claude-monitor
cd claude-monitor
bash install.sh
open /Applications/ClaudeMonitor.app
```

Requires macOS 14+ and Swift 5.9+.

## Build from source

```bash
swift build -c release
```

The executable lives in `.build/release/ClaudeMonitor`. To package it as a proper `.app` bundle (so it persists in the menu bar), run `bash install.sh`.

## Add to login items

System Settings → General → Login Items → add `/Applications/ClaudeMonitor.app`.

## How it works

The app runs `ps aux` every 5 seconds, classifies processes by name, and aggregates them by app. When RAM exceeds the auto-kill threshold or PostCSS worker count exceeds its threshold, it sends `SIGKILL` to those processes.

No telemetry, no network, no dependencies beyond Apple's SwiftUI/AppKit.

## License

MIT — do whatever.
