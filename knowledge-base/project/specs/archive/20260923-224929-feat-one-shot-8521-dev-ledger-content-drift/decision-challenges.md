---
feature: feat-one-shot-8521-dev-ledger-content-drift
issue: 8521
plan: knowledge-base/project/plans/2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md
---

# Decision challenges: feat-one-shot-8521-dev-ledger-content-drift

These are Taste and User-Challenge findings from plan review (headless one-shot run). They were
recorded here and not applied, so the operator can decide on them at ship time.

## DC-1 (User-Challenge): pull a minimal dev-reconcile workflow into this PR

**Source:** CTO devex review, P1.

**Plan says:** the guard fails a PR that edited or renamed an already-applied unmerged migration. The
recommended fix needs no database write: restore the applied body and add a new migration. Discarding
an applied version still requires the manual dev reconcile procedure. The convenience path is deferred
to #8605, re-evaluated after "more than 2 extra-migration PRs a month".

**Challenge:** the 2026-09-21 record shows 26 edit-after-apply rows across about 260 migrations. At
roughly 1 migration in 10, the #8605 trigger would fire almost at once. Agents and fork contributors
have no dev credentials, so a guard with only a manual discard path leads to more ad-hoc dev writes
(the 2026-09-22 fix was one, and it went unrecorded). The proposal is a dispatchable, audited "revert
my unmerged migration" workflow. It would apply the applied blob's `.down.sql`, delete the ledger row,
and only accept files that are unmerged and owned by the caller's branch.

**Why not applied:** it adds scope, and it has CI write to the shared dev ledger and schema. That is a
separate risk decision (ADR-084: stated scope is the default).

## DC-2 (Taste): warn about A1 before push, not after the heavy job

**Source:** CTO devex review, P1.

**Challenge:** a git-only local or ship-time check could catch most A1 cases without reading the
database, by flagging when an unmerged migration differs from the author's own `origin/<branch>` blob
(the blob that the PR's CI applied). The author would learn about it before waiting in the mutex queue.

**Why not applied:** it is a new surface (a ship-skill or hook check), outside CI. The authoritative
guard stays in CI either way.

## DC-3 (Taste): the 30-day freshness threshold for branch ownership

**Source:** deepen-plan security and observability reviews. Observability suggested 14 days; the plan
picks 30.

**What the plan decided:** a branch with no commit in 30 days stops owning rows, so its applied
migrations get the blocking `stale` verdict on main. The error names the branch. A shorter threshold
catches abandoned branches sooner but reds main more often for slow PRs. A longer one lets orphans
hide for longer.

**Why surfaced:** it is a policy value, not a technical correctness question.

## DC-4 (Taste): generalize the `detect-changes` guard-state step into a list

**Source:** DHH plan review and the deepen-plan architecture review.

**Challenge:** the base / introduction / deleted three-arm logic now exists twice. One copy is #8597's
inline step. The other is this plan's `ledger_guard` step, which is fed by a single path. A
list-driven step (or a composite action) would make the next guard a one-line addition.

**Why not applied:** refactoring #8597's step breaks its wiring asserts (T10/T11) and gains no
property for this PR.
