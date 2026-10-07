# Tasks: fix flaky grandchild-reaped test (#9670)

Plan: knowledge-base/project/plans/2026-10-07-fix-flaky-grandchild-reaped-test-plan.md

## Phase 1: Edit the test (single file)

- [ ] 1.1 Fix local `isAlive` in apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts: ESRCH from kill(0) => dead, EPERM => alive; state parsed after last `)`; Z/X => dead; stat read ENOENT/ESRCH => dead when /proc readable, else alive; record `lastProbe`
- [ ] 1.2 Replace the 3s `Date.now()` loop + final single probe with `vi.waitFor(..., { timeout: 15_000, interval: 25 })`
- [ ] 1.3 Evidence-bearing assertion message (pid, lastProbe, waited ms, loadavg); extend `node:os` import to `{ loadavg, tmpdir }`
- [ ] 1.4 Row timeout 20_000 -> 40_000; refresh describe-block comment

## Phase 2: Verify

- [ ] 2.1 50 iterations of the row under >= 2x nproc busy loops (temporary `{ repeats: 50 }`, removed before commit); record load/count/wall time
- [ ] 2.2 Whole file green once under load
- [ ] 2.3 Mutation: remove product `process.kill(-child.pid, "SIGKILL")` => row RED on assertion (state S) within 40s; revert; server diff empty
- [ ] 2.4 `npx tsc --noEmit` + `npx vitest run test/server/inngest/cron-claude-eval-substrate-exit.test.ts`

## Phase 3: Ship

- [ ] 3.1 PR body `Closes #9670`
- [ ] 3.2 Comment on #9670: corrected premise, measured baseline, fixes, "paste failure message as a count on this issue"
