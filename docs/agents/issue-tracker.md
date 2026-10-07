# Issue tracker: GitHub

Issues, specifications, and tracer-bullet tickets live in GitHub Issues for `taekwondodev/HermesUsageMonitor`. Before GitHub operations, load the `github-cli` skill. Use `gh-axi` for reads and writes; use `gh` only for `gh auth`.

Run commands from this clone after checking `git remote -v`; `gh-axi` infers the repository there. For `gh-axi api`, use this repository's qualified endpoint.

## Issue operations

- Create: `gh-axi issue create --title "..." --body-file <path>`.
- Read: `gh-axi issue view <number> --comments --full`; inspect labels and relevant comments as well as the body.
- List: `gh-axi issue list --state open` with appropriate `--label`, `--state`, and `--limit` filters. Read relevant issues individually.
- Update the existing body: `gh-axi issue edit <number> --body-file <path>`.
- Comment: `gh-axi issue comment <number> --body-file <path>`.
- Change labels: `gh-axi issue edit <number> --add-label "..." --remove-label "..."`.
- Claim: `gh-axi issue edit <number> --add-assignee @me`.
- Close: `gh-axi issue close <number> --comment "..."`.

Read the current body, labels, and relevant comments before editing. Paginate collections to exhaustion when selecting work or asserting completeness. Read back the exact issue or relationship after a write.

Never include credentials, tokens, passwords, auth files, database contents, or sensitive logs in issues, comments, or summaries.

## Capture and specification

Before classifying or transitioning issues, read `docs/agents/triage-labels.md`.

Quick capture creates one issue with exactly one category label, `needs-grilling`, and `parked`. When the complete specification is ready, update that issue in place and replace `needs-grilling` with `ready-for-agent` in one label transition. Preserve the issue number, comments, and activity label.

## Wayfinding and tracer-bullet tickets

Before creating a wayfinding map or choosing child-ticket labels, read `/wayfinder`'s Ticket Types section. Ensure its required labels exist before using them.

- Map: create one issue with the `wayfinder:map` label and the map body defined by `/wayfinder`.
- Child: create an issue and link it with `gh-axi issue subissue add <map> <child>`.
- Blocker: add a native dependency with `gh-axi api POST /repos/taekwondodev/HermesUsageMonitor/issues/<child>/dependencies/blocked_by --field issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the numeric database id from `gh-axi api /repos/taekwondodev/HermesUsageMonitor/issues/<n> --jq .id`, not the issue number or node id.
- Children: list in map order with `gh-axi issue subissue list <map>`.
- Open blockers: read `gh-axi api /repos/taekwondodev/HermesUsageMonitor/issues/<child> --jq .issue_dependencies_summary.blocked_by`.
- Frontier: select the first open, unassigned child in map order with zero open blockers.
- Claim: assign the selected ticket to the driving developer before modifying implementation files, and in the same update replace `parked` with `in-flight`. Read back assignee and labels.
- Decision resolution: comment with the answer, close the decision ticket, and append its summary and link to the map's Decisions-so-far.
- Implementation closure: close only after code review passes and the commit lands.

If native sub-issues are unavailable, maintain a map task list and a `Part of #<map>` line in each child. If native dependencies are unavailable, maintain a `Blocked by: #<number>` line and inspect every blocker's live state. Report the fallback; do not treat an API failure as evidence that no blockers exist.

Each implementation ticket describes one tracer-bullet slice and its affected components from the approved architecture.

## Native development links

For issue-backed PR work, use GraphQL through `gh-axi api POST /graphql --field query='<operation>' --full`. Paginate connections to exhaustion and verify associations after writes.

- Inspect `Issue.linkedBranches` and match repository plus branch name before creating an association.
- For an authorized new remote branch, use `createLinkedBranch` with explicit `issueId`, `repositoryId`, `name`, and a verified branch-point `oid` available in the source repository. Read back the association and ref.
- For an existing remote branch, preserve the ref. If no supported linking operation is available, report the association as pending.
- Verify PR closing links through `PullRequest.closingIssuesReferences`; a body mention alone is insufficient.

Create associations that propagate closure only when full-ticket delivery and closure on merge are authorized.

Before implementation or delivery, read `docs/agents/delivery.md`. Use `/commit` for requested local commits and authorized direct delivery, or `/pr` for requested PR publication.
