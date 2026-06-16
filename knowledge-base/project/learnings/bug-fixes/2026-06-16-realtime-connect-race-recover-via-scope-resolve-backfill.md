# Learning: a realtime hook that subscribes before its scope filter resolves drops own-channel INSERTs; recover with a scope-resolve backfill, not a wider guard

## Problem

A freshly-started conversation did not appear in the web-platform **Recent
Conversations** rail until it *completed* — the reported "still doesn't show"
bug (PR #5421, follow-up to #5391). The rail's `useConversations` hook
(`apps/web-platform/hooks/use-conversations.ts`) subscribes to a Supabase
Realtime own-channel as soon as `userId` resolves, but `workspaceId` is set
later inside the same async `fetchConversations` (after an
`/api/workspace/active-repo` round-trip). Because the conversations rail
**portals per-drill** (ADR-047) and mounts fresh on entry to
`/dashboard/chat/*`, this connect-race fires on the dominant path
(`/dashboard` → new conversation):

- An own-channel INSERT arriving while `workspaceId` is still `null` is dropped
  by `shouldDropForScope` (`conv.workspace_id !== null`) — a correct guard, but
  with **no recovery**.
- Pre-`SUBSCRIBED` INSERTs are not replayed by supabase-js; the single
  `if (status === "SUBSCRIBED") fetchConversations()` backfill can run *before*
  the row exists and never re-runs.
- The completion UPDATE handler is `prev.map(...)` — it patches existing rows
  only and **cannot add a missing one**. So the row surfaced only on the next
  full refetch (nav away/back), i.e. "after it completes".

## Solution

Two changes, both on the rail's own hook instance (a cross-instance optimistic
insert was deliberately **deferred** — the rail and dashboard page are separate
`useConversations` instances and the chat surface holds none, so there is no
in-process writer path to the rail):

1. **Transition-gated scope-resolve backfill.** When `workspaceId` transitions
   `null → id` AND an own-channel INSERT was dropped during the unresolved
   window (`pendingScopeRecoveryRef`), refetch **once**. Transition-gated via a
   `prevWorkspaceIdRef` (same shape as the canonical
   `use-kb-layout-state.tsx:232-240` idiom). Seed the ref `null` (not the
   current value the canonical idiom uses) because `workspaceId` always starts
   `null` here — so the `null→id` edge still fires exactly once and no spurious
   mount transition is manufactured.
2. **Observable drop.** The dropped own-channel INSERT is mirrored to Sentry via
   `warnSilentFallback(null, { feature: "conversations-rail", … })`
   (`cq-silent-fallback-must-mirror-to-sentry`), gated on
   `channel === "own" && workspaceId === null` so it fires only in the brief
   connect window, never per-conversation in steady state.

The fix does **not** widen `shouldDropForScope` — every insert path (realtime
INSERT + the recovery backfill via the scoped list query) still routes through
the one guard, preserving the F3 cross-workspace containment invariant (a second
workspace's rail never shows this workspace's conversation).

## Key Insight

When a realtime subscription's scope filter resolves *asynchronously after*
the channel subscribes, the connect-window is a silent drop zone for
own-channel events. The fix is a **deterministic backfill keyed on the
scope-state transition** (independent of the realtime `SUBSCRIBED` callback
timing) — NOT widening the drop guard (which would re-open the cross-scope leak
the guard exists to prevent) and NOT a `map`-only UPDATE handler (which can
patch but never add a row). Recovery belongs on the *insert/backfill* path; the
UPDATE path owns membership-preserving patches only.

This is the membership-completeness companion to
[[2026-06-16-realtime-event-guard-must-equal-fetch-query-scope]] (#5391, which
established guard-equals-fetch-scope parity): #5391 made the guard *correct*;
this makes the *recovery* complete when the guard correctly drops a connect-race
event.

## Session Errors

1. **`git add` exit 128 ("pathspec did not match a file").** The Bash tool's
   CWD persists across calls; after a `cd apps/web-platform` for `tsc`/`vitest`,
   a later `git add apps/web-platform/...` ran from `apps/web-platform` and the
   doubled path didn't exist. **Recovery:** `cd <worktree-root> && git add …` in
   one call. **Prevention:** for git/test commands in a worktree pipeline,
   always prefix `cd <worktree-abs-path> &&` in the same Bash call (already in
   work/SKILL.md guidance — operator slip, not a new rule).
2. **`tsc` TS2322 — invalid `ConversationStatus` literal `"done"` in a test
   fixture.** **Recovery:** changed to `"completed"`. **Prevention:** the
   pinned `./node_modules/.bin/tsc --noEmit` gate caught it pre-commit; keep
   running it before the per-task commit (worked as designed).
3. **`user-impact-reviewer` first spawn misfired** — returned a meta agent-list
   message with 0 tool uses instead of reviewing. **Recovery:** re-ran the same
   `subagent_type` cleanly → CONCUR. **Prevention:** treat a 0-tool-use agent
   reply that echoes the available-agents list as a non-result and re-spawn;
   not deterministically reproducible, so no rule change.
4. **Cross-agent contamination: `architecture-strategist` reported a HIGH
   `if (false && …)` dead-code finding** that was `test-design-reviewer`'s
   transient in-place RED mutant on the same worktree. **Recovery:** ran
   `git diff HEAD` (empty) + re-ran the suite (15/15 green) and dismissed.
   **Prevention:** already documented in `review/SKILL.md` Sharp Edges — verify
   any "uncommitted working-tree / reverted-fix" finding against committed HEAD
   before trusting it. Followed correctly; no new rule.

## Tags
category: bug-fixes
module: apps/web-platform/hooks/use-conversations.ts
