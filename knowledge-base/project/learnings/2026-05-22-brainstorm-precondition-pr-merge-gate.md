# Learning: Brainstorm Pre-Worktree Probe Misses "After PR #N Merges" Temporal Preconditions

**Date:** 2026-05-22
**Skill:** soleur:brainstorm
**Category:** workflow-patterns
**Tags:** premise-validation, brainstorm-phase-0, temporal-precondition, gh-pr-view

## Problem

Issue #4319 (DSAR author-only message redaction) was created on 2026-05-22
with body text framing the work as **deferred** pending three conditions:

> "After PR #4289 (legal scaffolding) merges. Then:
>  1. Confirm departed-member coverage (#4230) is shipped and stable
>  2. Confirm PR #4289 lands privacy-policy + DPD §2.3 + gdpr-policy text…
>  3. Brainstorm the predicate shape…"

By the time `/soleur:go #4319` triggered the brainstorm later the same day,
PR #4289 had **already merged** (2026-05-22T08:07Z), #4230 had **already
closed**, and #4229 had **already closed**. The re-evaluation gate the
issue body cited was satisfied.

The brainstorm skill's Pre-worktree premise probe at Phase 0 matches three
substring patterns:

- `does not yet exist`
- `deferred from #?\d+`
- `blocked by #?\d+`

Issue #4319's body contains **none** of those. It uses a temporal
construction (`After PR #N merges. Then:`) that the regex does not catch.
Worse, the probe only calls `gh issue view`, but #4289 is a **PR**, so
even if a `#4289` token had been extracted, `gh issue view 4289` would
have failed (returning `Could not resolve to a PullRequest with the number
of 4289` if accidentally invoked via `pr view` on an issue).

The brainstorm would have proceeded under the stale framing "this is
deferred, hold for PR #4289 to merge" and produced re-evaluation criteria
as the artifact — wrong-premise output.

## Recovery

I manually probed all three dependencies at Phase 0:

```bash
gh issue view 4230 --json state,title   # CLOSED
gh issue view 4229 --json state,title   # CLOSED
gh pr view 4289 --json state,mergedAt   # MERGED 2026-05-22T08:07:37Z
```

This produced the reframing "the gate is satisfied, this is ready to
plan now" before any leader spawn, before any artifact write. The
brainstorm proceeded with carry-forward triad assessments from the
parent #4230 brainstorm (which had spawned CTO+CPO+CLO earlier the same
day) and produced a focused spec for the FR5 predicate that was
explicitly carved out at plan-review.

## Key Insight

The Pre-worktree premise probe at Phase 0 was designed for
**status-verb framings** (`blocked by`, `deferred from`,
`does not yet exist`). It does not cover **temporal-precondition
framings** that are equally common in deferred-scope-out issues split
out of a plan-review or brainstorm:

- `After PR #N merges`
- `After #N ships`
- `When PR #N lands`
- `Gated on PR #N`
- `Pending PR #N`

These framings are **load-bearing** for "should this brainstorm run
now?" because the cited PR can flip from open → merged between issue
creation and brainstorm invocation (often the same day, since
plan-review and merge can happen hours apart).

The probe should ALSO distinguish PRs from issues — `gh pr view`
succeeds where `gh issue view` fails, and the `mergedAt` field is the
load-bearing state for PR-gated preconditions (a PR can be CLOSED
without being MERGED, which is a different premise outcome).

## Prevention (Workflow Change)

Extend the Pre-worktree premise probe in `plugins/soleur/skills/brainstorm/SKILL.md`
to:

1. Match additional substring patterns:
   `after PR #?\d+ (merges|lands|ships|is merged)` |
   `gated on PR #?\d+` |
   `pending PR #?\d+` |
   `when PR #?\d+ (merges|lands|ships)`
2. For each extracted `#N`, try `gh pr view <N> --json state,mergedAt`
   first; on failure, try `gh issue view <N> --json state`.
3. If a cited PR is `MERGED`, the temporal gate is satisfied — reframe
   the brainstorm from "deferred" to "ready" BEFORE Phase 0.5 leader
   spawn and BEFORE worktree creation, and surface the timestamp to
   the operator.

## Session Errors

None significant — the manual probe caught the staleness at Phase 0
before any artifact write. **Prevention:** the SKILL.md edit above
makes the temporal-precondition check mechanical instead of relying on
the operator/agent to remember to probe each cited PR.

## Cross-References

- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-22-dsar-workspace-member-extension-brainstorm.md`
- This brainstorm: `knowledge-base/project/brainstorms/2026-05-22-dsar-author-redaction-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-dsar-author-redaction-4319/spec.md`
- Issues: #4319 (this), #4230 (parent), #4229 (umbrella)
- PR dependency: #4289 (legal scaffolding, MERGED 2026-05-22T08:07Z)
- Related learnings:
  - `2026-05-18-premise-validation-and-multi-clause-predicate-reading.md`
  - `2026-05-21-brainstorm-premise-verification-call-site-granularity-and-adr-mutability.md`
  - `workflow-patterns/2026-05-20-brainstorm-ladder-collapse-and-dependency-chain-staleness.md`
