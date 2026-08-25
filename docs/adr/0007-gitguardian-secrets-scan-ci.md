# ADR-0007: GitGuardian secrets scan for the repository CI

- Status: Accepted
- Date: 2026-08-24

## Context

The repository has no CI at all: no GitHub Actions workflows, no branch protection, only a
single main branch. Secrets or credentials committed to the working tree or anywhere in the
git history are never detected. The developer wanted a self-serve secrets scan that runs on
push to main and that an agent can reuse in a push-fix-push loop without a pull-request
workflow.

A first draft treated the full git history as a blocking gate. That would make the run red
permanently once any historical secret existed, and it would make the push loop unrecoverable:
a secret commit stays in history forever, so even a fix commit that removes the secret from
the tree cannot turn the gate green without rewriting history. The blocking gate therefore has to be the current working tree. Historical scanning is not
part of the repository workflow because it is not useful for this repository's push gate.

## Decision

Add a standalone GitHub Actions workflow (GitGuardian Secrets Scan) that runs on push to
main and on manual dispatch. It has one job:

- A blocking job that checks out the repository, installs ggshield, and runs a recursive
  scan of the current working tree. Any detected secret fails the run. This is the gate the
  push loop watches.


The blocking job runs the recursive path scan with `--yes`, because a recursive scan with
more than one file otherwise asks for confirmation and, in the non-interactive CI shell,
that prompt interrupts the scan before it starts (the run would pass green having scanned
nothing). `--yes` is required for the gate to actually scan.

No SARIF is produced and nothing is uploaded to GitHub code scanning. Enabled code scanning
is not available on this private repository without a GitHub Code Security license the
account does not have, so the Security-tab integration is dropped. Instead, when the gate
finds secrets it writes a JSON report and uploads it as a workflow artifact
(`gitguardian-findings`), because the GitGuardian web dashboard is not usable from this
account. Neither job requests `security-events: write`; the gate job requests `contents:
read` plus `actions: write` (the artifact upload needs the latter), and the history job
requests `contents: read` only.

The API key is read from the repository secret `GITGUARDIAN_API_KEY`; it is never committed,
logged, or surfaced in output.

The whole push-and-watch loop is exposed as one Makefile command (`make push-and-watch`)
that delegates to a script in the existing scripts directory, following the repository
thin-wrapper convention. The script pushes the current main, resolves the most recent run of
this workflow whose head matches the pushed HEAD, then runs `gh run watch --exit-status` so
the exit status propagates to the caller. It performs no additional local checks.

## Consequences

- Secrets in the pushed tree fail the CI run; a fix commit that removes the secret flips the
  gate green again without any history rewrite.
- Historical scanning is intentionally outside the CI workflow.
- The agent drives the loop with a single command and reads the outcome from its exit code.
- Activation depends on the `GITGUARDIAN_API_KEY` repository secret being set and on the
  workflow being valid; the main branch remains unprotected, so a manual dispatch can
  validate the workflow before the push trigger is relied upon.
- `gh run watch` requires authentication that can read checks (an OAuth or classic personal
  access token); a fine-grained token that cannot carry the checks read permission will not
  work.