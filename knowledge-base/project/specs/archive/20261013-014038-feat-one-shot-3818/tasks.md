---
plan: ../../plans/2026-05-15-fix-kb-chat-sidebar-chat-page-pre-existing-flakes-plan.md
issue: 3818
branch: feat-one-shot-3818
lane: single-domain
---

# Tasks: fix kb-chat-sidebar + chat-page pre-existing flakes (#3818)

## Phase 1 — Reproduction Probe (TIME-BOXED: 4h)

- [x] 1.1 — Run sequential full-suite repro probe (3 runs); capture results. **Result: 3/3 green, zero failures from named 4 files.**
- [x] 1.2 — Pool-pressure probe: `--pool=threads --poolOptions.threads.maxThreads=2` on 4 named files. **Result: 51/51 pass, 3.43s.**
- [~] 1.3 — File-ordering probe: SKIPPED. 1.1 + 1.2 already established green-on-green; further file-ordering exploration would not change the Phase 2.A/2.B decision.
- [~] 1.4 — Recent-diff blame: SKIPPED. 1.1 + 1.2 green confirms no deterministic regression to blame.
- [x] 1.5 — Decision point: **Phase 2.B (prophylactic hardening)** — no repro emerged from 1.1 + 1.2.

## Phase 2.A — Targeted Fix (if Phase 1 reproduced)

- [~] 2.A.* — N/A (Phase 2.B path taken).

## Phase 2.B — Prophylactic Hardening (if Phase 1 did NOT reproduce)

- [~] 2.B.1 — `scripts/test-all.sh` extension: SKIPPED intentionally. Existing `TEST_TIMING_LOG` in `run_suite()` (test-all.sh:109) already records FAIL state per suite. Duplicate log adds an unread file. Documented in learning file.
- [x] 2.B.2 — `WEBPLAT_TEST_USE_FORKS` escape hatch added to `apps/web-platform/vitest.config.ts`. Verified: default mode green, forks mode green.
- [x] 2.B.3 — Drift-guard row added to `apps/web-platform/test/setup-dom-leak-guard.test.ts` pinning `afterAll(...)` + `vi.restoreAllMocks()` proximity (regex within ~200 chars).
- [x] 2.B.4 — PR body framed as prophylactic; use `Ref #3818` not `Closes #3818`.

## Phase 3 — Verification

- [x] 3.1 — AC5: 5/5 post-fix `npm run test:ci` green (400 passed | 7 skipped, 4368 passed | 39 skipped).
- [x] 3.2 — AC3 drift-guard: `vitest run test/setup-dom-leak-guard.test.ts` → 10/10 pass.
- [~] 3.3 — N/A (Phase 2.B path).

## Phase 4 — Capture Learning

- [x] 4.1 — Wrote `knowledge-base/project/learnings/test-failures/2026-05-15-kb-chat-sidebar-chat-page-flake-recurrence.md` (Problem / Root Cause / Solution / Key Insight / Prevention / Related).
- [x] 4.2 — Cross-referenced PR #2819, learning `2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md`, this PR (#3831).

## Phase 5 — Ship

- [ ] 5.1 — Run `/soleur:ship` (handled by parent one-shot pipeline).
- [ ] 5.2 — Auto-merge via `gh pr merge --squash --auto` (handled by /soleur:ship Phase 5.4).
