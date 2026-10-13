---
title: Tasks — Apply withGithubRetry to remaining probe-octokit cron call sites
issue: 5230
lane: single-domain
plan: knowledge-base/project/plans/2026-06-14-feat-withgithubretry-probe-octokit-cron-call-sites-plan.md
---

# Tasks — #5230 withGithubRetry probe-octokit sweep

## Phase 0 — Preconditions (read-only)
- [ ] 0.1 Confirm `withGithubRetry` / `isRetryableGithubError` signatures (`server/github-retry.ts:77,98`).
- [ ] 0.2 Confirm individual-wrapper precedent (`cron-stale-deferred-scope-outs.ts:236-260`).
- [ ] 0.3 Confirm 404/403 no-retry tests use plain `httpError` (no `.cause`) — `probe-octokit-retry.test.ts:267-282`.

## Phase 1 — Widen createProbeOctokit discovery retry (probe-octokit.ts)
- [ ] 1.1 (RED) Add transient-connect-timeout-cause retry test to `test/server/github/probe-octokit-retry.test.ts` (helper sets `.cause = { code: "UND_ERR_CONNECT_TIMEOUT" }`, status 500; reject once then resolve; assert 2 attempts). Run — expect FAIL.
- [ ] 1.2 Add `import { isRetryableGithubError } from "@/server/github-retry";` to `probe-octokit.ts`.
- [ ] 1.3 Change retry guard to `if (status !== 401 && !isRetryableGithubError(err)) captureAndRethrow(err, i + 1);`.
- [ ] 1.4 Update header comment (lines ~34-40) + `log.warn` message to drop "401-only" wording (now: JWT-replication-401 OR transient-network-cause).
- [ ] 1.5 (GREEN) Re-run AC7 test + the existing 404/403/401 tests — all green.
- [ ] 1.6 Do NOT migrate the loop to `withGithubRetry` (fresh-JWT-per-attempt is load-bearing).

## Phase 2 — Wrap cron-oauth-probe.ts octokit calls (5 sites)
- [ ] 2.1 Add `import { withGithubRetry } from "@/server/github-retry";`.
- [ ] 2.2 Wrap L490 `GET /search/issues` (read).
- [ ] 2.3 Wrap L499 `POST .../comments` — own wrapper (non-idempotent).
- [ ] 2.4 Wrap L510 `POST .../issues` — own wrapper (non-idempotent).
- [ ] 2.5 Wrap L528 `POST .../comments` — own wrapper (non-idempotent).
- [ ] 2.6 Wrap L537 `PATCH .../issues/{n}` (idempotent).

## Phase 3 — Wrap cron-github-app-drift-guard.ts octokit calls (9 sites)
- [ ] 3.1 Add `import { withGithubRetry } from "@/server/github-retry";`.
- [ ] 3.2 Wrap L334 `GET /app` (read) + add orthogonal-retry comment (handler-level github_app_401 retry is status-driven, not thrown-error-driven).
- [ ] 3.3 Wrap L442 `GET /app/installations` (read).
- [ ] 3.4 Wrap L572 `GET /search/issues` (read).
- [ ] 3.5 Wrap L580 `POST .../comments` — own wrapper (non-idempotent).
- [ ] 3.6 Wrap L591 `POST .../issues` — own wrapper (non-idempotent).
- [ ] 3.7 Wrap L603 `GET /search/issues` (read).
- [ ] 3.8 Wrap L609 `POST .../comments` — own wrapper (non-idempotent).
- [ ] 3.9 Wrap L618 `PATCH .../issues/{n}` (idempotent).
- [ ] 3.10 Wrap L635 `POST .../issues` (leak issue) — own wrapper (non-idempotent).

## Phase 4 — Verify
- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (AC8).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts test/server/inngest/cron-oauth-probe.test.ts test/server/inngest/cron-github-app-drift-guard.test.ts test/github-api-retry.test.ts` exits 0 (AC9).
- [ ] 4.3 AC1–AC5 greps: `withGithubRetry(() =>` count == `octokit.request` count == 9 (drift) / 5 (oauth); `isRetryableGithubError` present in probe-octokit.ts; both crons import `withGithubRetry`.
- [ ] 4.4 AC4: no single `withGithubRetry` callback contains two `octokit.request(` calls.
