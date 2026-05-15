---
plan: ../../plans/2026-05-15-fix-kb-chat-sidebar-chat-page-pre-existing-flakes-plan.md
issue: 3818
branch: feat-one-shot-3818
lane: single-domain
---

# Tasks: fix kb-chat-sidebar + chat-page pre-existing flakes (#3818)

## Phase 1 — Reproduction Probe (TIME-BOXED: 4h)

- 1.1 — Run 10x parallel full-suite (`for i in 1..10; do npm run test:ci; done`); capture failures to `/tmp/web-platform-repro.log`
- 1.2 — Pool-pressure probe: `--pool=threads --poolOptions.threads.maxThreads=2`, default threads, and `--pool=forks`
- 1.3 — File-ordering probe: 4 named files + sibling kb-chat-sidebar/chat-surface files
- 1.4 — Recent-diff blame: `git show 05663ed6 -- apps/web-platform/components/chat/` + same for `3834ffd9`; enumerate new module-scope state
- 1.5 — Decision point: write 5-line summary in PR body; choose Phase 2.A (targeted) or Phase 2.B (prophylactic)

## Phase 2.A — Targeted Fix (if Phase 1 reproduced)

- 2.A.1 — Apply fix per Phase 1 finding (pool-level, scope-isolation, mock-stability, or scrub extension)
- 2.A.2 — If `pool: 'forks'` is chosen, document the ~2-3x CI duration tradeoff in `vitest.config.ts` comment

## Phase 2.B — Prophylactic Hardening (if Phase 1 did NOT reproduce)

- 2.B.1 — Extend `scripts/test-all.sh` line 145 with `TEST_TIMING_LOG` + `WEBPLAT_TEST_FAILURES_LOG` capture on Phase 4 invocation
- 2.B.2 — Add `WEBPLAT_TEST_USE_FORKS` escape hatch to `apps/web-platform/vitest.config.ts` (env-gated, default off)
- 2.B.3 — Add 1 new `it.each` row to `apps/web-platform/test/setup-dom-leak-guard.test.ts` pinning `afterAll(...)` + `vi.restoreAllMocks()` proximity
- 2.B.4 — Frame PR body as prophylactic; use `Ref #3818` not `Closes #3818`

## Phase 3 — Verification

- 3.1 — Run AC5: `for i in 1..5; do npm run test:ci || exit 1; done` — observe 5/5 green
- 3.2 — Run AC3 drift-guard: `vitest run test/setup-dom-leak-guard.test.ts`
- 3.3 — If Phase 2.A: confirm all 4 named tests pass in `npm run test:ci`

## Phase 4 — Capture Learning

- 4.1 — Write `knowledge-base/project/learnings/test-failures/<date>-kb-chat-sidebar-chat-page-flake-recurrence.md` (date picked at write-time per Sharp Edges) with Problem / Root Cause / Solution / Key Insight / Prevention / Related sections
- 4.2 — Cross-reference PR #2819, learning `2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md`, this PR

## Phase 5 — Ship

- 5.1 — Run `/soleur:ship` Phase 4 (full test-all.sh) — must be green
- 5.2 — Auto-merge via `gh pr merge --squash --auto` (handled by /soleur:ship Phase 5.4)
