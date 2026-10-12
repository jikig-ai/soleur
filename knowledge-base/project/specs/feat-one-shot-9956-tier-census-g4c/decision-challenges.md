# Decision Challenges — feat-one-shot-9956-tier-census-g4c

## 2026-10-11 — User-Challenge: the issue's prescribed remedy is infeasible

**Issue's stated direction:** #9956 asks for `removed { lifecycle { destroy = false } }`
claims (or the guard's declared-deletion equivalents) for egress-gateway resources it
believes #9529 deleted.

**Plan's deviation:** plan `knowledge-base/project/plans/2026-10-11-fix-tier-census-g4c-merge-base-plan.md`
does **not** add `removed {}` blocks or `INTENDED_DESTROYS`/`RETIRED_STATE_ABSENT`
entries. Premise validation: `git show 149a5d3b4e -- 'apps/web-platform/infra/*.tf'`
shows #9529 only *added* the six resources; all six remain declared and live on
`origin/main`. The G4c red on PR #9946 was a stale merge ref (`pull/9946/merge`
computed pre-#9529) diffed against the post-#9529 `origin/main` tip — main-side
additions misattributed as PR deletions.

**Why the deviation is correct:** a `removed {}` block naming a still-declared
address is itself a guard-contract violation and cannot coexist with the
`resource` block; a `RETIRED_STATE_ABSENT` entry trips G4g. The real defect is
the base ref (`origin/main` tip, a moving target) rather than missing claims —
ADR-282 §Consequence for the anchor already describes G4c as "the merge-base diff
the census computes".

**Ship rendering:** this challenge should render in the PR body so reviewers see
the premise correction; the PR `Closes #9956` because it eliminates the reported
red class, not because it performed the literal remedy.
