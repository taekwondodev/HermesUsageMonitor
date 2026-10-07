# Issue labels

## Categories

`bug` and `enhancement` are fixed category labels. Quick capture uses exactly one.

## Readiness

- `needs-grilling`: an intentionally incomplete issue awaiting a grilling session.
- `ready-for-agent`: a complete specification or implementation ticket ready for implementation.

Replace `needs-grilling` with `ready-for-agent` when publishing the complete specification.

## Activity

- `parked`: default for new issues and tickets; also apply when the user explicitly parks work.
- `in-flight`: apply when the user explicitly starts, resumes, or selects an issue as current work.

Keep exactly one readiness label and one activity label per open issue. When changing a dimension, replace its label in one update, preserve the other dimension and unrelated labels, then read back the result.

## Closure

Preserve `wontfix` for work that will not be pursued. It is a closure label, not a readiness or activity state.

For additional workflow markers, follow the invoking skill and check existing GitHub labels before creating any. Avoid duplicate labels for the same role.
