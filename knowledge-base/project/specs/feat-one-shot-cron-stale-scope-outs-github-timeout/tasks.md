---
lane: single-domain
plan: knowledge-base/project/plans/2026-06-12-fix-cron-stale-scope-outs-github-connect-timeout-plan.md
sentry_issue: 448a4173f90a436382c4396371927796
---

# Tasks — fix: `cron-stale-deferred-scope-outs` GitHub connect-timeout resilience

## Phase 0 — Preconditions

- [ ] 0.1 Open Code-Review Overlap check: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`, then standalone `jq --arg path <p> '.[] | select(.body // "" | contains($path))'` for each of: `github-retry.ts`, `cron-stale-deferred-scope-outs.ts`. Fold-in / acknowledge / defer per match; record None if empty.
- [ ] 0.2 Confirm `isRetryable` in `apps/web-platform/server/github-retry.ts` covers `UND_ERR_CONNECT_TIMEOUT` + `TypeError: fetch failed` (it does — Phase 0 re-read).

## Phase 1 — Shared retry helper (RED then GREEN)

- [ ] 1.1 (RED) Add `withGithubRetry` unit tests to `apps/web-platform/test/github-api-retry.test.ts`: retryable-then-success, non-retryable-immediate-rethrow, exhaust-3-then-rethrow, backoff-delay count (use `vi.useFakeTimers()`).
- [ ] 1.2 (GREEN) Append `export async function withGithubRetry<T>(fn, opts?)` to `apps/web-platform/server/github-retry.ts` (MAX_RETRIES=2, BASE_DELAY 1_000 → 1s/2s; retries only when `isRetryable(err)`; rethrows non-retryable + final). Logger-free (preserve dependency-free leaf).
- [ ] 1.3 Verify AC1: `git grep -n "export function withGithubRetry" apps/web-platform/server/github-retry.ts` == 1.

## Phase 2 — Wire the sweep through the helper

- [ ] 2.1 Import `withGithubRetry` into `cron-stale-deferred-scope-outs.ts`.
- [ ] 2.2 Wrap `octokit.request("GET /search/issues", …)` in `fetchCandidates` (AC2).
- [ ] 2.3 Wrap `POST …/comments` and `PATCH …/issues/{issue_number}` INSIDE the existing per-issue `try` (AC3); preserve the `err.status === 403 → "issue_write_403"` discriminator (non-retryable → rethrown attempt 1).
- [ ] 2.4 Verify AC7: `git grep -n "UND_ERR_CONNECT_TIMEOUT" apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` == 0 (no duplicated code list).

## Phase 3 — Regression + edge tests

- [ ] 3.1 AC4: transient search timeout (`TypeError: fetch failed` once → resolve) → sweep succeeds, 0 `reportSilentFallback`; add `code: UND_ERR_CONNECT_TIMEOUT` variant.
- [ ] 3.2 AC5: comment/close `{ status: 403 }` → single attempt + `op: "issue_write_403"` mirror, sweep continues.
- [ ] 3.3 AC6: search retryable on all 3 attempts → exhaust + rethrow → `op: "sweep"` mirror + heartbeat ok:false + handler rethrow.
- [ ] 3.4 Dry-run unaffected (existing test still green).

## Phase 4 — Gates

- [ ] 4.1 AC8 typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] 4.2 AC8 tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts test/github-api-retry.test.ts` passes.

## Phase 5 — Follow-up

- [ ] 5.1 File deferral issue (verify label exists via `gh label list` first): "Apply withGithubRetry to remaining probe-octokit cron call sites (drift-guard, oauth-probe, installation discovery)", re-eval trigger = next api.github.com connect-timeout Sentry event from those fnIds.

## Post-merge (operator)

- None. Deploys via `web-platform-release.yml` on merge; verified by next daily cron fire (`0 12 * * *`) producing a clean Sentry Crons heartbeat with no recurrence of issue `448a4173…`.
