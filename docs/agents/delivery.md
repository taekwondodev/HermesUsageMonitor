# Delivery policy

- Default mode: `direct`.
- Integration target: `taekwondodev/HermesUsageMonitor`, remote `origin`, branch `main`.
- PR base for an explicitly requested PR: the same repository and `origin/main`.
- PR source: a distinct task branch on `origin`. Use a fork only when explicitly selected for the task.
- Required verification: the local and remote gates below.

Before selecting a route or preparing a branch, read the shared delivery reference supplied by `implement` (`references/delivery.md`). An explicit task route overrides the default, but neither route authorizes a commit, push, PR publication, or issue closure by itself.

## Local verification

- Complete code review before delivery.
- For code changes, run `make test`, `make check`, and `make build`. The build installs and launches the app, so account for those effects before running it.
- For installed-app packaging or verification changes, also run `make verify`.
- For launch-performance changes, run `make launch-check` against the installed Release artifact. Read `docs/adr/0009-release-launch-probe-runtime-gate.md` before changing the probe, harness, or baseline.
- For resident-resource profiling changes, read `docs/adr/0010-release-resource-profile-runtime-gate.md`. Use its manual coverage requirements; there is no automatic CPU or memory budget.
- For documentation-only changes, verify referenced paths and commands, inspect the diff, and run `git diff --check`. App installation is not required.

Report blocked or unavailable checks explicitly. Rebaselining requires review rather than serving as a way to pass a failing measurement.

## Remote gate

Direct delivery follows `docs/adr/0007-gitguardian-secrets-scan-ci.md`. Push main only through `make push-and-watch`, which watches the GitGuardian Secrets Scan run matching the pushed commit and propagates failure.

The workflow in `.github/workflows/gitguardian.yml` runs on pushes to main and manual dispatch, not on pull requests. Do not describe its absence on a PR as a passing check. Recheck live repository rules before delivery and verify the exact delivered commit's remote result before claiming completion.

Close implementation tickets only after review passes and the commit lands.
