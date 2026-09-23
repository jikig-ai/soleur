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
