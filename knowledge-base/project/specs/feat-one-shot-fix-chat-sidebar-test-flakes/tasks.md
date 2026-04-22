# Tasks: fix chat-sidebar test flakes (#2594, #2505)

Derived from `knowledge-base/project/plans/2026-04-22-fix-chat-sidebar-test-flakes-parallel-vitest-plan.md`.

## 1. Reproduce (establish RED baseline)

- [ ] 1.1 `cd apps/web-platform && ./node_modules/.bin/vitest run 2>&1 | tee /tmp/vitest-baseline-1.log`
- [ ] 1.2 Repeat 4 more times, save to `/tmp/vitest-baseline-2.log` … `/tmp/vitest-baseline-5.log`. Tally failing tests per run.
- [ ] 1.3 Confirm serial-green: `./node_modules/.bin/vitest run --no-file-parallelism | tail -20` reports 2108 pass, 0 fail.
- [ ] 1.4 Confirm single-thread-green: `./node_modules/.bin/vitest run --poolOptions.threads.singleThread=true | tail -20` reports 2108 pass, 0 fail. (Distinguishes cross-file-worker leak from timer-leak.)
- [ ] 1.5 Paste the failure-frequency table into the PR draft description (test name → how many of 5 runs it failed).

## 2. Prerequisite audit (before editing setup-dom.ts)

- [ ] 2.1 `rg "beforeAll.*spyOn" apps/web-platform/test/` — identify any spies that live in `beforeAll` and would be broken by `vi.restoreAllMocks()` in `afterEach`.
- [ ] 2.2 If 2.1 has hits: either move to `beforeEach` in that file (per-test spy lifecycle) OR switch setup-dom.ts to `vi.clearAllMocks()` + `vi.unstubAllGlobals()` (narrower — drop call history only, leave spy wiring).
- [ ] 2.3 `rg "vi\\.stubGlobal|global\\.fetch\\s*=" apps/web-platform/test/` — verify stubGlobal usage so we know what the `unstubAllGlobals()` call needs to undo.

## 3. Implement primary fix (Phase 2 of plan)

- [ ] 3.1 Edit `apps/web-platform/test/setup-dom.ts` per plan Phase 2:
  - Add `beforeEach` that clears sessionStorage + localStorage (with `try/catch`).
  - Add `afterEach` ordered as: DOM cleanup → `vi.restoreAllMocks()` → `vi.unstubAllGlobals()` → `vi.unstubAllEnvs()` → `vi.useRealTimers()` → storage clear.
  - Keep the existing `@testing-library/jest-dom/vitest` import and `cleanup()` call.
- [ ] 3.2 `cd apps/web-platform && npx tsc --noEmit` — clean.
- [ ] 3.3 `./node_modules/.bin/vitest run test/setup-dom-leak-guard.test.ts` (after task 5.1 creates it) — passes.

## 4. Verify (Phase 3 of plan — statistical exit gate)

- [ ] 4.1 `./node_modules/.bin/vitest run 2>&1 | tee /tmp/vitest-fix-1.log` → 2109 pass / 0 fail.
- [ ] 4.2 Repeat 2 more times (`vitest-fix-2.log`, `vitest-fix-3.log`). All three MUST be 2109 pass / 0 fail.
- [ ] 4.3 Stress: `./node_modules/.bin/vitest run --poolOptions.threads.maxThreads=8 2>&1 | tail -20` → 2109 pass / 0 fail.
- [ ] 4.4 Regression: `./node_modules/.bin/vitest run --no-file-parallelism 2>&1 | tail -20` → still 2109 pass / 0 fail.
- [ ] 4.5 Paste the 4 log tails (`fix-1`, `fix-2`, `fix-3`, stress) into PR body under `## Evidence`.

## 5. Drift-guard test (Phase 5 of plan)

- [ ] 5.1 Create `apps/web-platform/test/setup-dom-leak-guard.test.ts` per plan Phase 5. Must be `.test.ts` (not `.tsx`) so it lands in the `unit` project.
- [ ] 5.2 Manually delete `sessionStorage.clear()` from setup-dom.ts, rerun the guard — confirm it fails with "retains sessionStorage clear". Restore the line. (Local-only sanity; do not commit the stripped version.)
- [ ] 5.3 Rerun `./node_modules/.bin/vitest run test/setup-dom-leak-guard.test.ts` — green.

## 6. Conditional guardrail (Phase 4 of plan — only if 4.1–4.4 did not hit 3/3 green)

- [ ] 6.1 Edit `apps/web-platform/vitest.config.ts`: add `isolate: true` to the `component` project only (NOT to the `unit` project, NOT workspace-level).
- [ ] 6.2 Repeat tasks 4.1–4.4.
- [ ] 6.3 Measure component-project wall-clock delta (before/after). Document in PR body. Ceiling: +25%.

## 7. Ship

- [ ] 7.1 Compound: `skill: soleur:compound`.
- [ ] 7.2 Commit with `fix:` prefix: `fix: reset sessionStorage, globals, timers, mocks in setup-dom.ts afterEach (#2594, #2505)`.
- [ ] 7.3 PR body MUST include: `Closes #2594`, `Closes #2505`, and the 4 log tails from task 4.5.
- [ ] 7.4 `skill: soleur:ship` to run the review/QA/compound gate.
- [ ] 7.5 After merge: add a comment to #2505 linking to the merged PR and #2594, for searchers who land on the duplicate.
- [ ] 7.6 Within 48h, verify 3 consecutive main-branch CI runs with `apps/web-platform` component tests green (plan AC: post-merge).

## Rollback plan

If, after merge, main-branch CI flakes on the same tests:

1. Revert the `setup-dom.ts` edit via a single `git revert <commit>`.
2. Re-open #2594 with a link to the flaking CI run.
3. Re-run this plan, this time engaging Phase 4 (`isolate: true`) from the start.

Do NOT keep the setup-dom.ts changes and layer on additional per-file edits — that produces the layered-patch anti-pattern the plan specifically rejects.
