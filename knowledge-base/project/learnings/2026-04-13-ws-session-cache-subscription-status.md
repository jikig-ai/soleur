---
title: Cache user state on WebSocket session to avoid per-message DB queries
date: 2026-04-13
category: performance-issues
tags: [websocket, supabase, caching, hot-path]
module: server/ws-handler.ts
---

# Learning: Cache user state on WebSocket session to avoid per-message DB queries

## Problem

When adding subscription enforcement to the WebSocket handler, the initial implementation queried Supabase on every `chat` and `resume_session` message to check `subscription_status`. This added a DB round-trip (~5-15ms) to the hottest path in the system. At scale, this would create N queries per second where N is the message rate across all users.

## Solution

Cache `subscription_status` on the `ClientSession` object at auth time. The auth handler already queries the `users` table for T&C version — combining the select to include `subscription_status` adds zero additional queries:

```typescript
// At auth: combined query (no extra DB call)
const { data: userRow } = await supabase
  .from("users")
  .select("tc_accepted_version, subscription_status")
  .eq("id", user.id)
  .single();

// Session registration: cache the status
const newSession: ClientSession = {
  ws,
  lastActivity: Date.now(),
  subscriptionStatus: userRow?.subscription_status ?? undefined,
};

// Per-message check: synchronous, zero DB calls
function checkSubscriptionSuspended(userId: string, session: ClientSession): boolean {
  if (session.subscriptionStatus === "unpaid") {
    // close connection
    return true;
  }
  return false;
}
```

## Key Insight

When adding enforcement checks to hot paths (WebSocket message handlers, API middleware), always check if the data is already available in an existing query or session state. The subscription status only changes on Stripe webhook events (seconds/minutes apart), not mid-conversation. Querying it on every message is wasteful. The worst case with caching is a brief window where a newly-suspended user can send a few more messages before reconnecting.

**General pattern:** If data changes on external events (webhooks, admin actions) rather than user actions, cache it at session start and accept eventual consistency.

## Session Errors

1. **ws-deferred-creation.test.ts mock breakage** — Adding the DB query to `checkSubscriptionSuspended` broke existing test mocks that didn't support the `.eq().single()` chain at the right depth. Recovery: Updated mock structure. Prevention: When adding DB queries to code covered by vi.mock chains, verify the mock chain supports the new query pattern before running tests.

## Tags

category: performance-issues
module: server/ws-handler.ts
