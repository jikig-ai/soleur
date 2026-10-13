# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-chat-sidebar-test-flakes/knowledge-base/project/plans/2026-04-22-fix-chat-sidebar-test-flakes-parallel-vitest-plan.md
- Status: complete

### Errors

Context7 MCP returned "Monthly quota exceeded" when queried for vitest 3.2 pool/isolate semantics. Deepen pass substituted direct source-code inspection (`node_modules/vitest/package.json` version confirmation + vitest API reference citations from memory) and a full `rg` audit of the test directory. No blockers — all findings are grounded in repo evidence, not Context7.

### Decisions

- Primary fix is a `setup-dom.ts` harness edit, not per-file beforeEach/afterEach additions. Covers all 7 flaky files plus every other `.test.tsx` prophylactically, generalizes to future siblings, and keeps the leak-cleanup visible in one file.
- Capture `originalFetch` at setup-file module load and force-restore in `afterEach`. Deepen-pass audit discovered 4 files use raw `global.fetch = vi.fn(...)` assignment that `vi.unstubAllGlobals()` cannot undo (`kb-layout*.test.tsx` family). This was invisible in the initial plan and is the most likely real leak path to `kb-chat-sidebar*` tests (they share worker threads).
- `isolate: true` deferred to Phase 4 guardrail. Engaged only if setup-harness does not yield 3/3 green, because re-isolation hides rather than fixes the leak and costs ~15-25% component-project runtime.
- Drift-guard is two-block: Block A asserts literal tokens in setup-dom.ts; Block B walks `test/*.test.tsx` and fails if a new file introduces `global.fetch = vi.fn(` without being on the allowlist. Pattern-class guard, not just token-level.
- Exit criterion is statistical: 3 consecutive `vitest run` invocations with 2109 pass / 0 fail, log tails pasted in PR body. One green run is not evidence.
- Closes #2594 (primary) and #2505 (duplicate) in PR body. Post-merge step: comment on #2505 linking the merged PR and #2594 for future searchers.

### Components Invoked

- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash (git status, repro/audit commands, gh issue view, rg, jq, markdownlint-cli2)
- Read (vitest.config.ts, setup-dom.ts, test files, use-kb-layout-state.tsx, existing plan)
- Write (plan file, tasks.md)
- Edit (plan enhancements, tasks.md updates)
- ToolSearch + mcp__plugin_soleur_context7__query-docs (quota exceeded — fallback to direct inspection)
