---
title: "Tasks — fix stale-deferred-scope-outs cron transient-fault resilience"
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-12-fix-stale-deferred-scope-outs-cron-transient-fault-resilience-plan.md
---

# Tasks

## Phase 0 — Preconditions

- [ ] 0.1 `git grep -n "createProbeOctokit(" apps/web-platform/server` — confirm no caller depends on immediate-throw on 429/5xx.
- [ ] 0.2 Confirm `ctx.attempt` (zero-indexed) + `ctx.maxAttempts` field names against `node_modules/inngest/types.d.ts`.
- [ ] 0.3 Confirm vitest collects `test/**/*.test.ts`; extend existing `test/server/inngest/cron-stale-deferred-scope-outs.test.ts` in place.

## Phase 1 — RED (write failing tests first)

- [ ] 1.1 A1: non-final attempt throw → no `error` heartbeat, rethrows, `reportSilentFallback` called.
- [ ] 1.2 A2: final attempt throw → `error` heartbeat + rethrow.
- [ ] 1.3 A3: no-`attempt` legacy shape → unchanged (error heartbeat on failure).
- [ ] 1.4 B1: transient 429 on `GET /search/issues` then success → single `ok`, no thrown sweep.
- [ ] 1.5 B3: permanent 404 on search → not retried, surfaces on final attempt.
- [ ] 1.6 AC6: `isTransientGitHubStatus` unit assertion ({401,429,5xx,secondary-403}=true; {403-plain,404,422}=false).
- [ ] 1.7 Run vitest → confirm new cases fail.

## Phase 2 — GREEN: Fix A (attempt-gated heartbeat)

- [ ] 2.1 `_cron-shared.ts`: add `attempt?: number; maxAttempts?: number;` to `HandlerArgs` (ONLY change).
- [ ] 2.2 `cron-stale-deferred-scope-outs.ts`: destructure attempt/maxAttempts; compute `isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`; skip the heartbeat POST on non-final failed attempt (still `reportSilentFallback` + rethrow); error heartbeat only on final-attempt failure.

## Phase 3 — GREEN: Fix B (bounded transient retry)

- [ ] 3.1 `probe-octokit.ts`: extract + export `isTransientGitHubStatus(err)`; widen `createProbeOctokit` retry from 401-only to `!isTransientGitHubStatus(err)`, same 3-attempt / 1s,2s budget.
- [ ] 3.2 `cron-stale-deferred-scope-outs.ts` `fetchCandidates`: wrap the `GET /search/issues` request in a bounded retry (2 retries, 1s/2s) using the shared predicate; permanent statuses rethrow immediately; preserve pagination.

## Phase 4 — Verify

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts` (+ probe-octokit test) — green.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [ ] 4.3 `./node_modules/.bin/vitest run test/server/inngest/` — cohort green (HandlerArgs widening fallout check).

## Phase 5 — Post-merge re-verification (operator/ship — automatable)

- [ ] 5.1 Fire dry-run via `plugins/soleur/skills/trigger-cron/scripts/trigger.sh cron/stale-deferred-scope-outs.manual-trigger --data '{"dry_run": true}'`; confirm `ok` heartbeat.
- [ ] 5.2 Confirm Sentry incident 5468023 clears to `ok` (recovery_threshold=1).
