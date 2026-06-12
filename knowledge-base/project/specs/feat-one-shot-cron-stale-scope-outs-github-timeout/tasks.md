---
lane: single-domain
plan: knowledge-base/project/plans/2026-06-12-fix-cron-stale-scope-outs-github-connect-timeout-plan.md
sentry_issue: 448a4173f90a436382c4396371927796
---

# Tasks — fix: `cron-stale-deferred-scope-outs` GitHub connect-timeout resilience

## Phase 0 — Preconditions

- [ ] 0.1 Open Code-Review Overlap check: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`, then standalone `jq --arg path <p> '.[] | select(.body // "" | contains($path))'` for each of: `github-retry.ts`, `cron-stale-deferred-scope-outs.ts`. Fold-in / acknowledge / defer per match; record None if empty.
- [ ] 0.2 **(P0 — load-bearing)** Confirm octokit's thrown error shape against installed source: `octokit.request` wraps a connect timeout in a `RequestError` (`name:"HttpError"`, `status:500`) with `UND_ERR_CONNECT_TIMEOUT` at `.cause.cause.code` — so top-level `isRetryable` MISSES it. Re-read `node_modules/@octokit/request/dist-src/fetch-wrapper.js` + `@octokit/request-error/dist-src/index.js`. This is why Phase 1 adds a cause-chain classifier, not a plain `isRetryable` reuse.

## Phase 1 — Cause-chain classifier + retry helper (RED then GREEN)

- [ ] 1.1 (RED) Add unit tests to `apps/web-platform/test/github-api-retry.test.ts`: `isRetryableGithubError` (RequestError-wrapped `UND_ERR_CONNECT_TIMEOUT` at depth 2 → true; bare `RequestError{status:403}` → false; self-referential `.cause` cycle → false, no hang) AND `withGithubRetry` (retryable-then-success, non-retryable-immediate-rethrow, exhaust-3-then-rethrow). Use `vi.useFakeTimers()`.
- [ ] 1.2 (GREEN) In `apps/web-platform/server/github-retry.ts`: (a) hoist `MAX_RETRIES = 2` + `BASE_DELAY_MS = 1_000` into this leaf and import them in `github-api.ts` (remove the private copies there); (b) add `export function isRetryableGithubError(err)` (cause-chain walk over `isRetryable`, bounded depth 5); (c) add `export async function withGithubRetry<T>(fn)` (NO `opts` param; retries only when `isRetryableGithubError`; rethrows non-retryable + final). Logger-free. Verify `github-api.ts` still typechecks after the constant swap.
- [ ] 1.3 Verify AC1: `git grep -n "export function withGithubRetry\|export function isRetryableGithubError" apps/web-platform/server/github-retry.ts` == 2; `MAX_RETRIES = 2` literal defined once (in the leaf).
- [ ] 1.4 Do NOT add a `status>=500` retry arm (octokit surfaces genuine 5xx as RequestError too — would over-retry).

## Phase 2 — Wire the sweep through the helper

- [ ] 2.1 Import `withGithubRetry` into `cron-stale-deferred-scope-outs.ts`.
- [ ] 2.2 Wrap `octokit.request("GET /search/issues", …)` in `fetchCandidates` (AC2).
- [ ] 2.3 Wrap `POST …/comments` and `PATCH …/issues/{issue_number}` INSIDE the existing per-issue `try` (AC3); preserve the `err.status === 403 → "issue_write_403"` discriminator (non-retryable → rethrown attempt 1).
- [ ] 2.4 Verify AC7: `git grep -n "UND_ERR_CONNECT_TIMEOUT" apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` == 0 (no duplicated code list).

## Phase 3 — Cron-integration regression tests

(Seed octokit's REAL shape in every retryable case — `Object.assign(new Error("fetch failed"), { name:"HttpError", status:500, cause: Object.assign(new TypeError("fetch failed"), { cause: { code:"UND_ERR_CONNECT_TIMEOUT" } }) })` — NOT a bare `TypeError`.)

- [ ] 3.1 AC4: transient search timeout (RequestError-wrapped once → resolve) → sweep succeeds, 0 `reportSilentFallback`, candidates from 2nd response.
- [ ] 3.2 AC5: comment `RequestError{status:403}` (non-retryable) → single attempt + `op:"issue_write_403"` mirror, sweep continues.
- [ ] 3.3 AC6: search retryable ×3 → `op:"sweep"` mirror + heartbeat ok:false + handler rethrow (helper exhaust mechanics covered in Phase 1 helper tests).
- [ ] 3.4 Dry-run unaffected (existing test still green).

## Phase 4 — Gates

- [ ] 4.1 AC8 typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] 4.2 AC8 tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts test/github-api-retry.test.ts` passes.

## Phase 5 — Follow-ups (file as tracking issues; do NOT fold in)

- [ ] 5.1 (F1) File deferral issue (verify label via `gh label list` first): "Apply withGithubRetry to remaining probe-octokit cron call sites (drift-guard, oauth-probe, installation discovery)", re-eval trigger = next api.github.com connect-timeout Sentry event from those fnIds.
- [ ] 5.2 (F2) File tracking issue for the pre-existing non-idempotent auto-close comment double-fire on Inngest replay (minimal guard: sentinel-comment check before POST). Re-eval trigger = operator report of duplicate auto-close comments OR `comment-and-close` Sentry op spike.

## Post-merge (operator)

- None. Deploys via `web-platform-release.yml` on merge; verified by next daily cron fire (`0 12 * * *`) producing a clean Sentry Crons heartbeat with no recurrence of issue `448a4173…`.
