# Tasks: fix chat input vertical alignment

## Phase 1: Setup

- [ ] 1.1 Read `apps/web-platform/components/chat/chat-input.tsx` and confirm the alignment issue at line 389 (`items-end` container) and line 425 (textarea className)
- [ ] 1.2 Run existing tests to establish green baseline: `cd apps/web-platform && npx vitest run test/chat-input.test.tsx test/chat-input-attachments.test.tsx`
- [ ] 1.3 Take Playwright screenshots at 3 breakpoints (1280px, 768px, 375px) of the chat input bar BEFORE the fix for comparison

## Phase 2: Core Implementation

- [ ] 2.1 Add `min-h-[44px]` to the textarea className in `apps/web-platform/components/chat/chat-input.tsx` (line ~425), appending after the existing `disabled:opacity-50` class

## Phase 3: Testing

- [ ] 3.1 Re-run existing tests to verify no regressions: `cd apps/web-platform && npx vitest run test/chat-input.test.tsx test/chat-input-attachments.test.tsx`
- [ ] 3.2 Take Playwright screenshots at the same 3 breakpoints (1280px, 768px, 375px) AFTER the fix
- [ ] 3.3 Compare before/after screenshots to confirm alignment improvement
- [ ] 3.4 Verify multi-line behavior: type several lines in textarea and confirm buttons stay anchored at bottom
- [ ] 3.5 Verify attachment preview strip does not affect input bar alignment (add a file, check layout)
- [ ] 3.6 Verify mobile @ mention button positioning is unchanged after the fix
