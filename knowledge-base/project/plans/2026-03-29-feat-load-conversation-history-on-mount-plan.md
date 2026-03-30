---
title: "feat: load conversation history on page mount"
type: feat
date: 2026-03-29
---

# feat: load conversation history on page mount

Closes #1291

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 3 (Implementation Steps, Key Details, Test Scenarios)
**Research sources:** Project learnings (Supabase silent errors, WebSocket close code routing, unapplied migration), codebase analysis (activeStreamsRef index tracking, reconnect lifecycle)

### Key Improvements

1. Added AbortController cleanup pattern for fetch cancellation on unmount/re-render
2. Identified critical activeStreamsRef index invalidation bug -- history must load before streaming or indices break
3. Added deduplication strategy for messages that exist in both history and WebSocket stream
4. Fixed dependency array design -- fetch once per conversationId, not per reconnection

## Overview

The chat page (`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`) does not load conversation history when mounted. The `useWebSocket` hook initializes with an empty `messages` state. On page refresh or navigation back to an existing conversation, all messages are lost.

## Problem Statement

When a user navigates to `/dashboard/chat/<conversationId>` for an existing conversation (not `new`), the page renders an empty message list. The server-side API endpoint `GET /api/conversations/:id/messages` exists in `apps/web-platform/server/api-messages.ts` and returns stored messages, but nothing in the client calls it.

## Proposed Solution

Add a `useEffect` in the chat page that fetches historical messages from the REST API on mount, then prepends them into the `messages` state before WebSocket streaming begins.

### Implementation Steps

#### 1. Update the API endpoint to include `leader_id` (`apps/web-platform/server/api-messages.ts`)

The current select is `id, role, content, created_at` -- it omits `leader_id`, which the client needs to render color-coded leader bubbles.

- [x] Add `leader_id` to the `.select()` call: `id, role, content, leader_id, created_at`

#### 2. No chat page changes needed

History loading is encapsulated inside the `useWebSocket` hook (Step 3). The chat page already consumes `messages` from the hook -- historical messages will appear automatically.

#### 3. Add history fetch inside `useWebSocket` hook (`apps/web-platform/lib/ws-client.ts`)

The hook already owns `messages` state and knows the `conversationId`. Fetching history inside the hook keeps state management encapsulated -- no new public API needed.

- [x] Add a `useEffect` with dependency array `[conversationId]` only (NOT `status`) to prevent re-fetching on reconnect
- [x] Guard: skip when `conversationId === "new"`
- [x] Fetch `GET /api/conversations/${conversationId}/messages` with Bearer token from Supabase session
- [x] Map response: `leader_id` to `leaderId`, add `type: "text"`, generate stable `id` from DB `id` field
- [x] Use functional updater to prepend history: `setMessages(prev => [...historyMsgs, ...prev])` -- this preserves any WebSocket messages that arrived during the fetch
- [x] Add AbortController in the useEffect cleanup to cancel in-flight fetches on unmount or conversationId change
- [x] Error handling: `console.error` and continue (do not block the chat UI)

### Research Insights

**Critical: activeStreamsRef index invalidation.**

The `activeStreamsRef` stores message array indices (positions) to track which array slot belongs to each leader's active stream. When history messages are prepended via `setMessages(prev => [...historyMsgs, ...prev])`, all existing indices shift by `historyMsgs.length`, causing `activeStreamsRef` entries to point at wrong messages.

Mitigation: The history fetch runs on mount before any streaming begins (the `useEffect` for `conversationId` fires before the user sends a message). In the normal flow, `activeStreamsRef` is empty when history loads, so no indices are invalidated. However, if a reconnection triggers a `stream_start` before the history response arrives, the indices would be wrong.

Safest approach: check that `activeStreamsRef.current.size === 0` before prepending. If streams are active, skip the prepend (the user is already seeing live messages; history would cause a jarring reorder).

**Fetch cleanup with AbortController.**

Standard React pattern -- the useEffect cleanup function should abort in-flight requests:

```typescript
useEffect(() => {
  if (conversationId === "new") return;
  const controller = new AbortController();

  (async () => {
    try {
      const supabase = createClient();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.access_token) return;

      const res = await fetch(
        `/api/conversations/${conversationId}/messages`,
        {
          headers: { Authorization: `Bearer ${session.access_token}` },
          signal: controller.signal,
        },
      );
      if (!res.ok) return;

      const { messages: history } = await res.json();
      const mapped = history.map((m: { id: string; role: string; content: string; leader_id: string | null }) => ({
        id: m.id,
        role: m.role as "user" | "assistant",
        content: m.content,
        type: "text" as const,
        leaderId: m.leader_id ?? undefined,
      }));

      if (activeStreamsRef.current.size === 0) {
        setMessages(prev => [...mapped, ...prev]);
      }
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      console.error("Failed to load history:", err);
    }
  })();

  return () => controller.abort();
}, [conversationId]);
```

**Dependency array: `[conversationId]` not `[conversationId, status]`.**

Including `status` would re-trigger the fetch on every reconnection (connecting -> connected -> reconnecting -> connected). History only needs to load once per conversation. The `conversationId` value does not change during reconnection, so the effect runs exactly once per conversation navigation.

**Supabase getSession() error handling.**

Per project learning (`2026-03-20-supabase-silent-error-return-values.md`): the Supabase client returns `{ data, error }` without throwing. The `getSession()` call may return a null session if the token is expired. Check `session?.access_token` before proceeding -- if null, skip the fetch silently (the WebSocket auth flow will handle the redirect via close codes).

**Deduplication is not needed in the normal flow.**

Historical messages have DB-generated UUIDs as IDs. WebSocket stream messages use client-generated IDs (`stream-${leaderId}-${Date.now()}`). These ID namespaces never collide. The only scenario where a message could appear twice is if the server sends a `stream_start`/`stream` for a message that is already in the DB history -- but this would only happen if the agent is mid-response during a page refresh, which the `resume_session` flow handles separately.

### Key Details

- **Auth token retrieval:** Use `createClient()` from `@/lib/supabase/client` (already imported in `ws-client.ts`) to get the session access token: `const { data: { session } } = await supabase.auth.getSession()`. Check `session?.access_token` before fetching -- null means expired session (per Supabase silent error learning).
- **Guard for new conversations:** The fetch must NOT run when `conversationId === "new"` -- new conversations have no history
- **Race condition:** Use a functional `setMessages` updater (`prev => [...historyMsgs, ...prev]`) so any WebSocket messages that arrived during the fetch are preserved. Additionally, check `activeStreamsRef.current.size === 0` before prepending to avoid invalidating active stream indices.
- **Error handling:** If the fetch fails (network error, 401, 404), log to console and continue with empty messages -- do not block the chat UI. Catch and ignore `AbortError` from the cleanup controller.
- **Stable message IDs:** Use the database `id` field (UUID) directly as the `ChatMessage.id`. Do not generate synthetic IDs -- the DB IDs are unique and stable across page refreshes.

### Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/server/api-messages.ts` | Add `leader_id` to select |
| `apps/web-platform/lib/ws-client.ts` | Add history fetch `useEffect` inside hook |

## Acceptance Criteria

- [ ] Navigating to `/dashboard/chat/<existing-id>` loads and displays historical messages
- [ ] Messages display with correct role (user/assistant) and leader color coding
- [ ] Page refresh preserves message history
- [ ] New conversations (`/dashboard/chat/new`) do NOT attempt to fetch history
- [ ] WebSocket streaming messages appear after historical messages
- [ ] If history fetch fails, the chat page still works (degrades to current behavior)
- [ ] No duplicate messages appear when history loads and WebSocket messages arrive

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side data loading bugfix.

## Test Scenarios

- Given an existing conversation with 5 messages, when the user navigates to `/dashboard/chat/<id>`, then all 5 messages are displayed in chronological order
- Given an existing conversation with leader-attributed messages, when history loads, then messages show the correct leader name and color border
- Given `conversationId` is `"new"`, when the page mounts, then no fetch to `/api/conversations/new/messages` is made
- Given the API returns a 401 (expired token), when the page mounts, then the chat UI is still usable with WebSocket (no crash)
- Given the user sends a message before history loads, when history arrives, then the user's WebSocket message is not overwritten
- Given the user navigates away mid-fetch (conversationId changes), when the component re-renders, then the in-flight fetch is aborted (no stale data from wrong conversation)
- Given a reconnection occurs after history has loaded, then the history fetch does NOT re-execute (dependency array is `[conversationId]` not `[status]`)
- Given a conversation with 100+ messages, when history loads, then messages appear in ascending chronological order matching the API's `order("created_at", { ascending: true })`

## Context

- The `resume_session` WebSocket message type exists but only re-associates the WebSocket connection with a conversation -- it does not replay message history
- The `Message` type in `apps/web-platform/lib/types.ts` includes `leader_id: DomainLeaderId | null` confirming the DB column exists (added in migration `010_tag_and_route.sql`)
- The Supabase client-side helper at `apps/web-platform/lib/supabase/client.ts` provides `createClient()` for browser-side auth

## References

- Related issue: #1291
- API endpoint: `apps/web-platform/server/api-messages.ts`
- WebSocket hook: `apps/web-platform/lib/ws-client.ts`
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Session resume learning: `knowledge-base/project/learnings/2026-03-27-agent-sdk-session-resume-architecture.md`
