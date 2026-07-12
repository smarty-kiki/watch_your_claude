# WatchYourClaude

macOS menu bar app that monitors Claude Code sessions — tracks input/output throughput, model generation speed, token usage, and displays charts.

## Tech

- **Swift** + **SwiftUI** for UI
- **TCA** (The Composable Architecture) for state management
- **File watcher** to tail Claude Code JSONL transcript files for real-time data

## Key source files

- `Sources/WatchYourClaude/` — app entry, AppKit/SwiftUI bridge, TCA store
- `Sources/WatchYourClaude/UI/` — views, charts
- `Sources/WatchYourClaude/Data/` — transcript parsing, file watching
- `Sources/WatchYourClaude/Resources/` — notification.wav, icon.png

## Build & package

```bash
swift build
bash package_app.sh
```

`package_app.sh` produces `WatchYourClaude.app` in the project root. It compiles, cleans the old bundle, copies the binary + resources, generates `Info.plist` (with `LSUIElement` so it's a menu bar-only app), and handles the icon.

**After any code change, always run `package_app.sh` before testing.**
