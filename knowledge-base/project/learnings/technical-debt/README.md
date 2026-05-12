# Technical Debt Ledger

Operator-facing ledger of known tech debt in the Soleur plugin codebase. Each `.md` file in this directory is a single debt entry — context, root cause, and the smallest fix that closes the entry.

The ledger is populated **reactively** by [/soleur:compound](../../../../plugins/soleur/skills/compound-capture/SKILL.md) after fixes ship, then drained **interactively** by [/soleur:resolve-debt](../../../../plugins/soleur/skills/resolve-debt/SKILL.md). There is no scheduled scanner in this directory's scope — that surface is deferred to #3650 with falsifiable re-evaluation criteria.

## Frontmatter Contract

Every entry MUST have a `status` field. Other fields vary by schema (see below).

| Field | Required when | Optional when | Forbidden when |
|-------|---------------|---------------|----------------|
| `status: open` | new entry (default) | — | — |
| `status: resolved` | closing with a fix that shipped | — | — |
| `status: wont-fix` | closing without a fix (rejected, obviated, deferred indefinitely) | — | — |
| `linked_issue: <int>` | `status: resolved` | `status: wont-fix` | `status: open` |

`linked_issue` is the GitHub issue number as a YAML integer (no `#` prefix, no string quotes). The `learnings-researcher` and `kb-search` skills assume integer.

### Why `status` (not just absence-of-`linked_issue`)

`wont-fix` is the **load-bearing discriminator of record**. Without a `status` field, there is no way to express "we know about this debt and have decided not to fix it" — absence-of-`linked_issue` is ambiguous between "still open" and "decided not to fix." Future schema simplification must preserve `status` for this reason. The simpler-looking alternative (drop `status`, infer from `linked_issue`) is foreclosed.

## Two Schema Shapes

The ledger contains entries from two periods, both preserved as-is. Schema unification is a separate follow-up; do not mass-migrate.

**Schema A — legacy (entries dated 2026-02-12):**

```yaml
---
module: plugins/soleur
date: 2026-02-12
problem_type: best_practice
component: skills
tags: [skills, foo, bar]
severity: medium
status: open
---
```

**Schema B — current (entries dated 2026-03-03 onward):**

```yaml
---
title: <short title>
date: 2026-03-03
category: technical-debt
tags: [foo, bar]
severity: low
status: open
---
```

`/soleur:resolve-debt` and `--list` handle both shapes. Mutation preserves whichever shape it finds.

## Archive

`archive/` holds entries that are no longer surfaced for triage. `/soleur:resolve-debt` does not scan it. To restore an archived entry, move the file back to the parent directory (no other change needed).

## Non-Goals

These are explicit deferrals, not gaps:

- **`--undo-close` flag** — recovery is `git checkout -- <file>` (pre-commit) or `git revert` (post-commit). The skill never auto-commits; the in-place mutation is reversible by VCS, not by a second flag.
- **Schema unification** — the two shapes coexist by design. Tracked as a separate follow-up.
- **Bulk-resolve** — closing N entries in one invocation. Defer until usage data shows it's needed.
- **Severity filter** — `--severity high`. Defer until the ledger is large enough for the unfiltered table to be unwieldy.
- **JSON output for agent consumption** — defer until at least one downstream skill needs it.
- **Scheduled scanner / time-series dashboard** — deferred to #3650 (Spec B). Re-evaluation gated on observed close-loop activity post-Spec-A merge.

## Related

- Skill: [/soleur:resolve-debt](../../../../plugins/soleur/skills/resolve-debt/SKILL.md)
- Compound write path: [/soleur:compound](../../../../plugins/soleur/skills/compound-capture/SKILL.md) (template at `assets/resolution-template.md`)
- Deferred sibling: issue #3650 (scheduled scanner)
- Original parent issue: #2723
