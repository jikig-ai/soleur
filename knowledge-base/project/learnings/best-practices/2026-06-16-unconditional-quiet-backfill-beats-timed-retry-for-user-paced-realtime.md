---
title: "For a read-freshness gap on a user-paced realtime event, make the existing backfill unconditional — don't add a timed retry"
date: 2026-06-16
category: best-practices
module: apps/web-platform/hooks/use-conversations
tags: [realtime, supabase, react-hooks, read-freshness, falsification-gate, scope-isolation]
pr: 5436
---

# Learning: unconditional + quiet backfill beats a timed retry for a user-paced realtime event

## Problem

The Recent Conversations rail did not reliably show a freshly-started conversation until
it completed (reported twice — #5421 was the first attempt). The rail's `useConversations`
hook portals per-drill (ADR-047) and mounts fresh, so its realtime own-channel can subscribe
while `workspaceId` is still `null`; an own-channel INSERT in that window is dropped by
`shouldDropForScope`, and the conversation row is created **lazily server-side on the first
WS message** (user-paced), which can land before or after the existing backfills.

#5421's fix added a scope-resolve backfill but **gated it on a recorded drop**
(`pendingScopeRecoveryRef`). That missed the no-drop orderings: a row created after the
connect window, or an INSERT buffered pre-`SUBSCRIBED` (supabase-js never replays those, so
no drop is recorded → the ref never arms → the refetch never fires).

## Solution

Two competing fixes were on the table. The v1 plan proposed a **bounded `setTimeout` retry**
that polls until the row appears. Two deepen-plan reviewers (code-simplicity + architecture)
independently flagged it as "a clock racing a user-paced event."

The shipped fix is strictly simpler: **drop the `pendingScopeRecoveryRef` gate so the
scope-resolve backfill fires UNCONDITIONALLY, exactly once, on the `workspaceId` `null→id`
transition** — regardless of whether a drop was recorded. Net-negative LOC (deletes the ref,
its arming branch, and a Sentry mirror). It is *more* deterministic than a timer because it
does not race the user; it reconciles the moment scope resolves.

The refetch is also made **quiet** (`{ background: true }` skips `setLoading(true)`/`setError(null)`)
so a background reconcile with rows present cannot blank/flash the rail.

## Key Insight

**Before writing any timer/retry for a realtime read-freshness gap, run a falsification gate:
exhibit one concrete event ordering that survives "unconditional backfill + the existing
SUBSCRIBED fetch + the steady-state INSERT reducer" and still drops the row. If you cannot,
no timer ships.** For this hook the three orderings all recover:
- scope-resolves-before-subscribe → `SUBSCRIBED` fetch catches the committed row;
- subscribe-before-scope-resolves → the unconditional `null→id` refetch catches it;
- row created lazily after both → the steady-state own-channel INSERT reducer adds it.

A timer is dead weight (plus cleanup/leak risk on a remounting component, plus a
bound-exhaustion Sentry slug) unless a surviving drop ordering actually exists. The
generalizable move: **widen an existing deterministic recovery to be unconditional rather than
bolting on a clock to chase a user-paced event.**

Corollary (scope isolation): the unconditional backfill is safe only because it routes through
the *same scoped* `fetchConversations` (`.eq(repo_url).eq(workspace_id)`) and only fires after
`workspaceId !== null` — it can never run a `repo_url`-only-scoped query. The
guard-equals-fetch-scope invariant ([[2026-06-16-realtime-event-guard-must-equal-fetch-query-scope]])
is what keeps "fire more often" from becoming a cross-tenant leak.

Corollary (don't over-quiet): the quiet path skips only the *top* `setLoading`/`setError`
toggle. Its interior `setConversations([])` (genuine repo-disconnect) and `setError` (genuine
failure) MUST still fire even under `background` — gating those on `!background` would
re-introduce a stale-rail-after-disconnect bug. (architecture-strategist suggested gating them;
data-integrity-guardian + code-quality-analyst independently confirmed firing them is correct —
the cross-reconcile triad caught the false-positive.)

## Session Errors

All process-level frictions this session; all one-off or already-enforced (no new rule warranted):

1. **Foreground `sleep 90` chain blocked by the harness.** Recovery: awaited the
   backgrounded test-all run's completion notification. **Prevention:** never chain foreground
   `sleep` to poll a backgrounded Bash task — it auto-notifies on exit (already harness-enforced).
2. **Bash CWD drift after parallel agent / subskill boundaries** — a repo-relative `grep`
   failed "No such file or directory". Recovery: re-ran with `cd <abs-worktree-path> &&`.
   **Prevention:** always prefix repo-relative Bash with an absolute `cd` inside a pipeline; the
   Bash tool's CWD can drift across agent spawns and child-skill invocations (already documented
   in work/review skills — apply it).
3. **Monitor tool called with `shellId` (wrong schema).** Recovery: dropped it — the backgrounded
   task already auto-notifies. **Prevention:** don't reach for Monitor on a backgrounded Bash task
   that re-invokes you on completion.
4. **`gh issue create` denied for missing `--milestone`.** Recovery: re-ran with
   `--milestone "Post-MVP / Later"`. **Prevention:** always pass `--milestone` on `gh issue
   create` (already hook-enforced — the gate caught it).

## Tags
category: best-practices
module: apps/web-platform/hooks/use-conversations
