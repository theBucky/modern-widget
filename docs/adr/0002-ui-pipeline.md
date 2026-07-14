# ADR 0002: UI pipeline

Date: 2026-07-15

Status: Accepted

## Context

The menu bar UI is a tabbed panel with four panes fed by four observable stores. Two injection styles coexist: the stores travel as initializer parameters through `MenuBarPanelView` and `PaneBody`, which forward them untouched, while `UpdaterManager` and `LaunchAtLoginManager` arrive through the SwiftUI environment.

The usage pane already renders a computed value: `CodingUsageStore` publishes `CodingUsagePresentation`, the view displays it, and the display rules are testable without views. The timer and calendar panes derive display state inside view bodies instead: reminder phase to title, message, and tint mapping lives in `ReminderPaneView`; future-day dimming, supplement coloring, and fill selection live in `WalkHistoryCalendarView`. None of that logic is reachable from tests.

Two more irregularities: the rule that completing a break records a walk exists only as two adjacent calls in a button action, and `CodingUsageTodayTotalSection` embeds a debug-only animation replay harness behind `#if DEBUG`, giving one production view a second interface.

## Decision

### Composition

`ModernWidgetApp` is the single composition root. It constructs and owns the four stores as `@State` and places every observable object into the environment: `ReminderEngine`, `WalkHistoryStore`, `DailySupplementStore`, `CodingUsageStore`, `UpdaterManager`, and `LaunchAtLoginManager`. Views declare dependencies with `@Environment` by type and receive no store initializer parameters. `MenuBarPanelView` and `PaneBody` lose all store properties; each pane pulls exactly the stores it uses.

The menu bar label is the one exception: `MenuBarIconView` keeps its explicit `engine` parameter because it is constructed at the root, where the engine is in scope, and sits outside the panel content hierarchy.

Cross-store rules are wired at the composition root. `ReminderEngine` gains an `onBreakCompleted: (Date) -> Void` hook invoked from `completeBreak(at:)`; the root sets it to `walkHistoryStore.recordWalk`. The complete-break button calls only `engine.completeBreak(at: .now)`. The engine remains ignorant of walk history.

### Pane presentation values

Each pane converges on the usage pane's shape: store in, presentation value out, view renders the value. The value is the test surface; view bodies contain layout only.

The reminder status display moves to `Models/Reminder` as a value built from `ReminderSnapshot`. It exposes the formatted countdown or overdue title as a plain string, the status message, and a semantic emphasis case rather than a `Color`, so the model layer stays free of SwiftUI and equality checks work in tests. The view maps emphasis to styling. Tests pin the phase-to-display mapping, including the mm:ss padding and the overdue title.

The calendar day cell display moves to `Models/WalkHistory` as a value built from the cell date, walk count, supplement state, and reference day. It exposes semantic label and fill cases: future days dimmed, supplement taken versus pending, today highlight, walked-day fill. It joins `WalkHistoryMonth`, which already models the grid this way. Tests pin each rule, including the future-versus-today boundary.

Chart scaling in `CodingUsageChart` stays in the view. The bar floor and axis bound are interwoven with redaction and hover selection, which are view concerns; splitting them would leave both halves without a clear role.

### Debug replay harness

`CodingUsageTodayTotalSection` becomes a pure renderer of `CodingUsageTodaySummary`. The replay button, replay state, and synthetic start-summary generator move to a debug-only harness view in its own file, wrapped entirely in `#if DEBUG`. The harness owns the replay lifecycle and feeds the section a plain summary. `CodingUsageView` mounts the harness in debug builds and the section directly in release builds; that conditional is the only `#if DEBUG` in the usage views.

### Cleanup

The empty `Sources/ModernWidget/Models/Selection/` and `Tests/ModernWidgetTests/Selection/` directories are removed. `WalkHistoryCalendarView` renames `historyStore` and `supplementStore` to the canonical `walkHistoryStore` and `dailySupplementStore`.

Out of scope: `SettingsPaneView`, `MenuBarIconView` internals, chart internals, the `FormatStyle` adapters, and the `PanelLayout` and `PanelColor` constant namespaces. Settings keys, persisted formats, and visible behavior are unchanged.

## Consequences

Adding a pane means adding a store, a presentation value with tests, and a view that renders it; no plumbing edits in `MenuBarPanelView`. Display-rule regressions in the timer and calendar panes become test failures instead of visual diffs. The break-recording rule has one home, so future triggers such as a notification action cannot forget half of it.

Environment injection makes pane dependencies implicit at call sites; the `@Environment` declarations at the top of each pane are the dependency list. A pane mounted outside the app scene, such as in a preview, must supply its stores explicitly.
