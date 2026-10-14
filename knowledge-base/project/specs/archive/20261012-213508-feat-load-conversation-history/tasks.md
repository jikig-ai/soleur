# Tasks: Load Conversation History on Mount

Source: `knowledge-base/project/plans/2026-03-29-feat-load-conversation-history-on-mount-plan.md`

## Phase 1: API Fix

- [x] 1.1 Add `leader_id` to select in `apps/web-platform/server/api-messages.ts`
  - Change `.select("id, role, content, created_at")` to `.select("id, role, content, leader_id, created_at")`

## Phase 2: Core Implementation

- [x] 2.1 Add history fetch `useEffect` inside `useWebSocket` hook (`apps/web-platform/lib/ws-client.ts`)
  - Dependency array: `[conversationId]` only (NOT `status` -- avoids re-fetch on reconnect)
  - Guard: skip when `conversationId === "new"`
  - Get auth token via `createClient()` + `getSession()`, check `session?.access_token` before fetch
  - Fetch `GET /api/conversations/${conversationId}/messages` with Bearer token
  - Map response: use DB `id` directly, `leader_id` to `leaderId`, add `type: "text"`
  - Check `activeStreamsRef.current.size === 0` before prepending to avoid index invalidation
  - Use functional updater: `setMessages(prev => [...mapped, ...prev])` to preserve WebSocket messages
  - Add AbortController in useEffect cleanup for fetch cancellation
  - Error handling: catch and ignore `AbortError`, `console.error` for other errors

## Phase 3: Testing

- [ ] 3.1 Verify existing conversation loads history on navigation
- [ ] 3.2 Verify new conversation does not fetch history
- [ ] 3.3 Verify leader colors render correctly on historical messages
- [ ] 3.4 Verify page refresh preserves messages
- [ ] 3.5 Verify WebSocket messages append after historical messages
- [ ] 3.6 Verify failed fetch degrades gracefully
- [ ] 3.7 Verify navigating away mid-fetch aborts the request (no stale data)
- [ ] 3.8 Verify reconnection does not re-fetch history
