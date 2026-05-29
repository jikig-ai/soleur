# Learning: Read the governing ADR's Alternatives-Considered table before proposing to reverse/extend it

## Problem

Brainstorm #4581 needed to fix "an org-targetable flag (`byok-delegations`) can't be
scoped to one org." The issue body framed gap 3 as a blast-radius problem and suggested
"likely needs per-feature segments OR per-org override granularity." The governing decision,
ADR-043 (Flagsmith per-org targeting), had already chosen a **single shared `org-targeted`
segment** and explicitly **rejected "N per-org segments"** for *segment explosion*.

The naive path is to treat the ADR's binary (shared-segment vs per-org-segment) as the
option space and pick one — which would have led to recommending the per-org-segment model
the ADR rejected, re-importing the explosion concern.

## Solution

Read ADR-043's `## Alternatives Considered` table **directly** (not a paraphrase) before
proposing approaches. The table listed exactly two scoping options: per-org segments
(rejected: O(orgs) explosion) and the single shared segment (chosen). It **never enumerated
per-feature segments** — one segment per org-targetable flag, O(features) ≈ 2 today.

Per-feature segments resolve ADR-043's *stated rejection reason* (bounded on the small axis,
not the customer axis) AND provide the missing per-(feature,org) granularity AND map onto the
existing `flip.sh --org` membership-edit code path. The 2026-05-25 audit-env-flags brainstorm
that fed ADR-043 also framed the choice as the same binary — so the third option had been
invisible across two artifacts. Surfacing it was the brainstorm's entire value-add, and it
only appeared because the ADR's alternatives table was read line-by-line.

CTO recommended the rejected option (B, per-org segment); CPO recommended A (per-feature).
Reading the ADR made the reconciliation decisive: A bounds segments on features, B relocates
the explosion to the unbounded customer axis. Operator chose A.

## Key Insight

When a brainstorm proposes to **reverse or extend a governing ADR's data-model decision**,
read the ADR's `## Alternatives Considered` table verbatim. The rejected alternatives encode
the decider's *reason* — and the winning new option is often one the ADR never listed that
**dismantles that exact rejection reason**. A "reversal" brainstorm that only chooses between
the ADR's already-enumerated options is doing the ADR's work over again; the leverage is in
the un-enumerated third option. Pair this with the existing brainstorm rule to verify
register/ledger citations against canonical content — extend it to ADR alternatives tables.

## Session Errors

1. **`gh pr view 4232` returned empty** — #4232 is an issue, not a PR. Recovery: fell back to
   `gh issue view 4232`. Prevention: when a `#N` ref's type is unknown, query issue-or-PR in
   one step (`gh issue view N || gh pr view N`); expected, low-cost.
2. **`git ls-files | grep flag` returned empty in the bare-repo root** — the bare root has no
   populated index. Recovery: `git ls-tree -r main --name-only | grep ...`. Prevention:
   already covered by `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md` —
   in a bare root, use `git ls-tree -r <ref>` / `git show <ref>:<path>`, never `git ls-files`.
3. **`git show main:knowledge-base/overview/constitution.md` → false "no kb at main"** — that
   exact path doesn't exist; kb does (5225 tracked files). Recovery: confirmed via
   `git ls-tree -r main | grep -c '^knowledge-base/'`. Prevention: probe directory existence
   with an `ls-tree` count, not a single guessed file path.

## Tags
category: workflow-patterns
module: brainstorm
issue: 4581
related: ADR-043-flagsmith-per-org-targeting, 2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification
