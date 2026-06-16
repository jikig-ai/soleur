---
title: "A new Realtime event subscription's client guard must be scope-equivalent to the fetch query, not a subset"
date: 2026-06-16
category: best-practices
tags: [supabase-realtime, scope-guard, react-hooks, test-mocks, code-review]
modules: [apps/web-platform/hooks/use-conversations.ts]
related_prs: [5391, 5317]
---

# Realtime event guard must equal the fetch-query scope (not a subset)

## Problem

The Recent Conversations rail showed "No conversations yet." while a conversation
was actively streaming (regression after #5317). Root cause: `use-conversations.ts`
learned about conversations only via a mount-time fetch + Realtime **UPDATE** events
— there was no **INSERT** path. Per ADR-047 the rail portals outside the Next.js
swap region, so it stays mounted and never re-runs its mount effect; a conversation
created after mount on an empty list never appeared.

## Solution

Two coordinated hook-only fixes:
1. A scoped Realtime **INSERT** subscription on both channels (own/user_id +
   shared/workspace_id), branching on event, prepending a fill-only de-duped
   placeholder truncated to `limit`.
2. A bounded **`SUBSCRIBED`-status backfill** `fetchConversations()` (own channel
   only) — Realtime delivers INSERTs at-least-once and does NOT replay events
   buffered during the connect window, so one refetch on subscribe closes the
   create-during-connect race. It fires once per subscribe transition (not per
   render); it deliberately fires on the FIRST SUBSCRIBED too (that is what closes
   the initial-load race — do not "optimize" it away).

A shared `shouldDropForScope(conv, {repoUrl, workspaceId, channel, archiveFilter})`
guard and a shared `deriveRailTitle` helper are used by BOTH the INSERT and UPDATE
handlers so they cannot drift.

## Key Insight

**A new Realtime event handler's client-side scope guard must be scope-EQUIVALENT
to the fetch query — filter on every column the list query filters on, not a
subset.** The original INSERT guard checked `repo_url` + `visibility` + `archive`
but omitted `workspace_id`, while the fetch query scopes by `repo_url` AND
`workspace_id`. The own channel's WAL filter is only `user_id`, so an owner with
two workspaces on the SAME repo would see a workspace-B INSERT surface in the
workspace-A rail (then flicker out on the next refetch). RLS isolates cross-TENANT
rows; the client guard is the cross-repo/**workspace** surfacing guard within a
tenant. A guard that is a strict subset of the fetch scope surfaces rows the
refetch would drop. This was a `pr-introduced` gap that passed the unit suite
green and was caught only by two orthogonal review agents (security-sentinel +
user-impact-reviewer) concurring. Mechanical reviewer check: when a PR adds a
Realtime `.on()` handler that maintains a list, diff its guard columns against the
`.eq(...)`/`.is(...)` chain of the list query — they must match.

## Session Errors

1. **`git add <relative path>` failed ("did not match any files")** — the Bash
   tool's CWD reset to the bare-repo root mid-session. Recovery: re-ran with
   `apps/web-platform/`-prefixed paths. Prevention: already covered — always
   `cd <worktree-abs> && <cmd>` in one Bash call; never rely on persisted CWD.
2. **New test file `tsc` errors** — `ChannelMock.on` typed as `(...args: unknown[])`
   rejected the concrete `vi.fn` signature; `state.rows` typed
   `Record<string,unknown>[]` rejected `Conversation` (no index signature).
   Recovery: matched the concrete `on` signature and typed `rows: Conversation[]`.
   Prevention: type mock interface method signatures concretely, not with
   `(...args: unknown[])`. One-off.
3. **Full suite first run: 23 failures across 3 files** (command-center,
   start-fresh-onboarding, update-status) — each rendered the REAL hook with a
   channel mock whose `.on()` returned a subscribe-only stub
   (`vi.fn().mockReturnValue({ subscribe })`). Adding a SECOND `.on()` (INSERT)
   threw `on is not a function`. Recovery: made each channel mock chainable
   (`.on()` returns the channel). Prevention: see route-to-definition below —
   extending a channel's `.on()` chain is the same blast radius as extending a
   `.from()` chain; sweep all real-hook renderers, not name-filtered.

## Prevention / Reviewer takeaway

- When a PR adds a Realtime `.on()` event handler that maintains a client list,
  assert the handler's scope guard filters on the SAME columns as the list query.
- When a PR adds a second `.on()` registration to an existing channel, sweep every
  test that renders the real hook (`git grep -l '<hook>' test/` minus the
  `vi.mock("@/hooks/<hook>")` set) and make each channel mock chainable.
