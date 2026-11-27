# XScope Studio

[![macOS CI](https://github.com/zixew/XScope-Studio/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/zixew/XScope-Studio/actions/workflows/macos-ci.yml)

Native macOS developer companion for Xcode & iOS engineering — inspect Simulators in 2D/3D, diagnose Crashlytics & hangs, run static Swift/UIKit/SwiftUI code reviews, and monitor unit tests in one workspace.

## Features

- **Overview**: Real-time workspace snapshot, active Simulator & physical iPhone status, and quick diagnostics.
- **Crashlytics**: Parse `.ips` / crash reports, highlight culprit frames, and jump straight to source lines in Xcode (`xed`).
- **Leaks & Hangs**: Static & live freeze timeline, retain cycle (`[weak self]`) call-tree detection, and memory/CPU telemetry.
- **Code Review**: Fast local Swift, UIKit, and SwiftUI analyzer across Pull Request diffs, specific modules/folders, or the full project.
- **Simulator 2D / 3D Live UI Inspector**: Interactive 2D canvas and 3D exploded layer hierarchy with depth/zoom/wireframe controls, live sync, appearance toggles, and console/deep-link utilities.
- **Unit Tests & Utilities**: Run XCTest / Swift Testing targets, inspect results, and scan localization (`L10n`) keys.
- **Quick Jump (`⌘K`)**: Instant file, symbol, and module search with line-level jump to Xcode.
- **Theme & Custom Background**: Glassmorphic dark workspace with customizable wallpaper and English / Bahasa Indonesia (`EN` / `ID`) localization.

## Architecture

Built with Swift 6 (`swift-tools-version: 6.0`) and SwiftPM:

- `DevCompanionCore` — Pure Swift diagnostic engines, static analyzers, crash parsers, and project scanners.
- `DevCompanionMac` — Native macOS SwiftUI + AppKit desktop app structured with VIPER modules.
- `DevCompanionCoreTests` — Unit test suite covering core analyzers and parsers.

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode (for `simctl`, `xed`, and iOS Simulator tooling)

## Build & Test

```bash
# Build
swift build

# Run unit tests
swift test

# Run the desktop app
swift run DevCompanionMac

# Package macOS .app bundle
./scripts/build_app.sh
```
