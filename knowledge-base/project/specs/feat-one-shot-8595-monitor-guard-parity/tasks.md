# Tasks — feat-one-shot-8595-monitor-guard-parity

Derived from `knowledge-base/project/plans/2026-11-01-fix-monitor-registry-guard-gaps-plan.md`
(issue #8595, epic #10390 PR 3, draft PR #11824).

## Phase 1 — Message change + verification

- [ ] 1.1 RED proof: temporarily append `"nonexistent-monitor-probe"` to
  `NON_INNGEST_MONITORS` in
  `apps/web-platform/test/server/inngest/function-registry-count.test.ts`;
  run `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/server/inngest/function-registry-count.test.ts`; confirm (c3) fails
  naming the probe entry and prescribing removal (AC2). Revert the probe.
- [ ] 1.2 Apply the second-arg message to the (c3) `expect(stale, …)` call in
  the same file, per the plan's Proposed Solution snippet (message must
  interpolate `stale` and prescribe removing the entries from the set).
- [ ] 1.3 GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/server/inngest/function-registry-count.test.ts` exits 0 (AC3).
- [ ] 1.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Phase 2 — Acceptance verification

- [ ] 2.1 AC1 grep: `grep -n 'stale NON_INNGEST_MONITORS'
  apps/web-platform/test/server/inngest/function-registry-count.test.ts`
  returns ≥1 hit containing a removal directive.
- [ ] 2.2 AC4 evidence greps each return ≥1 hit: (c3) test name,
  `GHA schedule cron ↔ monitor crontab parity`,
  `Watchdog dispatch clock parity`; and
  `git grep -c 'type = "interval"' -- apps/web-platform/infra/sentry/cron-monitors.tf`
  returns 0.
- [ ] 2.3 AC5 diff scope: `git diff --name-only origin/main...HEAD` outside
  `knowledge-base/project/` touches only the one test file.
- [ ] 2.4 Update PR #11824 title/body at ship time (`Closes #8595`);
  evidence-of-satisfaction cites the AC4 grep results.
