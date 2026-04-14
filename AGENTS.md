# Repository Guidelines

## Project Structure & Module Organization

`modern-widget` is a small SwiftPM macOS menu bar app focused on off-chair break reminders. App code lives under `Sources/ModernWidget`, split by role: `Models/App` for app entry, `Services` for reminder state and notifications, `Views` for SwiftUI UI. Build artifacts land in `.build/`; `dist/` holds the signed `.app` bundle produced by the helper script. `script/build_and_run.sh` packages and launches the app. `Tests/` exists but is currently empty, add new test targets there when coverage lands.

## Build, Test, and Development Commands

Use SwiftPM for day-to-day work:

- `swift build`: compile debug build.
- `swift run ModernWidget`: launch from SwiftPM when bundle packaging is not needed.
- `swift test`: run tests. Today this fails with "no tests found" until a test target is added.
- `script/build_and_run.sh`: build, bundle, ad-hoc sign, then launch the menu bar app.
- `script/build_and_run.sh verify`: smoke test packaged app startup.
- `script/build_and_run.sh logs`: stream app logs after launch.

## Coding Style & Naming Conventions

Follow existing Swift 6 style: 4-space indentation, no trailing noise, minimal type annotations when inference is obvious. Use `UpperCamelCase` for types, `lowerCamelCase` for properties and methods, singular file names matching the main type like `AppModel.swift`. Keep concerns separated by folder, prefer flat control flow with early returns, keep side effects near UI actions or system boundaries. No formatter or linter is checked in, so match surrounding code and Swift API Design Guidelines.

## Testing Guidelines

Add Swift Testing or XCTest targets under `Tests/ModernWidgetTests`. Name files after the unit under test, for example `AppModelTests.swift`. Cover behavior, not implementation details: countdown math, pause and resume transitions, reminder reset behavior, notification permission handling. Run `swift test` before opening a PR.
