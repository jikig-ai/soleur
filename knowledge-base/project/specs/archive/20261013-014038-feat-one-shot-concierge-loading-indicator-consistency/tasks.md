# Tasks — feat-one-shot-concierge-loading-indicator-consistency

Plan: `knowledge-base/project/plans/2026-05-07-fix-concierge-loading-indicator-consistency-plan.md`

## Phase 1 — Test (RED)

1. Update `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` T1:
   - Keep `getByLabelText("Soleur Concierge avatar")` and the `/routing to the right experts/i` prose assertion.
   - Add: `expect(chip.querySelector(".message-bubble-active")).not.toBeNull();`
   - Add: `expect(within(chip).getByText("Working")).toBeInTheDocument();`
   - Run: `bun test apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` → expect T1 to FAIL.

## Phase 2 — Implementation (GREEN)

2. Edit `apps/web-platform/components/chat/chat-surface.tsx` lines 615-625:
   - Replace the inline `isClassifying` chip block with the `MessageBubble` render shown in the plan's Approach A.
   - Pass `role="assistant"`, `content=""`, `leaderId={CC_ROUTER_LEADER_ID}`, `messageState="tool_use"`, `toolLabel="Routing to the right experts…"`, `getDisplayName`, `getIconPath`.
   - Wrap in `<div data-testid="routing-chip" className="flex justify-start">`.
3. Verify imports — `MessageBubble` is already imported at the top of chat-surface.tsx (it's the component the rest of the chat list renders); confirm before saving.
4. Run: `bun test apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` → expect T1 GREEN.
5. Run: `bun test apps/web-platform/test/chat-surface-resume-classifying.test.tsx` → expect green (no change needed).
6. Run: `bun test apps/web-platform/test/chat-page.test.tsx` → expect green (no change needed).

## Phase 3 — Refactor / Verify

7. Run: `bun test apps/web-platform` (full suite) → expect green.
8. Run: `cd apps/web-platform && bunx tsc --noEmit` → expect zero errors.
9. Visual QA — start the dev server (`cd apps/web-platform && bun dev`), open a chat, send any first message, capture before/after screenshots showing the routing chip and the subsequent tool-use bubble side-by-side. Attach to PR.

## Phase 4 — Ship

10. `git add apps/web-platform/components/chat/chat-surface.tsx apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx`
11. Run `skill: soleur:compound` to capture any session learnings.
12. Commit: `fix(chat): unify concierge routing chip visual treatment with tool_use bubble`
13. Open PR with screenshot pair attached. PR body uses `Ref #<one-shot-issue>` (no auto-close).
14. `skill: soleur:ship` → labels, review, merge.
