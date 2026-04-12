# Tasks: Fix Chat Input Alignment

## Phase 1: Core Fix

- [ ] 1.1 Fix vertical alignment in `apps/web-platform/components/chat/chat-input.tsx`
  - Change `items-end` to `items-center` on the flex container (line 389)
- [ ] 1.2 Move hint text into placeholder in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - Update placeholder prop to include "Type @ to switch leader"
  - Remove the desktop-only hint `<span>` from below the input

## Phase 2: Testing

- [ ] 2.1 Verify existing tests pass (`apps/web-platform/test/chat-input.test.tsx`)
- [ ] 2.2 Update tests if any assert on the removed hint text or changed placeholder
- [ ] 2.3 Visual verification via Playwright screenshot (desktop and mobile viewports)
