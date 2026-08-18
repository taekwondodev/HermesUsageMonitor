# HermesUsageMonitor

Native macOS menu bar companion for monitoring AI subscription usage observed by Hermes Agent.

## Current state

This repository contains the initial SwiftUI menu bar scaffold:

- macOS 26+
- menu bar-only app using `MenuBarExtra`
- fixed app icon
- three subscription groups: Nous Portal, OpenCode Go, and ChatGPT
- quota/accounting UI backed by Hermes Agent's live usage bridge

The app is intentionally read-only. Hermes integration, quota snapshots, profile aggregation, and reset notifications will be implemented from the approved product specification.

## Hermes data bridge

Quota data is read from the machine-readable `hermes usage --json` command, which reuses Hermes Agent's existing authentication and provider/account-usage code. The app never stores provider credentials and never asks the providers to authenticate separately.

Hermes local accounting is read read-only from the profile's `state.db` via SQLite. The app maps technical providers such as `nous` and `openai-codex` to commercial subscriptions and keeps unknown or unavailable sources explicit. It never derives a quota percentage from historical token usage.

## Open in Xcode

Open `Package.swift` in Xcode 26.6 and run the `HermesUsageMonitor` executable scheme.

## Build from Terminal

```bash
swift build
```

## Install the local app bundle

To build, ad-hoc sign, install, and launch the personal menu bar app:

```bash
./scripts/build-app.sh
```

The script installs `HermesUsageMonitor.app` in `~/Applications`. If an existing instance is running, it asks for confirmation before replacing it. `swift run HermesUsageMonitor` remains a development mode; because it is not a `.app` bundle, UserNotifications are intentionally disabled in that mode.

To verify an already-installed bundle without rebuilding it:

```bash
./scripts/verify-installed-app.sh
```
