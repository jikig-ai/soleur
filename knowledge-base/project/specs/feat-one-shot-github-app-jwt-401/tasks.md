---
feature: feat-one-shot-github-app-jwt-401
lane: single-domain
plan: knowledge-base/project/plans/2026-05-28-fix-github-app-jwt-401-exp-margin-retry-backoff-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — fix: GitHub App installation-token 401s (Sentry 122537945)

Runner: **vitest** (bun blocked for web-platform via `bunfig.toml`).
Invocation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-token-hardening.test.ts`

## Phase 1 — RED: extend tests

- 1.1 Add exp-margin test to `apps/web-platform/test/github-app-token-hardening.test.ts`:
  mint a token, decode the Bearer JWT from `mockFetch.mock.calls[0][1].headers.Authorization`
  (`Buffer.from(seg, "base64url")`), assert `exp - now <= 540` and `iat <= now`
  (captured under fake timers).
- 1.2 Update existing `toHaveBeenCalledTimes(2)` assertions (`:167`, `:206`) to `3`;
  the "two consecutive 401s" test becomes "three consecutive 401s" (queue 3 `mock401()`,
  advance timers 1s then 2s).
- 1.3 Update "401 then 500" test: 401 → 401 → 500; assert 3 calls, `rejects.toThrow(/500/)`,
  `reportSilentFallback` called.
- 1.4 Add backoff-success tests: 401→200 (2 calls, 1s); 401→401→200 (3 calls, 1s+2s).
- 1.5 Keep "does NOT retry on 403" (1 call) + AC2/AC3/AC4 tests; reconcile any call counts.
- 1.6 Run vitest — confirm RED (new + updated tests fail against current code).

## Phase 2 — GREEN: reduce JWT exp margin

- 2.1 `apps/web-platform/server/github-app.ts` `createAppJwt` (`:122-126`): change
  `exp: now + 10 * 60` → `exp: now + 9 * 60` (540s). Keep `iat: now - 60`. Add comment
  citing the 600s ceiling + octokit `now+570` precedent + #122537945.

## Phase 3 — GREEN: widen mint retry to canonical exponential backoff

- 3.1 Add constants matching `github-api.ts:21-22` naming/values:
  `INSTALL_TOKEN_MAX_RETRIES = 2` (3 total attempts), `INSTALL_TOKEN_BASE_DELAY_MS = 1_000`.
- 3.2 Replace the single-retry block (`github-app.ts:487-496`) with the bounded loop
  (mirror `github-api.ts:61-93` shape, 401-only predicate; `attempt` from 0; delay
  `INSTALL_TOKEN_BASE_DELAY_MS * 2 ** attempt`). Preserve: 401-only retry, fresh JWT per
  attempt (`mintAndExchange()`), body-drain (`response.text().catch(()=>{})`) before delay,
  `log.warn` with `attempt + 1`. Leave the post-loop `if (!response.ok)` /
  `reportSilentFallback` / throw block (`:498-518`) unchanged.

## Phase 4 — Verify

- 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-token-hardening.test.ts` — all green.
- 4.2 `cd apps/web-platform && npx tsc --noEmit` — clean.
- 4.3 `git diff --name-only` excludes `server/github/probe-octokit.ts` (AC6).

## Phase 5 — Ship + post-deploy verification

- 5.1 PR body: reference Sentry issue 122537945; `Closes #<N>` if a GitHub issue tracks it.
- 5.2 Post-deploy: query Sentry events for issue 122537945 over a 24-72h window via the
  `discoverability_test` command (uses `SENTRY_IAC_AUTH_TOKEN`; SENTRY_API_TOKEN /
  SENTRY_AUTH_TOKEN lack issue-read scope). Verdict: new events trend to 0.

## Invariants (do NOT regress)

- Do NOT edit `server/github/probe-octokit.ts` — separate JWT path, already safe (`exp = now + 570`).
- Retry is 401-only; non-401 breaks the loop immediately.
- Fresh JWT per attempt; body-drain before each sleep.
- Final error/Sentry/throw block unchanged.
