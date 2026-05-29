---
title: Warn-level debounced mirror for recovered-fallback Sentry floods (severity alone does not stop alert-rule volume)
date: 2026-05-29
category: integration-issues
module: observability
issue: 4571
pr: 4571
related_pr: 3720
tags: [observability, sentry, debounce, silent-failure, feature-flags, flagsmith, alert-rules]
---

# Learning: For a recovered degraded path that floods Sentry, debounce the mirror — lowering severity to `warning` alone does NOT reduce alert-rule volume

## Problem

A production Sentry alert (`auth-callback-no-code-burst`, Sentry ID
`ac2d712121d94ad9ab154a16f6178fa7`) fired on `GET /login` with the chain
`TimeoutError → "getIdentityFlags failed and no default flag handler was provided"`.

The original fix-goal framing was "the request fails hard — add a Flagsmith
`defaultFlagHandler` so the page degrades gracefully." That premise was false:
`fetchRuntimeFlagsFromFlagsmith` already catches the SDK throw and returns `null`,
and `getRuntimeSnapshot` substitutes `runtimeEnvFallback()` (env-var mirror per
ADR-038). **The page already renders.** The Sentry "error" was the
`reportSilentFallback` mirror itself — emitted at `level: "error"` with no
debounce — for a recovered ~200ms timeout. Anonymous `/login` traffic
(health-checks, crawlers via `curl/8.5.0`) hammered the cache-cold window and
produced a burst of identical error events that tripped the alert.

## Solution

Two real defects, both in the *reporting*, not the *degradation*:

1. **Severity** — switch the recovered-timeout report from `reportSilentFallback`
   (error) to a warn-level path.
2. **Volume** — debounce per-segment so an edge slowdown cannot burst.

Implemented as a thin warn-level sibling of the existing `mirrorWithDebounce`,
reusing the **same** `_mirrorDebounce` `TtlDedupMap` instance:

```ts
export function mirrorWarnWithDebounce(err, ctx, key, errorClass): void {
  if (!_mirrorDebounce.tryClaim(`${key}:${errorClass}`, Date.now())) return;
  warnSilentFallback(err, ctx);   // level: "warning"
}
```

Call site keys on the per-segment snapshot cache key shape
`${role}:${orgId ?? "__anon__"}` (never a `userId` — it is an in-process dedup
token, never emitted) with a dedicated `errorClass`
`flagsmith:getidentityflags-timeout`.

## Key Insight

- **Debounce is the actual volume bound, not the severity change.** Sentry
  `EventFrequencyCondition` alert rules count events regardless of `level` —
  flipping error→warning alone would NOT have stopped the alert. The
  ≤1-event-per-`(role,orgId,errorClass)`-per-5-min debounce is what fixes the
  flood. Lower severity is secondary (correct classification of a recovered
  path), not the mitigation.
- **Adding the SDK `defaultFlagHandler` would have been worse:** it makes the
  SDK swallow the throw and return empty flags for ALL runtime flags (worse than
  the env-var fallback that mirrors real prd-segment state) AND deletes the
  observability signal entirely (our catch never runs). The app-level
  catch + env fallback is the superior degradation mechanism; tune the report,
  not the degradation.
- **Sibling-helper over signature-parameterization** when only one call site
  needs the new behavior: a warn-level sibling on the shared dedup map is ~8
  lines with zero blast radius vs. adding a `level` arg to every existing
  `mirrorWithDebounce` caller. The shared map is safe because a distinct
  `errorClass` keeps the key spaces disjoint.
- Generalizes [[2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces]]:
  that learning picks debounce for high-cardinality per-user surfaces; this adds
  the warn-level variant for recovered-but-noisy degraded paths keyed on a
  low-cardinality segment bucket rather than a userId.

## Session Errors

1. **Deepen-plan Phase 4.6 threshold gate flagged `observability.ts`** (forwarded
   from session-state.md). The sensitive-path regex matched
   `apps/web-platform/server/observability.ts`, requiring a
   `threshold: none, reason: …` scope-out bullet in the plan's User-Brand Impact
   section. Recovery: added the bullet during planning. Prevention: when a plan
   edits any `apps/web-platform/server/**` file, pre-author the threshold
   scope-out bullet — the gate is deterministic on that prefix.

2. **`git stash list` denied by the `hr-never-git-stash-in-worktrees` hook**
   during work Phase 0.5 preflight (check 4). The hook blocks all `git stash`
   invocations including the read-only `list` subcommand. Recovery: re-ran the
   remaining preflight checks (`git status`, divergence) without the stash
   probe. Prevention: the work-skill preflight stash-check is redundant inside a
   worktree (stashing is forbidden there anyway); the check should be guarded to
   run only outside `.worktrees/`, or use `git stash list` via a path the hook
   permits. Low impact — the deny is loud and the remaining checks cover the
   preflight intent.

3. **`hr-never-git-stash-in-worktrees` hook denied a `git commit` whose MESSAGE
   described the stash incident.** The hook substring-matches the literal
   `git stash` anywhere in the bash command, so a commit-message heredoc that
   merely *names* the stash deny (documenting error #2) tripped it. Recovery:
   reworded the commit message to avoid the literal `git stash` substring
   ("the worktree stash-list preflight deny"). Prevention: when writing a
   commit message / learning that must reference the forbidden command, avoid
   the exact `git stash` token in the bash invocation (paraphrase, or write the
   file with the Edit/Write tool and commit with a terse message). A tighter
   hook matcher (anchor on command position, not free-text substring) would
   remove the friction but risks false-negatives — paraphrasing is the cheap
   path.

## Tags
category: integration-issues
module: observability
