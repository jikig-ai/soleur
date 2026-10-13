---
feature: auth-flow-state-retention-prune
issue: 5739
branch: feat-one-shot-5739-auth-wal-reduction-v2
date: 2026-07-07
---

# Decision Challenges — #5739 v2

Surfaced during plan/deepen-plan for `/ship` to render into the PR body + file as an
`action-required` issue. These require operator judgment; they are NOT auto-applied.

## DC1 — Disposition of superseded WIP draft PR #5762

**Context.** This v2 PR ships the actionable #5739 deliverable and uses `Closes #5739`, so merging
it auto-closes the issue. The sibling draft PR **#5762** (branch `feat-5739-auth-wal-reduction`) is
a mid-soak measurement task that would then be left as a draft against a closed issue.

**Challenge (raised by architecture-strategist review, F3).** The repo's default is
never-defer-operator-actions, and closing #5762 is a scriptable one-liner
(`gh pr close 5762 --comment "superseded by #<v2>"`). Left undecided, two open PRs both reference
#5739.

**Why NOT auto-acted.** The operator **explicitly fenced #5762 off** in the task framing: "do NOT
reuse or nuke the existing branch/PR." That explicit directive **overrides** the never-defer
default for this specific PR (a User-Challenge per decision-principles/ADR-084 — the operator's
stated direction is the default). So /work and /ship do NOT auto-close or delete #5762.

**Operator decision needed.** Close #5762 as superseded (v2's post-soak measurement subsumes its
mid-soak record), OR keep #5762 open/for-record. Recommendation: confirm v2's measurement fully
subsumes #5762's snapshot, then close #5762 as superseded — but only on operator ack. The branch/
worktree must NOT be deleted regardless.
