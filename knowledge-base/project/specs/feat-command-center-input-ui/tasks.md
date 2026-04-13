# Tasks: Command Center Input UI Fix

**Plan:** knowledge-base/project/plans/2026-04-13-fix-command-center-input-ui-plan.md
**Branch:** feat-command-center-input-ui
**PR:** #2133

## Phase 1: Fix Sizing

- [ ] 1.1 Update input element: add `min-h-[44px]` to match button height
- [ ] 1.2 Update container: change `gap-2` → `gap-3`, `items-end` → `items-center`

## Phase 2: Pending Attachments Bridge

- [ ] 2.1 Create `apps/web-platform/lib/pending-attachments.ts` with set/get/clear API

## Phase 3: Command Center Attachment UI

- [ ] 3.1 Add attachment state and validation logic to dashboard page
- [ ] 3.2 Add hidden file input and paperclip button
- [ ] 3.3 Add attachment preview strip
- [ ] 3.4 Add drag/drop and paste handlers
- [ ] 3.5 Update `handleFirstRunSend` to store pending files before navigation
- [ ] 3.6 Update submit button disabled state

## Phase 4: Chat Page Integration

- [ ] 4.1 Extract `uploadWithProgress` to shared utility if not already exported
- [ ] 4.2 Consume pending files after session confirmation on chat/new page
- [ ] 4.3 Upload pending files via presign API and send with initial message

## Phase 5: Tests

- [ ] 5.1 Update command-center.test.tsx with attachment and sizing tests
- [ ] 5.2 Create pending-attachments.test.ts
