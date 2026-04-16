---
title: "fix: restore cost estimate on KB chat conversation resume"
type: fix
date: 2026-04-16
---

# fix(kb-chat): cost estimate not restored on conversation resume

Closes #2436

## Problem

When resuming a KB chat conversation (reopening the sidebar on a document with prior
messages), messages load correctly but the cumulative cost estimate is missing. The cost
display shows nothing despite the conversation having prior usage data persisted in the
database.

### Root Cause

There are two resume paths, both with the same gap:

1. **Sidebar resume (`start_session` with `resumeByContextPath`)** -- The server queries
   `conversations` with `.select("id, last_active, context_path")` and sends back
   `session_resumed`. Cost columns (`total_cost_usd`, `input_tokens`, `output_tokens`)
   are not selected or included in the response.

2. **Direct resume (`resume_session`)** -- The server queries `conversations` with
   `.select("id, status")` and sends back `session_started`. Cost columns are not
   selected or included.

3. **Client history fetch (`/api/conversations/:id/messages`)** -- The `api-messages.ts`
   handler queries the `conversations` table for ownership check but only selects `id`.
   The response is `{ messages }` with no cost data.

4. **Client `usageData` state** -- Initialized to `null` in `connect()` (line 173 of
   `ws-client.ts`) and never seeded from historical data. The `usage_update` handler
   accumulates deltas from the current WS session only.

The database already stores cumulative cost data via the `increment_conversation_cost`
RPC (migration 017). The data exists; it is just never returned to the client on resume.

## Approach

The simplest fix is to include cost data in the `/api/conversations/:id/messages`
response. This endpoint is already called by `fetchConversationHistory` on both resume
paths (the mount-time effect and the `realConversationId` effect). Adding cost data to
this response means the client can seed `usageData` from the same fetch that loads
messages -- no new API calls, no WS protocol changes needed.

**Why not the WS protocol?** Adding cost fields to `session_resumed` or `session_started`
would require:

- WS type changes (`WSMessage` union in `types.ts`)
- Server-side query changes in two separate handler cases
- Client-side handling in two separate `case` blocks

The API approach touches fewer files, uses the existing fetch path, and avoids coupling
cost restoration to the WS handshake timing.

## Implementation Phases

### Phase 1: Server -- Include cost data in messages API response

**File:** `apps/web-platform/server/api-messages.ts`

1. Expand the conversation ownership query to also select `total_cost_usd`,
   `input_tokens`, `output_tokens` from the `conversations` table
2. Include these fields in the JSON response alongside `messages`:

```text
{
  messages: [...],
  totalCostUsd: number,
  inputTokens: number,
  outputTokens: number
}
```

### Phase 2: Client -- Seed usageData from history fetch

**File:** `apps/web-platform/lib/ws-client.ts`

1. Update `fetchConversationHistory` return type to include cost data alongside messages
2. In both resume effects (mount-time and `realConversationId`), seed `setUsageData` from
   the fetched cost data when it is present and `usageData` is currently `null`
3. Guard: only seed if current `usageData` is `null` to avoid overwriting accumulation
   from an in-flight `usage_update` that arrived before the fetch resolved

### Phase 3: Tests

**File:** `apps/web-platform/test/api-messages.test.ts` (new or extend existing)

1. Test that the `/api/conversations/:id/messages` response includes `totalCostUsd`,
   `inputTokens`, `outputTokens` fields from the conversation row

**File:** `apps/web-platform/test/ws-usage-update.test.ts` (extend existing)

1. Test that `usageData` is seeded from historical cost data on resume (mock fetch
   returning cost fields, verify `setUsageData` called with historical values)
2. Test race condition: if `usage_update` WS event arrives before the history fetch
   resolves, the fetch result does NOT overwrite the accumulated value (the `null`
   guard on `usageData` prevents stale historical data from clobbering fresh
   accumulations)

**File:** `apps/web-platform/test/chat-page-resume.test.tsx` (extend existing)

1. Test that resumed conversation displays cost estimate from historical data

Note: `fetchConversationHistory` is a private function inside `ws-client.ts` (not
exported). Tests must either mock the fetch API response at the network layer or test
behavior indirectly through component rendering with mock `useWebSocket` return values.

## Acceptance Criteria

- [ ] Resumed KB chat sidebar shows cost estimate from prior conversation turns
- [ ] Cost estimate continues accumulating correctly after new messages in a resumed session
- [ ] Cost display shows `$0.0000` format consistent with non-resumed sessions
- [ ] No regression: new conversations still start with no cost display until first usage_update
- [ ] Both resume paths work: sidebar resume (resumeByContextPath) and direct resume (resume_session)

## Test Scenarios

- Given a conversation with prior cost data, when the user resumes via KB sidebar, then the cost estimate displays the historical cumulative cost
- Given a resumed conversation showing historical cost, when the user sends a new message and receives a response, then the cost accumulates on top of the historical value
- Given a new conversation (no history), when the first usage_update arrives, then cost displays from zero (no regression)
- Given a conversation with zero cost (no agent responses yet), when resumed, then no cost display appears (matches current behavior for zero-cost state)
- Given a resumed conversation where a `usage_update` WS event arrives before the history fetch resolves, when the fetch completes, then the fetched historical cost does NOT overwrite the already-accumulated value (null guard prevents stale data)

## MVP

- Restore cost on resume via the messages API response
- Seed client `usageData` state from the fetched data

## Non-Goals

- Changing the WS protocol (`session_resumed`/`session_started` message types)
- Real-time cost synchronization across tabs
- Cost breakdown by leader/turn

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- bug fix restoring existing data flow.
