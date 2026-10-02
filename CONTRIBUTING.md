# Contributing to WatchYourClaude

Thanks for your interest in contributing! This document covers everything you need to get started.

## Requirements

- macOS 14.0+
- Swift 5.9+ (Xcode 15 or later, or the Swift toolchain installed via [swiftlang](https://www.swift.org/install/))

## Getting Started

```bash
# Clone your fork (or this repo directly if you have write access)
git clone https://github.com/smarty-kiki/watch_your_claude.git
cd watch_your_claude

# Build
swift build

# Package a runnable .app bundle and launch it
bash package_app.sh
open WatchYourClaude.app

# Release-mode build (same as CI)
bash package_app.sh --release
```

There is no test target yet — please verify your change by building the app bundle and exercising the affected UI (menu bar status, throughput chart, consumption chart).

## How Changes Are Accepted

1. Open an issue first for anything substantial (new features, behavior changes) so we can align on the approach.
2. Create a feature branch from `main`:
   ```bash
   git checkout -b feat/my-change
   ```
3. Keep PRs focused — one feature or fix per PR.
4. Push your branch and open a pull request against `main`. CI must pass.

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add per-model breakdown to consumption chart
fix: stop double-counting token events on session resume
docs: update README requirements
```

Allowed types: `feat`, `fix`, `docs`, `refactor`, `perf`, `chore`, `ci`. Commit messages may be written in English or Chinese; the type prefix is required.

### Pull Request Checklist

- [ ] `swift build` passes without warnings introduced by the change
- [ ] `bash package_app.sh` produces a working app bundle
- [ ] The menu bar app has been launched and the affected behavior verified manually
- [ ] README/CLAUDE.md updated if behavior or project structure changed

## Code Layout

See the "Project Structure" section in the [README](README.md). Key entry points:

- `Sources/WatchYourClaude/App.swift` — entry point, menu bar icon
- `Sources/WatchYourClaude/Services/ClaudeDataService.swift` — reads `~/.claude/` session data
- `Sources/WatchYourClaude/ViewModels/SessionMonitor.swift` — state management and file watching

## Reporting Bugs

Please use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml) and include your macOS version and any console output. Session files under `~/.claude/` may contain private data — never paste full JSONL transcripts.

## Licensing

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE) that covers this project.
