# HermesUsageMonitor

Native macOS menu bar companion for monitoring AI subscription usage observed by Hermes Agent.

## Current state

This repository contains the initial SwiftUI menu bar scaffold:

- macOS 26+
- menu bar-only app using `MenuBarExtra`
- fixed app icon
- two subscription groups: OpenCode Go and ChatGPT
- quota/accounting UI backed by Hermes Agent's live usage bridge

The app is intentionally read-only. Hermes integration, quota snapshots, profile aggregation, and reset notifications will be implemented from the approved product specification.

## Hermes data bridge

Quota data is read through the app-bundled `hermes-usage-bridge` launcher. The launcher uses the existing Hermes virtual environment and Hermes Agent authentication: ChatGPT/OpenAI Codex is read through the upstream usage API and OpenCode Go through its usage endpoint. HermesUsageMonitor never stores provider credentials and never asks providers to authenticate separately.

The launcher and bridge resource are installed inside the app bundle by `scripts/build-app.sh`; Hermes Desktop does not need to be open.

Hermes local accounting is read read-only from the profile's `state.db` via SQLite. The app maps supported technical providers such as `openai-codex` and `opencode-go` to commercial subscriptions and ignores unsupported sources. It never derives a quota percentage from historical token usage.

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

To verify Hermes compatibility after an update and save a non-sensitive report:

```bash
./scripts/verify-hermes-compatibility.py
```

Reports are written under `~/.hermes/update-safe/`.
