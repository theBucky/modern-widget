# Repository agent guide

## Engineering rules

- Choose the simplest correct implementation for current requirements. Extract shared logic only when genuine duplication or a shared invariant demands the abstraction; keep one-off code inline.
- Build in layers: start from the smallest version that works end to end, then add each capability on top of a working product.
- Keep components modular, concerns separated, and code self-explanatory. Rewrite unclear logic rather than defending a design with comments.
- Preserve runtime behavior during formatting, lint, typing, and test-structure changes.

## Boundaries

- Treat `refs/` as read-only reference material; do not edit or import from that directory.
- Do not preserve backward compatibility. Remove obsolete paths directly; skip compatibility layers, fallbacks, and migrations.
- Keep public pull requests, commits, generated files, and documentation free of private names, internal context, customer-derived data, and AI attribution.

## Structure

```text
Sources/ModernWidget/
  App/                 SwiftUI app entry and MenuBarExtra scene
  Models/
    HistoryRetention   shared three-month retention window
    Reminder/          countdown state, snapshots, notification issues
    Usage/             Claude/Codex/Pi usage report models
    WalkHistory/       month grid, weekday helpers, day cell display
  Services/
    DailySupplementStore daily supplement persistence
    Reminder/          timer engine and notification delivery
    Usage/             Claude/Codex/Pi log loading and pricing
    WalkHistoryStore   walk persistence and day counts
  Views/               tabbed menu bar panel, timer, calendar, usage panes
Tests/ModernWidgetTests/
  Usage/               Claude/Codex/Pi usage loader tests
  *.swift              reminder, walk history, supplement, retention tests
```

## Scripts and commands

1. `swift-format format --in-place --recursive Sources/ Tests/`
2. `swift build`
3. `swift test`
4. `script/build_and_run.sh`

Script modes: `debug`, `logs`, `verify`, `telemetry`.
