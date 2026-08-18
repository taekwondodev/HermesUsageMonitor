# ADR-0001: Notify only on observed quota reset transitions

- Status: Accepted
- Date: 2026-08-18

## Context

HermesUsageMonitor performs manual and automatic quota refreshes. A manual refresh can return newer consumption values, but clicking refresh is not itself a reset event. Providers expose quota windows such as `5 hours`, `Weekly`, and `Monthly`, sometimes with a reset timestamp.

The app must avoid false notifications, retroactive notifications after restart, and invented reset estimates.

## Decision

Keep manual refresh behavior unchanged. Reset notification detection runs on consecutive live observations and only emits when the provider data proves that a quota window reset occurred. A reset that happened while the app was stopped establishes the first post-launch baseline and does not notify. If the provider does not expose a verifiable reset signal, the app does not notify.

A manual refresh is allowed to emit a notification when that refresh observes the same verified reset transition. The button action itself is never a notification trigger.

The exact transition is: previous `usedPercent > 0`, current `usedPercent == 0`, and current `resetAt > previous resetAt`. Repeated observations such as `0% → 0%` do not notify. Multiple windows resetting in one observation are aggregated into one notification.

## Consequences

- Refresh remains useful for immediately updating consumption values.
- Notification timing depends on the next live observation after the provider reset; there is no provider push listener.
- Reset detection must be implemented in the Service/domain layer, not in the SwiftUI button handler.
- Tests must distinguish manual refresh data changes from reset transitions.
