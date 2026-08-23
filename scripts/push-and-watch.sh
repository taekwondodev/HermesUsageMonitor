#!/bin/bash
set -euo pipefail

# Push the default branch and block until the GitGuardian CI run for that push finishes.
# Single entry point for the agent's push-fix-push loop: exits zero on a green run,
# non-zero on a failed run (e.g. a secret detected in the pushed tree).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

BRANCH="${1:-main}"

command -v gh >/dev/null 2>&1 || { printf 'gh CLI is required.\n' >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { printf 'gh is not authenticated (run gh auth login).\n' >&2; exit 1; }

# Resolve the pushed branch head up front; the run we watch must match it, not an older
# run or the checkout HEAD when a different branch is checked out.
HEAD_SHA="$(git rev-parse "refs/heads/${BRANCH}")"

WORKFLOW_NAME="${GITGUARDIAN_WORKFLOW:-GitGuardian Secrets Scan}"

git push origin "${BRANCH}"

# The run for this push may take a moment to register on GitHub. Poll until a run whose
# head sha equals the pushed HEAD appears, then keep that run id.
for _ in {1..90}; do
    RUN_ID="$(gh run list \
        --workflow "${WORKFLOW_NAME}" \
        --branch "${BRANCH}" \
        --limit 10 \
        --json databaseId,headSha \
        --jq ".[] | select(.headSha == \"${HEAD_SHA}\") | .databaseId" 2>/dev/null | head -1 || true)"
    [[ -n "${RUN_ID}" ]] && break
    sleep 2
done

if [[ -z "${RUN_ID}" ]]; then
    printf 'No run appeared for HEAD %s of "%s" on %s after push.\n' \
        "${HEAD_SHA}" "${WORKFLOW_NAME}" "${BRANCH}" >&2
    exit 1
fi

printf 'Watching run %s of "%s" on %s (head %s).\n' \
    "${RUN_ID}" "${WORKFLOW_NAME}" "${BRANCH}" "${HEAD_SHA}" >&2

# Exit status propagates: gh run watch --exit-status is non-zero when the run fails.
gh run watch "${RUN_ID}" --exit-status