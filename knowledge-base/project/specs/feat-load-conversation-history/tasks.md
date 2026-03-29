# Tasks: Load Conversation History on Mount

Source: `knowledge-base/project/plans/2026-03-29-feat-load-conversation-history-on-mount-plan.md`

## Phase 1: API Fix

- [ ] 1.1 Add `leader_id` to select in `apps/web-platform/server/api-messages.ts`
  - Change `.select("id, role, content, created_at")` to `.select("id, role, content, leader_id, created_at")`

## Phase 2: Core Implementation

- [ ] 2.1 Add `loadHistory` callback to `useWebSocket` hook (`apps/web-platform/lib/ws-client.ts`)
  - Add `loadHistory: (msgs: ChatMessage[]) => void` callback using `useCallback`
  - Export from hook return value alongside existing `messages`, `sendMessage`, etc.

- [ ] 2.2 Add history fetch `useEffect` to chat page (`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`)
  - Guard: skip when `conversationId === "new"`
  - Get auth token via `createClient()` + `getSession()`
  - Fetch `GET /api/conversations/${conversationId}/messages` with Bearer token
  - Map response: `leader_id` to `leaderId`, add `type: "text"`, generate `id`
  - Call `loadHistory(mappedMessages)`
  - Use a `historyLoadedRef` to prevent duplicate fetches
  - Error handling: log and continue (do not block UI)

- [ ] 2.3 Add loading state indicator
  - Track `isLoadingHistory` state
  - Show "Loading messages..." while fetching
  - Show normal empty state or messages after load completes

## Phase 3: Testing

- [ ] 3.1 Verify existing conversation loads history on navigation
- [ ] 3.2 Verify new conversation does not fetch history
- [ ] 3.3 Verify leader colors render correctly on historical messages
- [ ] 3.4 Verify page refresh preserves messages
- [ ] 3.5 Verify WebSocket messages append after historical messages
- [ ] 3.6 Verify failed fetch degrades gracefully
