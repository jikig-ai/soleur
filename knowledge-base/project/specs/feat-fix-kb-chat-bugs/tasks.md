---
title: "fix: KB Chat — 6 bugs"
branch: feat-fix-kb-chat-bugs
pr: 2422
---

# Tasks: fix KB Chat — 6 bugs

## Phase 1: Backend — System prompt fixes (Bugs #2 and #5)

- [ ] 1.1 Read `apps/web-platform/server/agent-runner.ts` system prompt block (lines 478-507)
- [ ] 1.2 Remove `workspacePath` from system prompt (line 481) — replace with relative path instruction and "Never mention file system paths" directive
- [ ] 1.3 Add `else if (context?.path)` fallback (after line 488) — instruct agent to Read the specific document file
- [ ] 1.4 Write tests for system prompt: verify no `/workspaces/` substring, verify context.path fallback, verify context.content path unchanged

## Phase 2: Frontend — Timeout logic (Bugs #1 and #4)

- [ ] 2.1 Read `apps/web-platform/lib/chat-state-machine.ts`
- [ ] 2.2 Change `tool_use` cases (lines ~100, 119, 137, 155) from `timerAction: { type: "reset" }` to `timerAction: null`
- [ ] 2.3 Increase timeout constant from 30000 to 45000
- [ ] 2.4 Write tests: verify tool_use does not reset timer, verify stream resets timer, verify timeout constant is 45000

## Phase 3: Frontend — Input alignment and cost display (Bugs #3 and #6)

- [ ] 3.1 Check if `knowledge-base/project/plans/2026-04-12-fix-chat-input-alignment-plan.md` fix was already applied
- [ ] 3.2 Read `apps/web-platform/components/chat/chat-input.tsx` textarea classes (line 499)
- [ ] 3.3 Change `py-3` to `py-2.5` and `min-h-[44px]` to `h-[44px]`
- [ ] 3.4 Read `apps/web-platform/components/chat/chat-surface.tsx` cost display blocks (lines 425-439, 479-492)
- [ ] 3.5 Replace `isFull &&` gated cost display with variant-aware cost display visible in both full and sidebar
- [ ] 3.6 Write tests: cost renders in sidebar variant, textarea height class assertion

## Verification

- [ ] 4.1 Run existing tests (`node node_modules/vitest/vitest.mjs run`)
- [ ] 4.2 Start dev server and verify fixes in browser (Playwright or manual)
