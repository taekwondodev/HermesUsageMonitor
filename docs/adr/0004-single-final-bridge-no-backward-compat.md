# ADR-0004: Bridge contract has a single final version, no backward compatibility

- Status: Accepted
- Date: 2026-08-22

## Context

The bundled bridge (`scripts/hermes_usage_bridge.py` plus its launcher) emits a JSON usage contract that `HermesUsageCommandReader` decodes. The bridge and the app are built and shipped together in the same `.app` bundle: `build-app.sh` copies the Python script into `Resources/` and the launcher into `Contents/Helpers/`. Because producer and consumer travel as one unit, their contract version can never legitimately diverge at runtime.

The previous convention incremented an explicit contract version on each change (`VERSION = 1` then `VERSION = 2`, mirrored by `HermesUsageCommandReader.contractVersion`), and the reader rejected any payload that did not match. That version gate guards nothing real: there is no runtime condition in which the bundled bridge and the app are at different contract versions. The real compatibility boundary with Hermes is the import of `agent.account_usage` inside the bridge, which `load_usage_api` already validates with `callable(...)` checks.

Issue #34 introduced a second version of the bridge contract. This change records the decision that new contract changes replace the previous contract outright rather than being stacked as parallel supported versions.

## Decision

The bridge contract has a single final shape with no version field and no backward-compatibility path.

- Remove `VERSION` and the emitted `"version"` field from `hermes_usage_bridge.py`.
- Remove `contractVersion`, `Payload.version`, and the `guard payload.version == ...` gate from `HermesUsageCommandReader`.
- Remove the now-dead `ManualResetUnavailableReason.unsupportedVersion` case and the test cases that verified an unsupported bridge version.

Any future contract change edits the bridge and the reader in the same commit; the old contract is replaced, never coexists.

## Scope of this decision

This applies only to the internal bridge contract. The file-based readers `HermesQuotaSnapshotReader` (quota-snapshot.json) and `HermesAccountingReader` (accounting.json) keep their version gates: their producer is external or theoretical, and the version field there is the only future protection against an unknown shape.

## Consequences

- New bridge contract changes are applied as a single atomic change instead of a version bump.
- An outdated or externally replaced bridge surfaces as malformed data or a `BridgeError` from the Hermes API import, which is acceptable for a development-only condition the bundled pair can never reach.
- The version comparison logic and its error states no longer exist in the bridge path; nothing needs manual version coordination during future bridge changes.