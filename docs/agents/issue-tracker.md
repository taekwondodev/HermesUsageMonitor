# Issue tracker: GitHub

Issues, specs, and tickets for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- Create: `gh issue create`
- Read: `gh issue view <number> --comments`
- List: `gh issue list`
- Comment: `gh issue comment <number>`
- Labels: `gh issue edit <number> --add-label` / `--remove-label`
- Close: `gh issue close <number> --comment`

Infer the repository from `git remote -v`; `gh` resolves it automatically inside this clone.

## Workflow

- Specs are GitHub issues.
- Tracer-bullet tickets are GitHub issues.
- Use native GitHub issue dependencies for blocking relationships when available.
- Claim work with `gh issue edit <number> --add-assignee @me`.
- Close implementation tickets only after code review passes and the commit lands.
