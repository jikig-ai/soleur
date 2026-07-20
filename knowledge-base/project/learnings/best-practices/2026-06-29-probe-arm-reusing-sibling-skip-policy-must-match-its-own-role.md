# Extending one arm of a multi-arm probe must re-derive its skip/silent policy from THIS arm's role, not copy a sibling's

## Problem

`cron-workspace-sync-health` has three arms over the same `workspaces` table:
- **arm-1** — the **freeze detector**: reports (now also reconciles) `repo_status='ready' AND github_installation_id IS NULL` workspaces. Its entire reason to exist is to keep a stuck/frozen workspace **visible** (the ~5-week founder-KB freeze it was built after).
- **arm-3** — the **went-quiet probe**: needs to parse `owner/repo` from `repo_url` to hit GitHub. On a malformed/legacy `repo_url` it `continue`s **silently** — correct, because it simply can't run its probe and there's nothing actionable beyond what arm-1 already covers.

When #5675 extended arm-1 from reporter to reconciler, the plan prescribed "malformed `repo_url` → silent count-skip, **mirroring arm-3**." That was implemented (a `decision.reason !== "malformed-repo-url"` suppression on the signal). It passed tsc + the full vitest suite green.

But it was a **pr-introduced observability regression**: pre-#5675 arm-1 reported *every* finding unconditionally. A solo `ready + NULL-install + malformed-repo_url` workspace — doubly broken, definitely stuck — went **silent**. The freeze detector stopped reporting exactly the kind of frozen workspace it exists to surface.

## Root cause

The malformed-skip policy was copied from a **sibling arm with a different semantic role**. arm-3's "can't probe → skip silently" is right for a *detection* arm (no signal to add). arm-1 is a *reporter/freeze-detector* — for it, "can't resolve" is precisely the state to keep visible. Same table, same parse, opposite correct disposition.

Two orthogonal review agents (data-integrity L2, user-impact Finding-1) caught it post-implementation; the plan's 7 plan-time agents + the green unit suite did not — because the suite encoded the (wrong) plan AC, and plan-time review reasoned about "is the disclosure accurate?" not "does this arm's silence match its job?"

## Solution

arm-1 keeps the visible `op:ready-null-installation` signal for **every** skip reason (`team-workspace-never-auto-detect`, `needs-reauth`, AND `malformed-repo-url`) — the signal-suppression branch was removed entirely, and the skip reason tightened to a literal union. The shared `owner/repo` parse was extracted to a `parseOwnerRepo` helper used by both arms (the *parse* is shared; the *skip disposition* is per-arm). The plan + ACs were synced to the corrected behavior.

## Key Insight

When you extend one arm of a multi-arm probe/detector by reusing a sibling arm's skip / silent-`continue` / fall-through policy, **re-derive that policy from THIS arm's semantic role** — do not copy it because the two arms share a table or a parse step. A detection arm's "can't run → skip silently" is the wrong default for a reporter arm whose entire purpose is to keep the unresolvable state visible. The shared mechanics (a slug parser) are fine to share; the *disposition on failure* is role-specific. The cheapest catch is to ask, per skip branch: "if this arm goes silent here, does the user lose the only signal for a genuinely stuck state?" If yes, keep the signal regardless of what the sibling arm does.

## Session Errors

- **Bash CWD drift** (`./node_modules/.bin/tsc: No such file or directory`, exit 127) — the Bash tool does not persist `cd` across calls; a verification command ran from the worktree root instead of `apps/web-platform`. Recovery: re-ran with an explicit `cd <app> && …`. Prevention: already covered (the `work` skill + several learnings document this); chain `cd` into every per-app test/typecheck call. One-off.
- **Degraded review-agent spawn** — `user-impact-reviewer`'s first spawn returned a generic deferred prompt ("Review this PR.") with 0 tool-uses. Recovery: re-spawned with the full prompt; it then ran clean. Prevention: already covered (review skill Rate-Limit-Fallback gate + the "parallel review batches stall" sharp edge — proceed on partial coverage, re-spawn the degraded one). One-off transient.

## Tags
category: best-practices
module: apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts
issue: 5675
related: [[2026-06-18-multi-workspace-per-installation-breaks-founder-resolve-and-ready-clone]]
