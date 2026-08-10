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
contract test and ADR-175.

Drivers: `deepen-plan` must clear the cursor or a designed HALT loops forever; the templates
reference is the canonical frontmatter definition and would otherwise become the most-wrong of three;
`wg-architecture-decision-is-a-plan-deliverable` requires the ADR. Two reviewers (DHH,
code-simplicity) argued `deepen-plan` should be deferred; the plan keeps it because the HALT loop is
reachable deterministically on the first try.

**Recommendation:** accept. Say the word and `deepen-plan` becomes a follow-up issue with a
documented non-goal.

## UC-4 — Folded into this PR (superseding the earlier deferral)

- Stale `1800` budget figure (5 sites, 4 files) — v1 folded it in; cut in v2 because the AC passed
  green while the harmful text at `plan/SKILL.md:969` remained.
- Checkpoint-committing the skeleton for durability.
- An `archive-kb` guard for cursor-bearing plans.

Each becomes an issue during `/work` (tasks 6.1–6.3).

---

## v3 — the resume cursor was assessed and dropped (2026-08-10)

A 12-agent post-implementation review found twelve blocking defects in the `pipeline_resume:`
cursor, behind a 285/285 green suite. Every one was the same shape: a second progress signal that
could disagree with the plan file's own content, with the disagreement resolving to a fail-open arm.

Routed to the `soleur:engineering:cto` agent as an architecture fork (per this repo's rule that such
decisions go to the CTO rather than the operator). Ruling: **ship the durability half, delete the
cursor.** Completion is asserted from `## Acceptance Criteria` — the one heading present in all three
detail-level templates, written last. Recorded in ADR-175.

**This deviates from the operator's stated direction in #7418**, which asked for a
`<!-- planning in progress -->` marker made load-bearing in `one-shot`'s recovery. The durability
half of that ask ships in full. The *marker* does not: neither as an HTML comment (invisible when
rendered, and `preflight` strips comments) nor as the frontmatter key that replaced it. The intent —
"a consumer can tell a half-written plan from a finished one" — is met by content assertion instead,
which needs no marker to leak, no writer to prescribe, and no table to invert.

Measured argument for the drop, since it is the operator's money: the cursor's checkpoint boundaries
did not subdivide either expensive block, so on the motivating incident's own shape it skipped five
haiku-pinned agents and re-ran the eleven session-model agents in full — while costing ~12–15 extra
tool calls and ~15–30k tokens on **every** happy-path run. It cost more on runs that succeed than it
saved on runs that stall.

If the operator wants the literal marker restored, that remains their call; ADR-175 §Considered
Options 2 and 5 record why neither form survived review.
