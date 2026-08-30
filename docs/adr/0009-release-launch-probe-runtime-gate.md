# ADR-0009: Keep launch measurement in Release behind a runtime gate

- Status: Accepted
- Date: 2026-08-30

## Context

HermesUsageMonitor is an `LSUIElement` menu-bar app. It has no Dock bounce, and Instruments App Launch did not identify the persistent app process reliably because LaunchServices and the single-instance guard produced a transient process. Issue #43 therefore introduced an app-owned milestone from process launch to the first appearance of the menu-bar identity.

A Debug-only probe would measure a binary with different optimization, runtime checking, layout, and launch characteristics from the installed Release app. Removing the probe after one measurement would also make the committed baseline impossible to reproduce and would leave future launch regressions without the same milestone.

The probe is called from the menu-bar identity's `onAppear`. Its inactive path must not materialize the process environment or read uptime and process identity. JSON encoding, task creation, and file I/O belong only to an explicitly instrumented launch.

## Decision

The launch probe remains compiled into the installed Release app. It activates only when the launching process provides a non-empty `HERMES_LAUNCH_PROBE_FILE` environment variable. The inactive path checks that variable directly with `getenv` before reading monotonic uptime, reading the process identifier, allocating the payload, creating asynchronous work, or writing a file.

The project-owned launch harness sets the variable to a unique temporary path, launches the installed Release executable directly, and accepts a payload containing only the process identifier and monotonic system uptime. Direct executable launch is an accepted proxy for LaunchServices launch because the latter did not identify the persistent `LSUIElement` process reliably. A missing menu-bar milestone invalidates the sample instead of producing a shorter result. The harness validates the process identifier, uses atomic file replacement, terminates each launched process, and removes the temporary directory after each sample.

The harness start time uses `CLOCK_UPTIME_RAW`, and the app milestone uses `ProcessInfo.systemUptime`. On the supported macOS platform both are awake-time-since-boot clocks. They must remain in the same clock domain. Changing either clock is a harness-contract change that requires a new baseline.

The harness hashes the installed executable before and after each measurement run and rejects a run if the executable changes. The baseline's executable SHA-256 is provenance metadata. It is not compared with the candidate SHA-256 because a performance candidate is intentionally a different binary. Machine identity, sample count, and the baseline-derived p95 budget remain the regression contract.

A baseline is regenerated only when the measurement machine, operating system, milestone, harness contract, or accepted performance reference changes. Rebaselining is reviewed and committed rather than performed as routine cleanup.

## Threat model

- Trust boundary: the parent process controls the probe environment variable and destination path.
- Assets: launch behavior, local file integrity, measurement validity, and provider-sensitive data.
- Spoofing and tampering: the harness rejects a payload whose process identifier differs from the launched process and rejects an executable that changes during sampling.
- Information disclosure: the payload contains only process lifecycle metadata. It never includes quota data, accounting data, credentials, environment contents, or provider responses.
- Denial of service: the harness bounds every sample with a timeout and terminates the process after success or failure.
- Elevation of privilege: the probe gains no permissions. A caller able to supply the process environment acts with the same user privileges as the app. The implementation trusts that parent process to provide the harness's unique temporary path and does not enforce a directory restriction.

## Consequences

Normal launches retain the exact Release binary used for regression measurement while performing only a static state check and direct environment lookup for the dormant probe. Instrumented launches allocate and write the small payload after capturing the milestone, with the write performed outside the main actor.

The probe and harness are permanent observability infrastructure rather than temporary debug code. Their runtime gate, payload, baseline semantics, and rebaseline policy are durable constraints for future launch-performance changes linked to issue #43.
