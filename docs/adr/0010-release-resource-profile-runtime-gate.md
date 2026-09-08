# ADR-0010: Keep resident resource profiling in Release behind a runtime gate

- Status: Accepted
- Date: 2026-09-08

## Context

HermesUsageMonitor is a resident LSUIElement menu-bar app. Cold launch alone does not describe its ongoing cost, and the cost differs while the quota popover is open versus closed. The profile must use the installed Release artifact while keeping ordinary launches unchanged.

## Decision

Resident profiling remains compiled into the installed Release app and activates only when `HERMES_RESOURCE_PROFILE_FILE` is non-empty. The inactive path constructs no sampler, reads no monotonic clock, performs no OS task query, and performs no file I/O beyond the direct environment lookup.

The popover's existing `onAppear` and `onDisappear` lifecycle tags samples as open or closed. A 0.5-second coordinator captures physical footprint and process CPU percentage. The OS reader is the only code that calls task information APIs; aggregation and coverage validation are pure.

The chart palette is the monochrome ink, paper, and gray palette captured from the installed app icon. The H and four-point sparkle are rendered as the chart identity mark; no unrelated provider or system accent colors are introduced.

A session payload is written atomically when the app quits. It contains the tagged sample series, per-state aggregates, schema version, and validity. A session is valid only when both states have at least 15 seconds of tagged sample duration. Invalid sessions are reported by the measurement script and never become baselines.

A committed resource baseline contains only per-state memory average and peak, CPU average, and provenance: machine, operating system, architecture, and executable SHA-256. It contains no series, provider quota data, accounting data, credentials, or Hermes runtime contents. The chart renderer reads this baseline and the existing launch baseline to produce one share-ready PNG.

## Threat model

- Trust boundary: the environment variable supplies a local output path and arms the profiler.
- Assets: local measurement validity and resource metadata.
- Tampering: the measurement script hashes the installed executable before and after the run and records the hash as provenance.
- Information disclosure: payloads contain only process lifecycle and resource metrics; provider-sensitive data is excluded by type and schema.
- Denial of service: the measurement script bounds the manual session and terminates the process after success or failure.
- Elevation of privilege: profiling requests no additional permissions and runs with the app user's existing privileges.

## Consequences

Normal launches retain the same Release binary and pay only the environment gate. Manual profiling requires the owner to leave the popover closed and open for the required coverage, then quit. Rebaselining is a reviewed commit that updates the baseline and regenerates the chart; no automatic CPU or memory budget is introduced.
