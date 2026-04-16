# Tasks: fix(kb-chat) resumed conversation shows empty chat

Ref: [Plan](../../plans/2026-04-16-fix-kb-chat-resume-empty-messages-plan.md)
Issue: #2425

## Phase 1: Fix history fetch for resumed sessions

- [ ] 1.1 Extract `mapDbMessageToChatMessage` helper in `apps/web-platform/lib/ws-client.ts`
  - [ ] 1.1.1 Create a function that maps `{ id, role, content, leader_id }` to `ChatMessage`
  - [ ] 1.1.2 Refactor existing history `useEffect` (line 407-418) to use the helper
- [ ] 1.2 Add new `useEffect` for `realConversationId` history fetch in `apps/web-platform/lib/ws-client.ts`
  - [ ] 1.2.1 Guard: return early if `realConversationId` is null
  - [ ] 1.2.2 Guard: return early if `realConversationId === conversationId` (existing effect handles this)
  - [ ] 1.2.3 Guard: return early if `conversationId !== "new"` (only sidebar resume path needs this)
  - [ ] 1.2.4 Fetch `/api/conversations/${realConversationId}/messages` with auth header
  - [ ] 1.2.5 Map response with `mapDbMessageToChatMessage`
  - [ ] 1.2.6 Deduplicate by message ID when prepending to messages state
  - [ ] 1.2.7 Use `AbortController` for cleanup on unmount
- [ ] 1.3 Write tests in `apps/web-platform/test/ws-client-resume-history.test.ts`
  - [ ] 1.3.1 Test: history fetch fires when `realConversationId` set with `conversationId="new"`
  - [ ] 1.3.2 Test: history fetch does NOT fire when `conversationId` is a real UUID
  - [ ] 1.3.3 Test: history fetch does NOT fire when `realConversationId` is null
  - [ ] 1.3.4 Test: messages from history appear in chronological order
  - [ ] 1.3.5 Test: duplicate messages from stream are filtered out by ID
  - [ ] 1.3.6 Test: "Send a message to get started" placeholder hides after history loads

## Phase 2: Fix banner premature dismissal

- [ ] 2.1 Update `handleMessageCountChange` in `apps/web-platform/components/chat/kb-chat-sidebar.tsx`
  - [ ] 2.1.1 Track initial history count from `onThreadResumed` messageCount parameter
  - [ ] 2.1.2 Only dismiss banner when message count exceeds historical message count (user sent new message)
- [ ] 2.2 Add test in `apps/web-platform/test/kb-chat-sidebar.test.tsx`
  - [ ] 2.2.1 Test: banner stays visible when message count matches historical count (history loaded)
  - [ ] 2.2.2 Test: banner dismisses when message count exceeds historical count (user sent new message)

## Phase 3: Fix date format in resume banner

- [ ] 3.1 Update `toLocaleDateString()` to `toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })` in `apps/web-platform/components/chat/kb-chat-sidebar.tsx`
- [ ] 3.2 Add test in `apps/web-platform/test/kb-chat-sidebar.test.tsx`
  - [ ] 3.2.1 Test: resumed banner includes time portion (not just date); pin locale for determinism

## Verification

- [ ] 4.1 Run existing test suite to confirm no regressions
- [ ] 4.2 Verify AC1-AC7 pass via test scenarios
