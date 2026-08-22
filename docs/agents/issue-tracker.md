# Issue tracker: GitHub

Issues, specifications, and tracer-bullet tickets live in GitHub Issues.

## Commands

- Create: `gh issue create`
- Read: `gh issue view <number> --comments`
- List: `gh issue list`
- Comment: `gh issue comment <number>`
- Labels: `gh issue edit <number> --add-label` / `--remove-label`
- Assign: `gh issue edit <number> --add-assignee @me`
- Close: `gh issue close <number> --comment`

Infer the repository from `git remote -v`.

## Workflow

- Specs are GitHub issues.
- Tracer-bullet tickets are GitHub issues.
- Use native GitHub sub-issues and blocking relationships when available.
- Claim implementation work before modifying files.
- Close implementation tickets only after code review passes and the commit lands.
- Never include credentials, tokens, passwords, auth files, database contents, or sensitive logs in issues, comments, or summaries.
