# HermesUsageMonitor Agent Context

## Project rules

- Treat `CONTEXT.md` as the glossary and domain source of truth.
- Read the applicable records in `docs/adr/` before changing related behavior.
- Keep HermesUsageMonitor read-only with respect to provider quota data and Hermes runtime data.
- Keep provider credentials, tokens, passwords, and auth contents out of logs, UI, notifications, tests, and summaries.
- Use the existing Swift package structure and bounded context unless a design decision explicitly changes it.
- Use GitHub Issues through `gh` for specifications, tickets, dependencies, comments, and closure.
- Close implementation tickets only after code review passes and the commit lands.

## Build & install

The Makefile in the repository root is the entry point for build and tooling commands
(`make build`, `make verify`, `make check`, `make test`, `make clean`). Use it instead of
calling scripts or `swift run` directly.

It is a thin wrapper: each target delegates to the scripts under `./scripts` or to a
standard SwiftPM command. Those scripts remain the single source of truth for how the
`.app` bundle is assembled, bundled, signed, and verified — the Makefile never duplicates
build logic and never introduces a parallel path.

- `./scripts/` — holds the scripts and templates that back the Makefile targets (app
  build/install, installed-app verification, Hermes compatibility check), plus the bridge
  helper (`hermes_usage_bridge.py` + `hermes-usage-bridge`) and `Info.plist` shipped into
  the app bundle.

## Dev cycle

### Issue tracker

GitHub Issues for `taekwondodev/HermesUsageMonitor`, operated through `gh`. See `docs/agents/issue-tracker.md`.

### Issue labels

The canonical dev-cycle labels are `needs-grilling`, `ready-for-agent`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. Read `CONTEXT.md` and the applicable records in `docs/adr/`. See `docs/agents/domain.md`.
