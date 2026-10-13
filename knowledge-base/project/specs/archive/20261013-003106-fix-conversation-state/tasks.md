# Tasks: Fix Conversation Command Center State and Titles

## Phase 1: Setup

- [x] 1.1 Research current implementation (dashboard page, conversation-row, use-conversations hook)
- [x] 1.2 Identify root causes (title derivation fallback, missing status update UI, junk conversations)
- [x] 1.3 Verify RLS policy allows client-side status updates (confirmed: `for all using (auth.uid() = user_id)`)

## Phase 2: Title Fix

- [ ] 2.1 Update `deriveTitle()` in `apps/web-platform/hooks/use-conversations.ts` with cascading fallback chain
  - [ ] 2.1.1 Handle empty-after-stripping: show raw message text
  - [ ] 2.1.2 Add fallback to first assistant message content
- [ ] 2.2 Add domain_leader-based fallback title in enrichment logic (lines 116-127)
- [ ] 2.3 Write tests for title derivation edge cases

## Phase 3: Clickable Status Badge

- [ ] 3.1 Convert `StatusBadge` to interactive component in `components/inbox/conversation-row.tsx`
  - [ ] 3.1.1 Clickable for `failed` and `waiting_for_user` (dropdown with transitions)
  - [ ] 3.1.2 Non-clickable for `active` (no affordance, agent running)
  - [ ] 3.1.3 Non-clickable for `completed` (terminal state)
- [ ] 3.2 Add dropdown with `useRef` + outside-click (share-popover pattern)
- [ ] 3.3 `e.stopPropagation()` on badge click and dropdown items
- [ ] 3.4 Add `onStatusChange` prop to `ConversationRow`
- [ ] 3.5 Write tests for badge click, dropdown rendering, status transitions

## Phase 4: Status Update Hook

- [ ] 4.1 Add `updateStatus` function to `useConversations` hook
  - [ ] 4.1.1 Optimistic update with captured previous state for rollback
  - [ ] 4.1.2 Supabase update with `{ error }` destructuring
  - [ ] 4.1.3 Error revert and error state
- [ ] 4.2 Update `UseConversationsResult` interface
- [ ] 4.3 Wire `updateStatus` from dashboard page to ConversationRow via `onStatusChange`
- [ ] 4.4 Write tests for optimistic update and error revert

## Phase 5: Deferred Conversation Creation

- [ ] 5.1 Modify `start_session` in `ws-handler.ts` to defer `createConversation()`
  - [ ] 5.1.1 Generate UUID eagerly, store as `pendingConversationId` in session
  - [ ] 5.1.2 Send `session_started { conversationId }` with pending ID
  - [ ] 5.1.3 Do NOT boot agent in `start_session` for directed sessions
- [ ] 5.2 Modify `chat` handler to create conversation on first real message
  - [ ] 5.2.1 Check if content is real (strip @-mentions, check non-empty)
  - [ ] 5.2.2 If real: create conversation, save message, boot agent
  - [ ] 5.2.3 If only @-mentions: send error, do NOT create conversation
- [ ] 5.3 Write tests for deferred creation scenarios

## Phase 6: Integration Testing and Verification

- [ ] 6.1 Verify existing tests pass: `cd apps/web-platform && npx vitest run`
- [ ] 6.2 Playwright verification: command center title rendering
- [ ] 6.3 Playwright verification: badge click → dropdown → status transition
- [ ] 6.4 Playwright verification: new session with real message creates conversation
- [ ] 6.5 Playwright verification: new session with only @-mention does not create conversation
- [ ] 6.6 Run markdownlint on changed .md files
