# Learning: Soak-gated tracker items + grep the helper signature before accepting an issue-body obstacle

## Problem

`/soleur:go #5689` routed a two-item tracking issue to brainstorm. Two traps:

1. **Item 1 (producer investigation)** was explicitly "required-on-signal" — gated
   on a one-week soak after arm-1 (#5684) merged. Barreling into a full
   worktree+triad brainstorm for it would have produced a spec for work whose
   trigger condition had not fired.
2. **Item 2's** issue body asserted an obstacle: *"needs a push-shaped payload and
   expands blast radius."* Taken at face value, that biases toward a heavyweight
   synthetic-event design (or toward leaving the item deferred).

## Solution

1. **Verify the soak clock before scoping a soak-gated item.** `gh pr view 5684
   --json mergedAt` showed arm-1 merged 2026-06-29T13:06:55Z — ~30 min before the
   session. The one-week soak had not elapsed, so item 1 had no signal to
   investigate. Surfaced this to the operator via AskUserQuestion; operator chose
   to brainstorm **only item 2**. Item 1 stayed OPEN and soak-gated.
2. **Grep the consuming helper's actual signature before accepting the obstacle.**
   `syncWorkspace(installationId, workspacePath, logger, …)`
   (`workspace-reconcile-on-push.ts:331`) pulls the **live default-branch HEAD**
   itself — it never consumes `headSha`/`beforeSha` (those only populate the
   `kb_sync_history` audit row). So the "needs a push-shaped payload" obstacle
   applied **only** to the synthetic-event approach the issue author had in mind.
   A **direct in-arm `syncWorkspace` call** sidesteps both the payload obstacle and
   the blast-radius concern, and preserves ADR-033 I6 (no Inngest event). All three
   triad leaders (CTO/CPO/CLO) converged on it. No migration needed
   (`kb_sync_history.trigger` is free-form JSONB).

## Key Insight

- **A "required-on-signal" / soak-gated tracker item is not scopeable until its
  trigger fires.** Check the merge/clock date of the gating event first; if the
  window hasn't elapsed, scope only the independently-actionable sibling items and
  leave the gated one open. Don't spin up worktree+leaders for work that can't yet
  begin.
- **An issue body's stated obstacle is usually a property of the approach the
  author imagined, not of the goal.** When a body says "needs X / expands blast
  radius," grep the consuming helper's real signature before accepting it — the
  obstacle frequently dissolves under a different, lighter approach. This is the
  same family as the existing reuse-premise / `verify-reuse-premise-post-vs-read`
  learnings, applied to an *obstacle* claim rather than a *capability* claim.

## Session Errors

None detected. The session ran clean — routing, premise validation, and triad
convergence all worked first-pass.

## Tags
category: workflow-patterns
module: brainstorm, cron-workspace-sync-health
related: 2026-05-30-verify-reuse-premise-post-vs-read-and-arming-is-the-real-gap.md, 2026-05-18-premise-validation-and-multi-clause-predicate-reading.md
issue: 5689
