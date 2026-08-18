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

## Hermes quota snapshot contract

The first repository adapter reads a read-only snapshot at `$HERMES_HOME/usage/quota-snapshot.json`, or `~/.hermes/usage/quota-snapshot.json` when `HERMES_HOME` is unset. Hermes may write the snapshot; this app never creates or modifies it.

The current contract uses `version: 1`, an ISO-8601 `capturedAt`, a `freshness` value (`live`, `persisted`, or `stale`), one commercial subscription, a source identifier, and quota windows with `rolling-5h`, `daily`, `weekly`, or `monthly` kinds. Percentages must be finite values from 0 through 100. Missing, malformed, unsupported, or unreadable snapshots are reported as unavailable rather than estimated.

## Hermes local accounting contract

Hermes local accounting is read from `$HERMES_HOME/usage/accounting.json`, or `~/.hermes/usage/accounting.json` when `HERMES_HOME` is unset. The app never writes this file. Version 1 contains an `entries` array grouped by commercial `subscription`; each entry may include a `profile`, `tokens`, `requests`, `models`, `provider`, and `cost`. Missing fields remain unavailable and are not estimated. Multiple profiles are displayed under their commercial subscription, with technical provider/model detail secondary to that grouping.

## Open in Xcode

Open `Package.swift` in Xcode 26.6 and run the `HermesUsageMonitor` executable scheme.

## Build from Terminal

```bash
swift build
```
