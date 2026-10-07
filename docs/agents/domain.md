# Domain docs

This repository has one bounded context.

## Before exploring implementation work

- Read root `CONTEXT.md`.
- Read records in `docs/adr/` that govern the behavior being investigated or changed.

Use glossary terms in issue titles, specifications, tickets, tests, and implementation notes. If a needed term is missing, reconsider the wording or note the gap for `/domain-modeling`.

Surface conflicts with accepted ADRs rather than silently overriding them.

## Layout and ownership

- `CONTEXT.md` owns domain terminology.
- `docs/adr/` owns qualifying decision rationale.
- `AGENTS.md` owns concise repository-wide operational rules.

There is no context map or per-package domain layout. Reuse existing authoritative records; create glossary entries or ADRs only when a resolved term or qualifying decision requires them. Missing optional domain documents are not a setup blocker.
