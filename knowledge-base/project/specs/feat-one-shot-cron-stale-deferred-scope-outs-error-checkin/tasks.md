---
title: "Tasks — fix stale-deferred-scope-outs cron transient-fault resilience"
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-12-fix-stale-deferred-scope-outs-cron-transient-fault-resilience-plan.md
---

# Tasks

> Single-fix design (deepen-plan revision 2026-06-12): gate the Sentry `error`
> heartbeat on the final Inngest attempt. The dropped "Fix B" (in-attempt retry /
> widened createProbeOctokit) is out of scope — see plan §"Alternative Considered".

## Phase 0 — Preconditions

- [x] 0.1 Verify Inngest delivers `attempt`/`maxAttempts` to the function ctx AND re-invokes with an incremented `attempt` when the sweep throws inside `step.run`. (Load-bearing: no in-repo handler reads `attempt` today; field is typed on BaseContext but unproven-in-repo.) Record finding.
- [x] 0.2 Verify Inngest's worst-case between-attempt retry delay `D` for a `retries: 1` function; confirm `D + final-attempt-latency < 30 min` (checkin_margin_minutes). Record the number.
- [x] 0.3 Confirm vitest collects `test/**/*.test.ts`; extend existing `test/server/inngest/cron-stale-deferred-scope-outs.test.ts` in place.

## Phase 1 — RED (write failing tests first)

- [x] 1.1 Add partial `_cron-shared` module mock spying on `postSentryHeartbeat` (use `importActual` spread to preserve siblings). Assert on the `ok` arg, NOT a fetch spy / makeStep().calls.
- [x] 1.2 A1: non-final attempt throw (`attempt:0,maxAttempts:2`) → `postSentryHeartbeat` NOT called, `.rejects.toThrow(/sweep failed/)`, `reportSilentFallback` called.
- [x] 1.3 A2: final attempt throw (`attempt:1,maxAttempts:2`) → heartbeat called with `{ ok: false }` + rethrow.
- [x] 1.4 A3: no-`attempt` legacy shape → error heartbeat (`ok:false`) on failure (backward-compat).
- [x] 1.5 A4: success on non-final attempt (`attempt:0,maxAttempts:2`) → heartbeat `{ ok: true }` (gating did not suppress a successful non-final check-in).
- [x] 1.6 A5: success on recovered attempt (`attempt:1,maxAttempts:2`) → `ok:true` + `logger.warn({ recovered_after_attempts: 1 })`.
- [x] 1.7 Run vitest → confirm new cases fail.

## Phase 2 — GREEN

- [x] 2.1 `_cron-shared.ts`: add `attempt?: number; maxAttempts?: number;` to `HandlerArgs` (ONLY change).
- [x] 2.2 `cron-stale-deferred-scope-outs.ts`: destructure attempt/maxAttempts; `isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`; success → `ok` (+ `recovered_after_attempts` warn when attempt>0); non-final failure → skip heartbeat POST + reportSilentFallback + rethrow; final failure → error heartbeat + rethrow.

## Phase 3 — Verify

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts` — green.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] 3.3 `./node_modules/.bin/vitest run test/server/inngest/` — cohort green (HandlerArgs widening fallout check).

## Phase 4 — Post-merge re-verification (operator/ship — automatable)

- [ ] 4.1 Fire dry-run via `plugins/soleur/skills/trigger-cron/scripts/trigger.sh cron/stale-deferred-scope-outs.manual-trigger --data '{"dry_run": true}'`; confirm `ok` heartbeat.
- [ ] 4.2 Confirm Sentry incident 5468023 clears to `ok` (recovery_threshold=1).
