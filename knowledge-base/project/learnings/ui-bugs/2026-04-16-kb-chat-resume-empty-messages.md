---
module: KB Chat
date: 2026-04-16
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Resumed KB Chat sidebar shows 'Continuing from' header but chat area is empty"
  - "'Send a message to get started' placeholder contradicts 'Continuing from' banner"
  - "Banner dismisses immediately when history loads instead of persisting"
  - "Resume banner date lacks time component for same-day disambiguation"
root_cause: async_timing
resolution_type: code_fix
severity: high
tags: [useeffect, react-hooks, prop-vs-state, history-fetch, deduplication, kb-chat]
---

# Learning: useEffect dependency on prop vs state causes missed history fetch on resume

## Problem

When resuming a KB Chat sidebar conversation, the "Continuing from" header appeared
(server metadata loaded) but the chat area was empty. The history-fetching `useEffect`
in `ws-client.ts` guards on `conversationId` (a prop), which stays `"new"` for the
sidebar resume path. When the server responds with `session_resumed`, it sets
`realConversationId` (state) to the actual UUID, but no effect watches that state
transition to trigger the history fetch.

Secondary issue: `handleMessageCountChange` dismissed the banner when `count > 0`,
which fires immediately when history loads -- before the user sees the banner.

## Solution

1. **Added a second `useEffect`** watching `[realConversationId, conversationId]` that
   fetches `/api/conversations/${realConversationId}/messages` when `realConversationId`
   transitions from null to UUID and `conversationId === "new"`.

2. **Extracted `fetchConversationHistory` helper** shared by both effects to eliminate
   ~30 lines of duplication (auth, fetch, mapping, error handling).

3. **Used Set-based deduplication** when prepending history: `existingIds = new Set(prev.map(m => m.id))`
   to handle the race where a stream event arrives during the fetch.

4. **Tracked `historicalCountRef`** from `onThreadResumed` callback. Banner only dismisses
   when `count > historicalCountRef.current` (user sent a new message), not when history loads.

5. **Changed `toLocaleDateString()` to `toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })`**
   for same-day conversation disambiguation.

## Key Insight

When a React hook uses a prop as an ID but the real ID is resolved asynchronously into
state, effects keyed on the prop will never re-fire for the resolved ID. The fix is a
second effect watching the state, with guards to avoid double-fetching when both IDs
are the same. This is a general pattern for "deferred ID resolution" -- any hook that
accepts a placeholder ID and later resolves the real one needs effects on both.

When extracting shared fetch logic, different merge strategies (guard-based vs dedup-based)
should be parameterized in the caller, not duplicated in the helper.

## Tags

category: ui-bugs
module: KB Chat
