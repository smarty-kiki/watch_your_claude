# WatchYourClaude

A macOS menu bar app for real-time monitoring of Claude Code sessions, token throughput, and API consumption.

## What It Does

WatchYourClaude reads Claude Code's local session data from `~/.claude/` and surfaces three things in your menu bar:

- **Session Status** — whether each Claude session is busy or idle, with project names
- **Throughput Chart** — real-time input/output tokens per second, measured from user message to first API response
- **Consumption Chart** — 3-hour rolling window of input/output tokens bucketed by 10 minutes, breakdown by project and model

The menu bar icon color reflects overall status: green (busy), blue (idle), gray (inactive).

## Requirements

- macOS 14.0+
- Swift 5.9+

## Building

```bash
swift build
```

## Running

Build the `.app` bundle:

```bash
bash package_app.sh
open WatchYourClaude.app
```

## How It Works

- **Session scanning** reads `~/.claude/sessions/*.json` and falls back to `~/.claude/projects/*/*.jsonl` to detect active Claude Code sessions.
- **Token events** are parsed from session JSONL files. Throughput is computed using user-message latency (user event → first assistant response) rather than gaps between consecutive API calls.
- **Consumption** aggregates token usage into 10-minute buckets over the last 3 hours, grouped by project directory and model.
- **Notifications** can be enabled to play a sound when a session transitions from busy to idle.

## Project Structure

```
Sources/WatchYourClaude/
├── App.swift                  # Entry point, menu bar icon, scene setup
├── Services/
│   └── ClaudeDataService.swift    # Reads ~/.claude/ session data
├── Models/
│   ├── SessionInfo.swift          # Active session metadata
│   ├── TokenEvent.swift           # Parsed API token usage event
│   ├── ThroughputPoint.swift      # Tokens-per-second data point
│   └── ConsumptionBucket.swift    # 10-min token aggregation
├── ViewModels/
│   └── SessionMonitor.swift       # Polling timers, state management
├── Views/
│   ├── ContentView.swift          # Main menu bar window
│   ├── SessionStatusView.swift    # Active session list
│   ├── ThroughputChartView.swift  # TPS line chart
│   └── ConsumptionChartView.swift # Token consumption bar chart
└── Resources/
    ├── icon.png
    └── notification.wav
```
