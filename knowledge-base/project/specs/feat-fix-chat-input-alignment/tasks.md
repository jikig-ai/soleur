# Tasks: fix chat input vertical alignment

## Phase 1: Setup

- [ ] 1.1 Read `apps/web-platform/components/chat/chat-input.tsx` and confirm the alignment issue
- [ ] 1.2 Run existing tests to establish green baseline: `cd apps/web-platform && npx vitest run test/chat-input.test.tsx test/chat-input-attachments.test.tsx`

## Phase 2: Core Implementation

- [ ] 2.1 Add `min-h-[44px]` to the textarea className in `apps/web-platform/components/chat/chat-input.tsx` (line ~425)

## Phase 3: Testing

- [ ] 3.1 Re-run existing tests to verify no regressions: `cd apps/web-platform && npx vitest run test/chat-input.test.tsx test/chat-input-attachments.test.tsx`
- [ ] 3.2 Visual verification: start dev server and confirm alignment in browser at desktop and mobile viewports
- [ ] 3.3 Verify multi-line behavior: type several lines and confirm buttons stay at bottom
