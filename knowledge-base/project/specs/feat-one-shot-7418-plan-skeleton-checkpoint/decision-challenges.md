# Decision Challenges — #7418

Headless run: surfaced here per ADR-084 routing rather than at an interactive gate. `ship` renders
this into the PR body and files an `action-required` issue.

## UC-1 — The plan does NOT implement the marker mechanism the issue specified

**Operator's stated direction (issue #7418, step 3):** *"write … a `<!-- planning in progress -->`
marker … make the in-progress marker load-bearing … Ensure the marker is removed when the plan is
finalized."*

**What the plan does instead:** carries the state in a dedicated frontmatter key,
`pipeline_resume:`, deleted at finalization.

**Why the challenge:** an HTML comment renders invisibly, so a leaked marker is silent — no reviewer
sees it and the next `/one-shot` reads a finished plan as resumable. `preflight` also strips HTML
comments from its combined input (`preflight/SKILL.md:492`). A frontmatter key is visible in every
diff, sits at a parseable fixed position, and is inert once deleted.

**What it costs:** the mechanism no longer matches the issue text, so the issue's step 3 is satisfied
in intent but not in letter.

**Recommendation:** accept the substitution. **The operator's stated direction remains the default —
say so and it will be implemented as written.**

## UC-2 — `status:` was considered and rejected (v1 used it; v2 does not)

v1 followed the "conform to existing precedent" instinct and put the state in `status:`. Three
reviewers independently measured the corpus: **338 of 1531 plans carry `status:` across 44+ values**,
and `status: planning` / `status: complete` already exist with human draft-state meaning. Reserving
tokens there would need a migration, an out-of-enum arm and a validator, and would still collide with
six other `status:` enums in the repo. v2 uses a dedicated key instead. Recorded because it reverses
a documented v1 decision.

## UC-3 — Scope grew from 2 files to 4 + test + ADR

The issue scoped "a pure ordering + incremental-persistence change to the plan skill plus the
recovery branch in one-shot". The plan adds `deepen-plan/SKILL.md`, `plan-issue-templates.md`, a
contract test and ADR-144.

Drivers: `deepen-plan` must clear the cursor or a designed HALT loops forever; the templates
reference is the canonical frontmatter definition and would otherwise become the most-wrong of three;
`wg-architecture-decision-is-a-plan-deliverable` requires the ADR. Two reviewers (DHH,
code-simplicity) argued `deepen-plan` should be deferred; the plan keeps it because the HALT loop is
reachable deterministically on the first try.

**Recommendation:** accept. Say the word and `deepen-plan` becomes a follow-up issue with a
documented non-goal.

## UC-4 — Deferred rather than folded in

- Stale `1800` budget figure (5 sites, 4 files) — v1 folded it in; cut in v2 because the AC passed
  green while the harmful text at `plan/SKILL.md:969` remained.
- Checkpoint-committing the skeleton for durability.
- An `archive-kb` guard for cursor-bearing plans.

Each becomes an issue during `/work` (tasks 6.1–6.3).
