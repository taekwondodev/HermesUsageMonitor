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

Building and installing the app goes through the scripts under `./scripts`, never a raw
`swift run`. The scripts are the single source of truth for how the `.app` bundle is
assembled, bundled, signed, and verified.

- `./scripts/build-app.sh` — build the release executable, assemble `~/Applications/HermesUsageMonitor.app` (resources, Info.plist, bridge helper, asset catalog / app icon), ad-hoc sign, install, and launch. Use this to build and install the app.
- `./scripts/verify-installed-app.sh` — verify an installed app bundle is complete and correctly signed, then launch it. Use this to confirm an install.
- `./scripts/verify-hermes-compatibility.py` — check the Hermes update-to-app compatibility path without mutating Hermes state.
- `./scripts/hermes_usage_bridge.py` + `./scripts/hermes-usage-bridge` — the bridge helper shipped into the app bundle.
- `./scripts/Info.plist` — template used by `build-app.sh`.

For quick compile/test iteration the SwiftPM commands still work (`swift build`, `swift test`),
but whenever the delivered `.app` is involved, route through the scripts above.

## Dev cycle

### Issue tracker

GitHub Issues for `taekwondodev/HermesUsageMonitor`, operated through `gh`. See `docs/agents/issue-tracker.md`.

### Issue labels

The canonical dev-cycle labels are `needs-grilling`, `ready-for-agent`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. Read `CONTEXT.md` and the applicable records in `docs/adr/`. See `docs/agents/domain.md`.
