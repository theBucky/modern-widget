# Project Context

macOS menu bar app for break reminders. SwiftPM, Swift 6.3, macOS 26.0+.

## Structure

```
Sources/ModernWidget/
  Models/App/   entry point
  Models/MenuBar/ panel placement
  Models/Reminder/ countdown state and schedule
  Models/WalkHistory/ month grid and retention rules
  Services/     state, notifications
  Views/        SwiftUI
Tests/ModernWidgetTests/ focused model tests
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
