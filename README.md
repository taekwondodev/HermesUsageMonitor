# HermesUsageMonitor

Native macOS menu bar companion for monitoring AI subscription usage observed by Hermes Agent.

## Current state

This repository contains the initial SwiftUI menu bar scaffold:

- macOS 26+
- menu bar-only app using `MenuBarExtra`
- fixed app icon
- three subscription groups: Nous Portal, OpenCode Go, and ChatGPT
- empty-state UI while Hermes data integration is pending

The app is intentionally read-only. Hermes integration, quota snapshots, profile aggregation, and reset notifications will be implemented from the approved product specification.

## Open in Xcode

Open `Package.swift` in Xcode 26.6 and run the `HermesUsageMonitor` executable scheme.

## Build from Terminal

```bash
swift build
```
