# Tasks: Fix Conversation Command Center State and Titles

## Phase 1: Setup

- [x] 1.1 Research current implementation (dashboard page, conversation-row, use-conversations hook)
- [x] 1.2 Identify root causes (title derivation fallback, missing status update UI)
- [x] 1.3 Verify RLS policy allows client-side status updates (confirmed: `for all using (auth.uid() = user_id)`)

## Phase 2: Core Implementation -- Title Fix

- [ ] 2.1 Update `deriveTitle()` in `apps/web-platform/hooks/use-conversations.ts` to handle empty-after-stripping case (show raw message)
- [ ] 2.2 Add fallback to first assistant message content when no user message exists
- [ ] 2.3 Add domain_leader-based fallback title (e.g., "CTO conversation") in enrichment logic
- [ ] 2.4 Write unit tests for title derivation edge cases in `test/command-center.test.tsx`

## Phase 3: Core Implementation -- Status Change

- [ ] 3.1 Add `updateStatus` function to `useConversations` hook with optimistic updates
- [ ] 3.2 Update `UseConversationsResult` interface to include `updateStatus`
- [ ] 3.3 Create action menu component in `components/inbox/conversation-row.tsx` (dropdown with status transitions)
- [ ] 3.4 Wire `updateStatus` from dashboard page through to ConversationRow props
- [ ] 3.5 Handle error case (revert optimistic update, show error)
- [ ] 3.6 Prevent event propagation on action menu click (do not navigate to chat)

## Phase 4: Testing

- [ ] 4.1 Add tests for status change interaction (click menu, select new status, verify call)
- [ ] 4.2 Add tests for optimistic update behavior (immediate UI change)
- [ ] 4.3 Add tests for error revert scenario
- [ ] 4.4 Verify existing tests in `test/command-center.test.tsx` and `test/components/conversation-row.test.tsx` still pass
- [ ] 4.5 Run full test suite: `cd apps/web-platform && npx vitest run`

## Phase 5: Verification

- [ ] 5.1 Manual verification with Playwright: navigate to command center, check title rendering
- [ ] 5.2 Manual verification with Playwright: click status action menu, verify transition
- [ ] 5.3 Run markdownlint on any changed .md files
