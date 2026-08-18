# HermesUsageMonitor domain glossary

HermesUsageMonitor monitors quota windows observed through Hermes Agent.

## Core terms

- **Quota window**: an independent provider limit such as `5 hours`, `Weekly`, or `Monthly`.
- **Used percentage**: the provider-reported percentage consumed by a quota window. It is not derived from local accounting.
- **Reset**: the provider-reported transition in which a quota window becomes available again after its window boundary passes.
- **Reset detection**: observing a reset transition by comparing consecutive live quota snapshots while the app is running.
- **Manual refresh**: a user-requested data acquisition. It keeps its existing behavior and may update usage values; it is not itself a notification event.
- A manual refresh may emit a notification only when its live result proves a reset transition; the button action itself never emits one.
- **Automatic refresh**: background acquisition used to keep the latest quota data and detect transitions without user interaction.
- **Retroactive reset**: a reset that occurred while the app was not running. It does not generate a notification on restart; the first live snapshot establishes the new baseline.
- **Unverifiable reset**: a window without a provider reset timestamp or another explicit reset signal. It does not generate a notification.
- **Reset notification transition**: `previous.usedPercent > 0` and `current.usedPercent == 0` and `current.resetAt > previous.resetAt`. A `0% → 0%` observation never notifies.
- **Aggregated reset notification**: simultaneous verified resets are grouped into one notification containing the provider and all reset windows.

The app treats Hermes and provider quota data as read-only observations. Local token/request/cost accounting cannot establish an official quota reset.
