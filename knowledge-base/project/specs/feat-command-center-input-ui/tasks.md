# Tasks: Command Center Input UI Fix

**Plan:** knowledge-base/project/plans/2026-04-13-fix-command-center-input-ui-plan.md
**Branch:** feat-command-center-input-ui
**PR:** #2133

## Phase 1: Fix Sizing

- [ ] 1.1 Update input element: add `min-h-[44px]` to match button height
- [ ] 1.2 Update container: change `gap-2` to `gap-3`, `items-end` to `items-center`

## Phase 2: Pending Attachments Bridge

- [ ] 2.1 Create `apps/web-platform/lib/pending-attachments.ts` with set/get/clear API and 5-min staleness guard

## Phase 3: Command Center Attachment UI

- [ ] 3.1 Add attachment state and validation logic to dashboard page
- [ ] 3.2 Add hidden file input and paperclip button
- [ ] 3.3 Add attachment preview strip
- [ ] 3.4 Add drag/drop and paste handlers
- [ ] 3.5 Update `handleFirstRunSend` to store pending files and revoke preview URLs before navigation
- [ ] 3.6 Update submit button disabled state
- [ ] 3.7 Add useEffect cleanup to revoke preview URLs on unmount

## Phase 4: Expose conversationId from ws-client

- [ ] 4.1 Capture conversationId from session_started message in ws-client.ts
- [ ] 4.2 Expose realConversationId in useWebSocket return value

## Phase 5: Chat Page Integration (two-step send)

- [ ] 5.1 Extract `uploadWithProgress` to shared utility if not already exported
- [ ] 5.2 After initial text message sent, check for pending files
- [ ] 5.3 Upload pending files via presign API using realConversationId
- [ ] 5.4 Send attachments as follow-up message
- [ ] 5.5 Handle upload failures gracefully (toast, continue without attachments)
- [ ] 5.6 Clear pending files after consumption

## Phase 6: Tests

- [ ] 6.1 Update command-center.test.tsx with sizing and attachment tests
- [ ] 6.2 Create pending-attachments.test.ts with staleness guard tests
