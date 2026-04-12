# Tasks: feat-conversation-history

**Plan:** [2026-04-12-fix-conversation-history-visibility-plan.md](../../plans/2026-04-12-fix-conversation-history-visibility-plan.md)
**Issue:** [#2026](https://github.com/jikig-ai/soleur/issues/2026)

## Phase 1: Implementation

- [ ] 1.1 Extract `FoundationsBar` inline component from existing foundation cards JSX in `page.tsx`
- [ ] 1.2 Remove the foundations early return block (`if (!kbError && visionExists && !allFoundationsComplete)` at line 292)
- [ ] 1.3 Add `FoundationsBar` to the empty inbox state (foundations incomplete + zero conversations)
- [ ] 1.4 Add `FoundationsBar` to the full inbox state (foundations incomplete + conversations exist)
- [ ] 1.5 Update empty-state heading copy: "No conversations yet" when foundations incomplete, "Your organization is ready" when complete

## Phase 2: Testing

- [ ] 2.1 Run existing tests to verify no regressions
- [ ] 2.2 Visual QA: foundations incomplete + conversations exist (Playwright screenshot)
- [ ] 2.3 Visual QA: foundations incomplete + zero conversations (Playwright screenshot)
- [ ] 2.4 Visual QA: all foundations complete + conversations exist (unchanged)
- [ ] 2.5 Visual QA: first-run state (unchanged)
- [ ] 2.6 Mobile viewport check for foundation cards + conversation list stacking
