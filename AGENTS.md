# HermesUsageMonitor Agent Context

## Project rules

- Treat `CONTEXT.md` as the glossary and domain source of truth.
- Read the applicable records in `docs/adr/` before changing related behavior.
- Keep Hermes runtime data read-only. Provider quota data is read-only except for user-confirmed single-credit redemption. Before changing redemption or provider writes, read `docs/adr/0005-manual-reset-redemption-remote-write.md`.
- Keep provider credentials, tokens, passwords, and auth contents out of logs, UI, notifications, tests, and summaries.
- Use the existing Swift package structure and bounded context unless a design decision explicitly changes it.
- Use GitHub Issues through `gh-axi` for specifications, tickets, dependencies, comments, and closure.
- Close implementation tickets only after code review passes and the commit lands.
- Push to main only through `make push-and-watch`: never bypass it with a bare `git push` to main.

## Build & install

Use the root Makefile for build and tooling commands instead of calling scripts or `swift run` directly. Run `make help` to discover targets.

Keep the Makefile a thin wrapper over `scripts/` or standard SwiftPM commands. The scripts own app assembly, bundling, signing, installation, and verification; do not duplicate that logic or introduce a parallel path.

Before changing app packaging or the bridge, inspect `scripts/`, which contains the build/install and verification scripts, bundled bridge helper, and `Info.plist`.

## Dev cycle

### Issue tracker

GitHub Issues for `taekwondodev/HermesUsageMonitor`, operated through `gh-axi`. Before tracker operations, read `docs/agents/issue-tracker.md`.

### Issue labels

Category, readiness, and activity labels, plus the `wontfix` closure label. Before classifying or transitioning issues, read `docs/agents/triage-labels.md`.

### Delivery

Default to direct delivery to `origin/main`. Before implementation or delivery, read `docs/agents/delivery.md` for route and target defaults.

### Domain docs

This is a single-context repository. Before exploring implementation work, read `docs/agents/domain.md`.
