---
title: "fix(kb-chat): resumed conversation shows empty chat -- messages not loaded"
type: fix
date: 2026-04-16
deepened: 2026-04-16
---

# fix(kb-chat): resumed conversation shows empty chat -- messages not loaded

Closes #2425

## Enhancement Summary

**Deepened on:** 2026-04-16
**Sections enhanced:** 4 (Implementation Phases, Test Scenarios, Acceptance Criteria, Root Cause Analysis)
**Research sources:** Codebase analysis, institutional learnings, edge case discovery

### Key Improvements

1. Discovered a **banner premature dismissal bug** that would be introduced by Phase 1: `handleMessageCountChange` in `kb-chat-sidebar.tsx` dismisses the "Continuing from" banner when `messages.length > 0`, which will fire immediately when history loads -- before the user sees the banner
2. Added explicit guidance on `useEffect` dependency arrays and cleanup patterns based on institutional learning `2026-04-16-module-scope-to-async-state-deps-mismatch.md`
3. Added a `setMessages` deduplication guard using message IDs to prevent history/stream overlap (strengthens AC4)
4. Added SSR/hydration consideration for `toLocaleString` -- test must pin locale to avoid flaky assertions across environments

### New Considerations Discovered

- The `handleMessageCountChange` callback comment explicitly documents the assumption that "messages on a resumed thread starts empty" -- fixing the bug invalidates this assumption and creates a cascading banner dismissal bug
- The `connect` callback clears `setSessionConfirmed(false)` on reconnect, which resets `sessionStarted` in chat-surface.tsx via the status effect at line 177 -- this means a reconnect after resume would re-trigger `startSession`, potentially creating a duplicate session. The existing code handles this via `abortActiveSession` on the server side, but the client may briefly show stale messages from the aborted session

## Overview

When resuming a previous KB Chat sidebar conversation, the header shows "Continuing from 4/16/2026" but the chat area is empty. The root cause is a missed history fetch: the sidebar always mounts `ChatSurface` with `conversationId="new"`, and the history-loading effect in `ws-client.ts` has a guard that exits early for `"new"` conversations. When the server responds with `session_resumed`, it sets `realConversationId` but the history fetch is keyed on the prop `conversationId`, not `realConversationId`, so history is never loaded.

Additionally, the "Continuing from" banner date uses `toLocaleDateString()` which omits the time, making same-day conversations ambiguous.

## Root Cause Analysis

### Bug 1: Empty messages on resume

The flow:

1. `kb-chat-sidebar.tsx` mounts `ChatSurface` with `conversationId="new"` (line 146)
2. `chat-surface.tsx` calls `useWebSocket("new")` which initializes `ws-client.ts`
3. The history-fetching `useEffect` in `ws-client.ts` (line 387) checks `if (conversationId === "new") return;` -- this early-return skips the history fetch
4. `chat-surface.tsx` calls `startSession({ resumeByContextPath })` (line 144-149)
5. Server finds existing thread, sends `session_resumed` with the real conversation ID
6. `ws-client.ts` handles `session_resumed` (line 320-328): sets `realConversationId` and `resumedFrom`
7. **No history fetch occurs** because the effect at line 387 only depends on `conversationId` (the prop, which is still `"new"`)

The fix: add a second `useEffect` in `ws-client.ts` that watches `realConversationId`. When `realConversationId` transitions from null to a value AND differs from the prop `conversationId`, fetch history from `/api/conversations/${realConversationId}/messages`.

### Bug 2: Ambiguous date format

In `kb-chat-sidebar.tsx` line 141:

```tsx
Continuing from {new Date(resumedBanner.timestamp).toLocaleDateString()}
```

This produces "4/16/2026" with no time. The fix: use `toLocaleString()` with options that include date and time (e.g., `toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })`) to produce output like "4/16/2026, 2:15 PM".

## Acceptance Criteria

- [x] **AC1:** When resuming a KB Chat sidebar conversation, prior messages are visible in the chat area
- [x] **AC2:** The "Continuing from" banner includes both date and time (e.g., "Continuing from 4/16/2026, 2:15 PM")
- [x] **AC3:** Messages loaded from history display in chronological order (oldest first)
- [x] **AC4:** History messages do not duplicate if a new message arrives from a live stream while history is loading
- [x] **AC5:** The "Send a message to get started" placeholder does NOT appear when history messages are present
- [x] **AC6:** Auto-scroll to the bottom of the chat after history is loaded
- [x] **AC7:** The "Continuing from" banner remains visible after history messages load (not dismissed prematurely by the message count change handler)

## Implementation Phases

### Phase 1: Fix history fetch for resumed sessions

**File:** `apps/web-platform/lib/ws-client.ts`

Add a new `useEffect` that triggers on `realConversationId` changes. When `realConversationId` is set and the `conversationId` prop is `"new"` (sidebar resume path), fetch message history from the API and prepend to `messages` state.

Extract the duplicated message-mapping logic (DB row to `ChatMessage`) into a shared helper function `mapDbMessageToChatMessage` rather than copy-pasting the mapping from the existing history effect. Both effects use the same shape.

Key considerations:

- Guard against race conditions: only prepend if `activeStreamsRef.current.size === 0` (same pattern as the existing history fetch on line 420). If a stream starts DURING the fetch (the `await fetch()` yields), the prepend guard prevents stale history from overwriting live data. The `AbortController` handles component unmount but the `activeStreamsRef` guard handles the mid-fetch stream arrival case.
- Use `AbortController` for cleanup (same pattern as existing effect)
- Return early if `realConversationId` is null or matches the prop `conversationId` (the existing effect already covers non-"new" IDs)

```text
apps/web-platform/lib/ws-client.ts
  - Extract mapDbMessageToChatMessage helper (shared by both history effects)
  - Add useEffect watching [realConversationId, conversationId]
  - Fetch /api/conversations/${realConversationId}/messages
  - Map and prepend to messages state using shared helper
```

#### Research Insights

**Deduplication guard (strengthens AC4):** When prepending history to `messages`, use a Set of existing message IDs to filter out any messages that arrived via stream while the fetch was in-flight:

```typescript
setMessages(prev => {
  const existingIds = new Set(prev.map(m => m.id));
  const unique = mapped.filter(m => !existingIds.has(m.id));
  return [...unique, ...prev];
});
```

This is more robust than the `activeStreamsRef.current.size === 0` guard alone: it handles the window where a stream event arrives and completes (setting `size` back to 0) before the fetch resolves.

**Dependency array audit (from learning `2026-04-16-module-scope-to-async-state-deps-mismatch.md`):** The new `useEffect` reads `realConversationId` (state) and `conversationId` (prop). Both must appear in the dependency array. Since `realConversationId` starts as `null` and transitions to a UUID, the effect naturally fires only once per resume. No additional guard needed beyond the null check.

**Effect cleanup on `conversationId` change:** If `conversationId` changes (unlikely in sidebar but possible in full chat), the existing effect at line 432 resets the connection via `connect()`. The new effect's `AbortController` will abort any in-flight fetch, preventing stale history from landing in a new session's message list.

### Phase 2: Fix banner premature dismissal

**File:** `apps/web-platform/components/chat/kb-chat-sidebar.tsx`

**Critical edge case discovered during deepening:** The `handleMessageCountChange` callback (line 99-111) has an explicit assumption in its comment: "messages on a resumed thread starts empty (the server doesn't replay history) -- so any count > 0 means fresh activity in the current session." Phase 1 invalidates this assumption. Once history loads, `messages.length` will immediately become > 0, triggering `setResumedBanner(null)` and dismissing the banner before the user sees it.

**Fix:** Change the `count > 0` guard to track whether the count increase is from history vs. new user activity. The simplest approach: check if `resumedFrom` is set (meaning we just loaded history) and only dismiss the banner when the count exceeds the historical message count:

```text
apps/web-platform/components/chat/kb-chat-sidebar.tsx
  - Track the initial history count from onThreadResumed's messageCount parameter
  - In handleMessageCountChange, only dismiss banner when count > historicalMessageCount
```

Alternatively, remove the auto-dismiss from `handleMessageCountChange` entirely and rely on a separate "first user message sent" signal. The current approach conflates "messages exist" with "user sent a message."

### Phase 3: Fix date format in resume banner

**File:** `apps/web-platform/components/chat/kb-chat-sidebar.tsx`

Change line 141 from `toLocaleDateString()` to `toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })`.

```text
apps/web-platform/components/chat/kb-chat-sidebar.tsx
  - Update toLocaleDateString() → toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })
```

#### Research Insights

**SSR/hydration safety:** `toLocaleString` output depends on the runtime locale. In SSR (Node.js) vs. client (browser), the locale may differ, causing a hydration mismatch. This is safe here because the banner is client-only (it renders from `resumedBanner` state, which is set by an effect after mount -- never during SSR). However, tests must pin the locale to avoid flaky assertions:

```typescript
// In test: use a fixed locale for deterministic output
const formatted = new Date("2026-04-16T14:15:00Z")
  .toLocaleString("en-US", { dateStyle: "short", timeStyle: "short" });
// -> "4/16/26, 2:15 PM"
```

**Verification note (AC5):** The empty-state placeholder in `chat-surface.tsx` (line 359-365) checks `messages.length === 0`. Phase 1 populates `messages` with history, so the placeholder hides naturally. No code change needed -- covered by test scenarios.

## Test Scenarios

- Given a KB Chat sidebar with an existing conversation for a document, when the sidebar opens and `session_resumed` fires, then prior messages appear in the chat area
- Given a resumed session with 5 historical messages, when the history loads, then messages appear in chronological order (oldest first, newest last)
- Given a resumed session where a live stream event arrives during history fetch, when both complete, then no duplicate messages appear (deduplication by message ID)
- Given a resumed session, when the "Continuing from" banner is visible, then it shows both date and time (e.g., "4/16/2026, 2:15 PM")
- Given a resumed session with loaded history, then the "Send a message to get started" placeholder is NOT visible
- Given a resumed session with loaded history (e.g., 5 messages), then the "Continuing from" banner is still visible (not dismissed by the message count change)
- Given a resumed session with loaded history, when the user sends a NEW message (count goes from 5 to 6), then the "Continuing from" banner is dismissed
- Given a resumed session, when `toLocaleString` is called in tests, the assertion pins the locale to avoid environment-dependent flakiness

## Context

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/lib/ws-client.ts` | Add `useEffect` to fetch history when `realConversationId` is set from resume; extract shared message mapper |
| `apps/web-platform/components/chat/kb-chat-sidebar.tsx` | Fix banner premature dismissal (Phase 2); change `toLocaleDateString()` to include time (Phase 3) |

### Files to add tests

| File | Tests |
|------|-------|
| `apps/web-platform/test/kb-chat-sidebar.test.tsx` | Add test for timestamp format in resume banner |
| `apps/web-platform/test/ws-client-resume-history.test.ts` (new) | Test that history fetch fires on `realConversationId` change for `conversationId="new"` |

### Related files (read-only)

| File | Relevance |
|------|-----------|
| `apps/web-platform/server/ws-handler.ts` | Server-side session resume handling (no changes needed) |
| `apps/web-platform/server/api-messages.ts` | Messages API endpoint (no changes needed) |
| `apps/web-platform/lib/chat-state-machine.ts` | Pure state machine for message rendering (no changes needed) |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- bug fix for existing KB Chat feature with no new user-facing surfaces, no cost changes, no legal implications.

## MVP

This is already minimal. Two code changes (one new effect, one date format tweak) fix both reported bugs.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Modify existing history `useEffect` to also watch `realConversationId` | Single effect | Conflates two trigger paths; harder to reason about cleanup | Rejected -- separate effects are cleaner |
| Have the server replay messages in the `session_resumed` event | No extra HTTP call | Changes WS protocol; large payloads over WS; breaks existing clients | Rejected -- too invasive for a bug fix |
| Use `conversationId` state instead of prop for history fetch | Works with current architecture | Requires significant refactor of `useWebSocket` hook signature | Rejected -- overkill |
