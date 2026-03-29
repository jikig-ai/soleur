---
title: "feat: load conversation history on page mount"
type: feat
date: 2026-03-29
---

# feat: load conversation history on page mount

Closes #1291

## Overview

The chat page (`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`) does not load conversation history when mounted. The `useWebSocket` hook initializes with an empty `messages` state. On page refresh or navigation back to an existing conversation, all messages are lost.

## Problem Statement

When a user navigates to `/dashboard/chat/<conversationId>` for an existing conversation (not `new`), the page renders an empty message list. The server-side API endpoint `GET /api/conversations/:id/messages` exists in `apps/web-platform/server/api-messages.ts` and returns stored messages, but nothing in the client calls it.

## Proposed Solution

Add a `useEffect` in the chat page that fetches historical messages from the REST API on mount, then prepends them into the `messages` state before WebSocket streaming begins.

### Implementation Steps

#### 1. Update the API endpoint to include `leader_id` (`apps/web-platform/server/api-messages.ts`)

The current select is `id, role, content, created_at` -- it omits `leader_id`, which the client needs to render color-coded leader bubbles.

- [ ] Add `leader_id` to the `.select()` call: `id, role, content, leader_id, created_at`

#### 2. Add history loading to the chat page (`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`)

- [ ] Add a `useEffect` that runs when `conversationId` changes (and is not `"new"`)
- [ ] Fetch `GET /api/conversations/${conversationId}/messages` with the Supabase access token as `Authorization: Bearer` header
- [ ] Map the response `messages` array to `ChatMessage[]` format (mapping `leader_id` to `leaderId`)
- [ ] Set the messages state with `setMessages` (not prepend, since on mount the array is empty)
- [ ] Track a `historyLoaded` boolean ref to avoid duplicate fetches on re-renders

#### 3. Expose `setMessages` or an `initMessages` method from `useWebSocket` (`apps/web-platform/lib/ws-client.ts`)

The `useWebSocket` hook currently does not expose a way to set messages from outside. Two approaches:

**Option A (preferred): Add a `loadHistory` callback to `useWebSocket`.**

- [ ] Add a `loadHistory(msgs: ChatMessage[]) => void` callback that calls `setMessages(msgs)` and is stable via `useCallback`
- [ ] Export it from the hook's return value
- [ ] The chat page calls `loadHistory(mappedMessages)` after fetch completes

**Option B: Fetch inside the hook itself.**

- [ ] Move the fetch logic into the `useWebSocket` hook, triggered by `conversationId` and `status === "connected"`
- [ ] Keeps message state management encapsulated

Option A is preferred because it keeps the hook focused on WebSocket concerns, and the REST fetch is a one-time page-load concern.

#### 4. Show loading state while fetching history

- [ ] While history is loading, show a "Loading messages..." indicator instead of the empty state prompt
- [ ] After history loads (even if empty), show the normal empty state or the messages

### Key Details

- **Auth token retrieval:** Use `createClient()` from `@/lib/supabase/client` (already imported pattern in `ws-client.ts`) to get the session access token: `const { data: { session } } = await supabase.auth.getSession()`
- **Guard for new conversations:** The fetch must NOT run when `conversationId === "new"` -- new conversations have no history
- **Race condition:** If the user sends a message via WebSocket before history loads, the history response must not overwrite WebSocket messages. Use a ref to track whether history has been set, and only set once.
- **Error handling:** If the fetch fails (network error, 401, 404), log to console and continue with empty messages -- do not block the chat UI

### Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/server/api-messages.ts` | Add `leader_id` to select |
| `apps/web-platform/lib/ws-client.ts` | Export `loadHistory` callback |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | Add history fetch `useEffect` + loading state |

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
