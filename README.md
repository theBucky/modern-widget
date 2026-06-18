# ModernWidget

Small macOS menu bar app for people who sit too long and spend too much time with coding agents.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange)

## What it does

ModernWidget lives in the menu bar and opens a compact glass-style panel with three panes:

- **Break timer**: 60 or 120 minute countdown, pause/resume, overdue state, and native reminders.
- **Walk history**: monthly calendar with per-day walk counts and daily supplement status.
- **AI usage**: local Claude, Codex, and Pi usage cost summaries with a 30-day mini chart.

Everything runs locally. State is stored with `UserDefaults`, and AI usage is read from local Claude, Codex, and Pi JSONL logs.

## Screenshots

| Break timer | Walk history | AI usage |
| --- | --- | --- |
| ![Break timer pane](.github/main.png) | ![Walk history calendar pane](.github/calendar.png) | ![AI usage pane](.github/ai_usage.png) |

## Features

### Break reminders

- Menu bar status icon reflects running, paused, and overdue states.
- Countdown presets: `60 min` and `120 min`.
- Pause and resume preserve elapsed progress.
- Reset completes a break, records a walk, and restarts the countdown.
- Native macOS notifications repeat while the reminder stays overdue.
- Timer state survives app restarts.

### Health tracking

- Walks are grouped by calendar day.
- History calendar keeps the current month plus the previous two months.
- Daily supplement checkbox is shown on the timer pane.
- Calendar day labels indicate supplement completion for past days.

### AI usage tracking

- Claude usage is loaded from `CLAUDE_CONFIG_DIR`, `XDG_CONFIG_HOME/claude`, or `~/.claude`.
- Codex usage is loaded from `CODEX_HOME` or `~/.codex`.
- Pi usage is loaded from `PI_AGENT_DIR` or `~/.pi/agent/sessions`.
- Active and archived Codex sessions are deduplicated.
- Claude sidechain duplicates are collapsed.
- Cost estimates support known Claude and GPT/Codex/Pi model pricing.
- The panel refreshes usage roughly every 10 minutes.

## Requirements

- macOS 26.0+
- Swift 6.3+
- `swift-format` for formatting

## Build and run

```bash
swift-format format --in-place --recursive Sources/ Tests/
swift build
swift test
script/build_and_run.sh
```

The app bundle is created at `dist/ModernWidget.app` and ad-hoc signed for local use.

### Build script modes

| Mode | Description |
| --- | --- |
| `run` | Build and launch the app. Default mode. |
| `debug` | Build and launch the executable in `lldb`. |
| `logs` | Launch the app and stream process logs. |
| `telemetry` | Launch the app and stream subsystem logs. |
| `verify` | Launch the app and verify the process started. |

```bash
script/build_and_run.sh debug
script/build_and_run.sh logs
script/build_and_run.sh verify
```

## Project structure

```text
Sources/ModernWidget/
├── App/
│   └── ModernWidgetApp.swift          # SwiftUI app entry and MenuBarExtra scene
├── Models/
│   ├── HistoryRetention.swift         # shared three-month retention window
│   ├── Reminder/                      # countdown state, snapshots, schedules
│   ├── Usage/                         # coding agent usage report models
│   └── WalkHistory/                   # month grid and weekday helpers
├── Services/
│   ├── DailySupplementStore.swift     # daily supplement persistence
│   ├── Reminder/                      # timer engine and notification delivery
│   ├── Usage/                         # Claude/Codex/Pi log loading and pricing
│   └── WalkHistoryStore.swift         # walk persistence and day counts
└── Views/
    ├── MenuBarPanelView.swift         # tabbed menu bar panel shell
    ├── ReminderPaneView.swift         # timer, controls, supplement checkbox
    ├── WalkHistoryCalendarView.swift  # calendar pane
    ├── CodingUsageView.swift          # AI usage pane
    └── MenuBarIconView.swift          # menu bar status icon

Tests/ModernWidgetTests/
├── Reminder*                          # reminder state and schedule tests
├── WalkHistory*                       # calendar and retention tests
├── DailySupplementStoreTests.swift
└── Usage/                             # Claude/Codex/Pi usage loader tests
```

## Data and privacy

- No server component.
- No analytics.
- No network calls for usage tracking.
- Local app state is stored in `UserDefaults`.
- AI usage summaries are computed from local Claude, Codex, and Pi log files.
