# Tasks: feat-conversation-history

**Plan:** [2026-04-12-fix-conversation-history-visibility-plan.md](../../plans/2026-04-12-fix-conversation-history-visibility-plan.md)
**Issue:** [#2026](https://github.com/jikig-ai/soleur/issues/2026)

## Phase 1: Implementation

- [ ] 1.1 Delete the foundations early return block (`if (!kbError && visionExists && !allFoundationsComplete)` at line 292)
- [ ] 1.2 Add foundation card grid JSX to the empty inbox state (inline, no component extraction)
- [ ] 1.3 Add foundation card grid JSX to the full inbox state (between header and filter bar)
- [ ] 1.4 Update empty-state heading copy: "No conversations yet" when foundations incomplete, "Your organization is ready" when complete
- [ ] 1.5 Adjust empty-state vertical alignment (`justify-start pt-10`) when foundations are shown

## Phase 2: Testing

- [ ] 2.1 Run existing tests to verify no regressions
- [ ] 2.2 Visual QA: foundations incomplete + conversations exist (Playwright screenshot)
- [ ] 2.3 Visual QA: foundations incomplete + zero conversations (Playwright screenshot)
- [ ] 2.4 Visual QA: all foundations complete + conversations exist (unchanged)
- [ ] 2.5 Visual QA: first-run state (unchanged)
- [ ] 2.6 Mobile viewport check for foundation cards + conversation list stacking
