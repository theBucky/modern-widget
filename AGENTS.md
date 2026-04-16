# Project Context

macOS menu bar app for break reminders. SwiftPM, Swift 6.3, macOS 14+.

## Structure

```
Sources/ModernWidget/
  Models/App/   entry point
  Services/     state, notifications
  Views/        SwiftUI
```

Build artifacts in `.build/`, signed bundle in `dist/`.

## Workflow

1. `swift-format format --in-place --recursive Sources/`
2. `swift build`
3. `script/build_and_run.sh`

Script modes: `debug`, `logs`, `verify`, `telemetry`.

No test target yet.

## Style

4-space indent. `UpperCamelCase` types, `lowerCamelCase` members. Flat control flow, early returns. See `.swift-format`.
