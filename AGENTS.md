# Project Context

macOS menu bar app for break reminders, walk history, daily supplement tracking, and local AI usage summaries. SwiftPM, Swift 6.3, macOS 26.0+.

## Structure

```text
Sources/ModernWidget/
  App/                 SwiftUI app entry and MenuBarExtra scene
  Models/
    HistoryRetention   shared three-month retention window
    Reminder/          countdown state, snapshots, schedules
    Usage/             Claude/Codex usage report models
    WalkHistory/       month grid and weekday helpers
  Services/
    DailySupplementStore daily supplement persistence
    Reminder/          timer engine and notification delivery
    Usage/             Claude/Codex log loading and pricing
    WalkHistoryStore   walk persistence and day counts
  Views/               tabbed menu bar panel, timer, calendar, usage panes
Tests/ModernWidgetTests/
  Usage/               Claude/Codex usage loader tests
  *.swift              reminder, walk history, supplement, retention tests
```

Build artifacts in `.build/`, signed bundle in `dist/`.

## Workflow

1. `swift-format format --in-place --recursive Sources/ Tests/`
2. `swift build`
3. `swift test`
4. `script/build_and_run.sh`

Script modes: `debug`, `logs`, `verify`, `telemetry`.

Tests use Swift Testing.

## Style

4-space indent. `UpperCamelCase` types, `lowerCamelCase` members. Flat control flow, early returns. See `.swift-format`.
