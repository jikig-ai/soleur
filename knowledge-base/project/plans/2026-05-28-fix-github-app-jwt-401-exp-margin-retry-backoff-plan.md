---
title: "fix: GitHub App installation-token 401s — JWT exp-margin + wider mint retry backoff"
type: fix
date: 2026-05-28
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
sentry_issue: 122537945
supersedes_partial: PR #4498 (2026-05-26 — added single 401 retry, did not fix exp boundary)
---

# fix: GitHub App installation-token 401s — JWT exp-margin + wider mint retry backoff

## Enhancement Summary

**Deepened on:** 2026-05-28
**Sections enhanced:** 4 (Research Insights, Implementation Phases, Risks, Acceptance Criteria)
**Research agents / passes used:** installed-SDK verification (`universal-github-app-jwt`), in-repo precedent grep (retry/backoff shapes), prior-learning reconciliation (PR #4498), gates 4.4/4.6/4.7/4.8

### Key Improvements

1. **Align the retry loop to the in-repo canonical backoff precedent** —
   `server/github-api.ts:21-22,56-95` already implements the exact pattern this
   plan needs: `MAX_RETRIES = 2` (3 total attempts), `BASE_DELAY_MS = 1_000`,
   `await delay(BASE_DELAY_MS * 2 ** attempt)` (1s, 2s), body-drain before each
   delay. Phase 3 now adopts this form verbatim instead of a divergent
   `[1000, 2000]` array constant — same delays, established idiom, lower review
   surface. (Precedent-diff gate, Phase 4.4.)
2. **Confirmed the octokit path is the precedent, not a co-victim** — verified
   `universal-github-app-jwt/index.js:23-24` computes `exp = now + 570` (a
   built-in 30s margin). Our `now + 540` is strictly more conservative; the
   octokit path needs no change and AC6 asserts it stays untouched.
3. **Prior-fix reconciliation** — this incident is the unresolved tail of PR
   #4498 (added the single 401 retry, never touched the exp boundary). The 90
   events firstSeen 2026-05-25 are post-#4498, proving the single retry was
   insufficient.

### New Considerations Discovered

- Two more in-repo backoff siblings beyond `github-api.ts` confirm the idiom:
  `server/concurrency.ts:82` and `server/inngest/send-with-retry.ts:33` (both
  `BASE_DELAY_MS * 2 ** attempt`). The repo has a single canonical
  exponential-backoff shape; the plan adopts it.
- `github-api.ts`'s retry is 5xx/network-only; our mint retry is 401-only — a
  deliberate divergence (the mint's transient class is JWT-replication/clock-skew
  401, not server 5xx). The loop SHAPE is shared; the retry PREDICATE differs by
  design. Documented in Risks.

## Overview

Sentry issue **122537945** (`Error: GitHub installation token request failed: 401`)
has fired **90 events over 14 days** (firstSeen 2026-05-25 14:31 UTC, lastSeen
2026-05-28 11:59 UTC, status unresolved). **100%** of events originate from the
Inngest function `workspace-reconcile-on-push`, minting an installation token for
org installation **122213433** — which is healthy (not suspended; `issues:write`
+ `members:read` granted). This is **not** a permission or suspension problem: the
App-JWT → installation-token exchange itself intermittently returns 401.

Two independent root causes in `apps/web-platform/server/github-app.ts`:

1. **JWT `exp` sits at GitHub's exact 600s maximum.** `createAppJwt()`
   (`github-app.ts:119-126`) sets `exp: now + 10 * 60` (600s). 600s is GitHub's
   **exact** maximum JWT lifetime. Under positive server-clock skew, GitHub reads
   `exp` as ">10 min in the future" and rejects the JWT with 401. Fix: leave
   margin (`exp: now + 540`, 9 min).

2. **The mint retry is too shallow.** `generateInstallationToken()`
   (`github-app.ts:460-529`) retries the token exchange **once** on 401 with a
   fixed 1s delay, then throws → `reportSilentFallback(op:
   "generate-installation-token")` → this Sentry issue. One 1s retry is
   insufficient for JWT-replication transients. Widen to **3 attempts total**
   (2 retries) with exponential backoff (1s, 2s).

**This incident is the unresolved tail of PR #4498** (2026-05-26), which added the
single 401-retry now present at `github-app.ts:491-496` but never touched the
`exp` boundary. 90 events firstSeen 2026-05-25 confirm the single retry did not
resolve it. See `knowledge-base/project/learnings/bug-fixes/2026-05-26-inngest-github-installation-token-401-resilience-gap.md`.

This is **auth-critical shared-path code**. A broken installation-token mint
blocks a user's workspace reconcile and all repo operations — hence the
`single-user incident` brand-survival threshold and `requires_cpo_signoff`.

## Research Reconciliation — Spec vs. Codebase

The triage ARGUMENTS made several claims; all were verified against the installed
code. Two require correction.

| Claim (ARGUMENTS / triage) | Reality (verified) | Plan response |
|---|---|---|
| `createAppJwt()` at ~lines 119-126 sets `iat: now-60`, `exp: now+600` | CONFIRMED verbatim at `github-app.ts:124-125` | Reduce `exp` to `now + 540`; keep `iat: now - 60` |
| `mintAndExchange`/`generateInstallationToken` at ~478-520 retries once on 401, 1s delay, then throws | CONFIRMED — inner `mintAndExchange()` closure at `:479-485`; single retry at `:491-496`; throw+`reportSilentFallback` at `:498-518` | Widen to 3 attempts, exp backoff |
| "Reducing `exp` margin benefits **every** App-JWT consumer (drift-guard, oauth-probe, KB upload, git-auth, workspace reconcile)" | **PARTIALLY WRONG.** There are **two** App-JWT minting paths. The hand-rolled `createAppJwt()` feeds git-auth, github-api, workspace, KB upload, and all Inngest crons (via `generateInstallationToken`). But **drift-guard and oauth-probe use `@octokit/app`** (`server/github/probe-octokit.ts` → `universal-github-app-jwt`), which is a **separate** minting path the `createAppJwt` fix does NOT touch. | Fix benefits all `github-app.ts` consumers. Drift-guard/oauth-probe are out of scope **and already safe** (see next row). No edit to `probe-octokit.ts`. |
| (implicit) octokit path may share the boundary bug | **FALSE — octokit path is NOT vulnerable.** `universal-github-app-jwt/index.js` computes `nowWithSafetyMargin = now - 30; expiration = nowWithSafetyMargin + 60*10` ⇒ `exp = now + 570` — a built-in 30s margin below the 600s ceiling. This is the canonical battle-tested pattern and is the **precedent** for our fix. | Cite octokit's `now + 570` as the precedent; our `now + 540` is strictly more conservative. No octokit change needed. |
| Test file `github-app-token-hardening.test.ts` covers the 401-retry behavior | CONFIRMED. Tests assert `mockFetch` `toHaveBeenCalledTimes(2)` (`:167, :206`) and use `vi.useFakeTimers()` + `vi.advanceTimersByTimeAsync(1_000)` | Existing count/timer assertions MUST be updated for the new 3-attempt / 1s+2s backoff. exp-margin asserted by decoding the captured Bearer JWT (pattern already used at `:188-191`). |
| Test runner is vitest; bun blocked via bunfig | CONFIRMED. `apps/web-platform/bunfig.toml` `[test] pathIgnorePatterns = ["**"]`; `package.json scripts.test = "vitest"`. vitest bin at `apps/web-platform/node_modules/.bin/vitest` | Use `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-token-hardening.test.ts` |

## Research Insights

- **The two JWT paths (load-bearing for scope).**
  - `createAppJwt()` (`github-app.ts:119-138`, module-internal) — used at
    `:162` (`getAppSlug`), `:240` (`getInstallationAccount`), `:351`
    (`findInstallationForLogin`), `:480` (`mintAndExchange` inside
    `generateInstallationToken`). **This is the only vulnerable path.**
  - `@octokit/app` via `server/github/probe-octokit.ts`
    (`createProbeOctokit`, `createAppJwtOctokit`) — used by
    `cron-github-app-drift-guard.ts` and `cron-oauth-probe.ts`. Mints its own
    JWT through `universal-github-app-jwt` with `exp = now + 570`. **Already
    safe. Out of scope.**
- **Downstream consumers of `generateInstallationToken` (all benefit from both fixes):**
  `server/workspace.ts:134`, `server/git-auth.ts:216`,
  `server/github-api.ts:106/131/162/197`, `server/inngest/functions/_cron-shared.ts:39`
  (the shared `mintInstallationToken` used by ~12 cron functions),
  `server/inngest/functions/workspace-reconcile-on-push.ts` (via `syncWorkspace`/git-auth),
  and `oneshot-gdpr-gate-50d-eval.ts:205`.
- **The retry already drains the first 401 body** (`:493`
  `await response.text().catch(() => {})`) before sleeping — preserve this in
  the loop refactor (drain before each retry sleep) to avoid socket leaks.
- **`generateInstallationToken` mints a fresh JWT per attempt** — `mintAndExchange()`
  calls `createAppJwt()` internally each time (`:480`), so each retry already gets
  a new `iat`/`exp`. The widened loop preserves this (fresh JWT per attempt is the
  whole point of retrying a clock-skew-rejected JWT).
- **Octokit precedent for the margin** — `iat: now - 30`, `exp: now + 570`
  (`universal-github-app-jwt/index.js`). Our choice `iat: now - 60`,
  `exp: now + 540` is more conservative on both ends. Precedent-diff satisfied
  (per `deepen-plan` Phase 4.4 precedent gate).
- **Backoff sizing.** 3 attempts with 1s + 2s = 3s max added latency on a fully
  failing mint. `@octokit/auth-app`'s `sendRequestWithRetries` retries downstream
  authenticated requests for up to ~5s; 3s on the exchange layer is within the
  same order and well under `GITHUB_FETCH_TIMEOUT_MS` (15s) per attempt.
- **Interactive callers exist (corrected at PR-review by `user-impact-reviewer`).**
  `generateInstallationToken` is reached synchronously from HTTP routes
  `POST /api/kb/upload` (via `github-api.ts` then `git-auth.ts`), `POST /api/kb/sync`,
  and the agent `pushBranch` tool — not only cron/reconcile. The added backoff is
  still acceptable: (a) **zero added latency on the happy path** (mint succeeds
  first try → 0 retries); (b) the added latency only occurs in the degraded 401
  window, where the retry converts a likely *failure* into a likely *success* —
  strictly better UX than the prior fail-after-1s; (c) the per-installation
  `tokenCache` collapses a single request's repeated calls (kb/upload's
  `githubApiPost` + `gitWithInstallationAuth`) to **one** real mint (the second
  hits cache), so worst-case added latency per request is ~3s, not ~6s; (d) a
  mint that exhausts all 3 attempts fails as a 500 in ~3s, well under the routes'
  30s `maxDuration`, and an unmintable token fails the downstream git op
  regardless. No interactive-caller retry cap is added — those callers benefit
  most from riding through a transient 401.

## User-Brand Impact

**If this lands broken, the user experiences:** their workspace silently stops
reconciling on push (the `workspace-reconcile-on-push` Inngest function fails its
token mint), and any repo operation routed through `generateInstallationToken`
(clone, PR create, repo list, KB sync) fails with an opaque 401-derived error.

**If this leaks, the user's data / workflow is exposed via:** N/A — this change
does not move or expose user data. It hardens an auth-token mint. The JWT carries
only the App ID (`iss`), `iat`, `exp` — no user-identifying content. Error logs
already redact PEM content (only an 8-char SHA-256 fingerprint at `:477` is
logged); the backoff loop must not change that.

**Brand-survival threshold:** single-user incident — a broken installation-token
mint blocks one user's workspace reconcile and repo operations end-to-end.

> CPO sign-off required at plan time before `/work` begins. CPO has already framed
> the blast radius in triage (single user's workspace reconcile / repo ops). The
> `user-impact-reviewer` agent will be invoked at review-time per
> `plugins/soleur/skills/review/SKILL.md`.

## Implementation Phases

> Phase order is load-bearing: the contract change (JWT exp) is independent of the
> retry change; both land in `github-app.ts`. Tests are written RED before each
> GREEN edit per `cq-write-failing-tests-before`.

### Phase 1 — RED: extend tests for exp-margin + widened backoff

File: `apps/web-platform/test/github-app-token-hardening.test.ts`

1. **exp-margin assertion (new test).** Add a test that mints a token
   successfully and decodes the Bearer JWT captured from
   `mockFetch.mock.calls[0][1].headers.Authorization` (split on `.`, base64url-
   decode the payload segment), then asserts:
   - `payload.exp - nowSeconds <= 540` (and `> 0`), where `nowSeconds =
     Math.floor(Date.now()/1000)` captured under fake timers.
   - `payload.iat <= nowSeconds` (negative skew preserved).
   Decode helper: `JSON.parse(Buffer.from(seg, "base64url").toString())`.
2. **Widened-retry tests.** Update the two existing tests that assert
   `toHaveBeenCalledTimes(2)`:
   - "throws after two consecutive 401s" → rename/extend to "throws after
     **three** consecutive 401s"; queue three `mock401()`; advance timers by the
     cumulative backoff (`await vi.advanceTimersByTimeAsync(1_000)` then
     `2_000`, or a single `3_000`); assert `toHaveBeenCalledTimes(3)`.
   - "throws with correct status after 401 followed by 500" → 401, 401, 500;
     assert `toHaveBeenCalledTimes(3)` and `rejects.toThrow(/500/)` and
     `reportSilentFallback` called.
3. **New backoff-success tests:**
   - "succeeds on 2nd attempt (1 retry)": 401 → success; advance 1s; 2 calls.
   - "succeeds on 3rd attempt (2 retries)": 401 → 401 → success; advance 1s then
     2s; 3 calls.
   - "does NOT retry on 403" (existing `:170-176`) — keep, still 1 call.
4. Preserve the AC2 (appId+fingerprint), AC3 (PEM shape), AC4
   (`reportSilentFallback`) tests; update any call-count expectations they carry.

Run (RED, must fail): `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-token-hardening.test.ts`

### Phase 2 — GREEN: reduce JWT exp margin

File: `apps/web-platform/server/github-app.ts` (`createAppJwt`, `:122-126`)

```ts
const payload = {
  iss: getAppId(),
  iat: now - 60,
  exp: now + 9 * 60, // 540s — 60s below GitHub's 600s max to absorb positive
                     // server-clock skew (octokit's universal-github-app-jwt
                     // uses now+570 for the same reason). #122537945.
};
```

Only the `exp` line changes. `iat: now - 60` is retained (more conservative than
octokit's `now - 30`). One-line change; benefits every `createAppJwt` caller.

### Phase 3 — GREEN: widen the mint retry to exponential backoff

File: `apps/web-platform/server/github-app.ts` (`generateInstallationToken`, `:487-519`)

Replace the single-retry block (`:487-496`) with a bounded loop that adopts the
**in-repo canonical backoff idiom** from `server/github-api.ts:21-22,56-95`
(see Precedent-Diff in Risks). Constraints:
- **Reuse the canonical constants/shape.** Add module-scope constants matching
  `github-api.ts:21-22` verbatim in name/value:
  `const INSTALL_TOKEN_MAX_RETRIES = 2; // 3 total attempts` and
  `const INSTALL_TOKEN_BASE_DELAY_MS = 1_000;`. Backoff delay is
  `INSTALL_TOKEN_BASE_DELAY_MS * 2 ** attempt` → attempt 0 = 1s, attempt 1 = 2s
  (identical delays to `github-api.ts:77`).
- **Only 401 retries** (this is the deliberate divergence from `github-api.ts`,
  which retries 5xx/network — the mint's transient class is JWT-replication /
  clock-skew 401, not 5xx). Any non-401 (`403`, `5xx`, ok) breaks the loop
  immediately — preserves the existing "does NOT retry on 403" and "401 then
  500 throws 500" semantics.
- **Drain the response body before each retry sleep** (`await
  response.text().catch(() => {})`) — preserve `:493` AND mirror `github-api.ts:72`.
- **Fresh JWT per attempt** — keep calling `mintAndExchange()` (which calls
  `createAppJwt()`) on each attempt.
- Keep a `log.warn` on each retry with `attempt + 1` + status (mirror
  `github-api.ts:73-76`).
- After the loop, the existing `if (!response.ok)` error/`reportSilentFallback`/
  throw block (`:498-518`) is unchanged — it fires on the final non-ok response.

Sketch (mirrors `github-api.ts:61-93` shape; 401-only predicate):
```ts
let response = await mintAndExchange();
for (
  let attempt = 0;
  response.status === 401 && attempt < INSTALL_TOKEN_MAX_RETRIES;
  attempt++
) {
  log.warn(
    { installationId, attempt: attempt + 1, status: response.status },
    "401 on installation token — retrying with backoff",
  );
  await response.text().catch(() => {}); // drain before delay (socket-leak guard)
  await new Promise((r) => setTimeout(r, INSTALL_TOKEN_BASE_DELAY_MS * 2 ** attempt));
  response = await mintAndExchange();
}
```
Note: `attempt` starts at 0 so `2 ** attempt` gives 1s then 2s, exactly as
`github-api.ts`. With `MAX_RETRIES = 2` the loop runs at most twice (attempts 0
and 1), yielding 3 total `mintAndExchange()` calls.

### Phase 4 — Verify GREEN + typecheck

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-token-hardening.test.ts` (all pass)
- `cd apps/web-platform && npx tsc --noEmit` (clean)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `createAppJwt()` produces a JWT whose decoded `exp - iat <= 600`
      AND `exp - now <= 540` (verified by the new decode-the-Bearer-JWT test). The
      `exp: now + 600` literal no longer appears: `grep -n "10 \* 60" apps/web-platform/server/github-app.ts`
      returns nothing in `createAppJwt`.
- [x] **AC2** — `generateInstallationToken` makes exactly **3** `fetch` calls on
      three consecutive 401s, then throws `/GitHub installation token request
      failed: 401/` and calls `reportSilentFallback({feature: "github-app", op:
      "generate-installation-token"})`. (vitest `toHaveBeenCalledTimes(3)`.)
- [x] **AC3** — `generateInstallationToken` makes 2 calls and succeeds when the
      2nd attempt returns a token; 3 calls and succeeds when the 3rd returns a
      token. Backoff delays are `INSTALL_TOKEN_BASE_DELAY_MS * 2 ** attempt`
      (1s then 2s), advanced via fake timers. (Matches `github-api.ts` idiom.)
- [x] **AC4** — Non-401 statuses do NOT trigger retry: 403 → 1 call + throw;
      401-then-500 → 2 calls + throw `/500/` + `reportSilentFallback` called.
- [x] **AC5** — `npx tsc --noEmit` clean in `apps/web-platform`.
- [x] **AC6** — `probe-octokit.ts` is **unchanged** (`git diff --name-only`
      excludes it) — confirms the octokit path was correctly scoped out as
      already-safe.
- [ ] **AC7** — PR body uses `Closes #<issue>` only if a GitHub issue tracks this;
      otherwise `Ref` the Sentry issue 122537945 in the body. (This is a
      code-fix landing pre-merge, not an ops-remediation, so `Closes` is
      appropriate if an issue exists.)

### Post-merge (operator) — automated where feasible

- [ ] **AC8** — After deploy, the Sentry event rate for issue **122537945** drops
      toward zero over a 24-72h window. **Automation:** queried by
      `discoverability_test` below (Sentry issues API, no SSH, no dashboard
      eyeball). Verdict rule: new events in the window after deploy timestamp
      should be 0 (allow ≤1 straggler from an in-flight retry); a rising count
      means the fix did not land or a third cause exists.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Shared-path auth change in `github-app.ts`. Two independent,
small, well-bounded edits (1-line exp; bounded retry loop). The dominant risk is
mis-scoping the blast radius — addressed by the Research Reconciliation rows
proving the octokit path is separate and already safe, and AC6 asserting
`probe-octokit.ts` is untouched. The retry-loop refactor must preserve four
invariants (401-only retry, fresh JWT per attempt, body-drain before sleep,
unchanged final error/Sentry block); each is an AC. No new infrastructure, no
schema, no new dependency.

### Product/UX Gate

Not applicable — no user-facing surface created or modified (server-side auth
internals). Tier: NONE.

## Infrastructure (IaC)

Skip — pure code change against an already-provisioned surface
(`apps/web-platform/server/`). No new server, secret, vendor, cron, or persistent
runtime process. The existing `GITHUB_APP_ID` / `GITHUB_APP_PRIVATE_KEY` secrets
are unchanged.

## Observability

```yaml
liveness_signal:
  what: Sentry issue 122537945 event rate (github-app / generate-installation-token op)
  cadence: continuous (per-mint-failure)
  alert_target: Sentry (de.sentry.io, org jikigai-eu, project web-platform)
  configured_in: apps/web-platform/server/github-app.ts (reportSilentFallback at :513)
error_reporting:
  destination: Sentry (captureException, tags feature=github-app op=generate-installation-token) + pino stdout
  fail_loud: true (reportSilentFallback mirrors to Sentry; throw propagates to Inngest function which surfaces in POST /api/inngest)
failure_modes:
  - mode: persistent 401 after 3 attempts (genuine credential/clock problem)
    detection: Sentry issue 122537945 fires; error log carries appId + pemFingerprint
    alert_route: Sentry default project alerting
  - mode: transient 401 resolved by retry (the target of this fix)
    detection: log.warn "401 on installation token — retrying with backoff" with attempt + delayMs; no Sentry event when a retry succeeds
    alert_route: pino stdout (container logs) only — by design, success is not paged
  - mode: non-401 mint failure (403 perm, 5xx)
    detection: Sentry issue (same op tag, status field distinguishes); single attempt for 403
    alert_route: Sentry
logs:
  where: container stdout (pino) + Sentry
  retention: Sentry default (30-90d); container stdout per host log policy
discoverability_test:
  command: >
    curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN"
    "https://de.sentry.io/api/0/organizations/jikigai-eu/issues/122537945/events/?statsPeriod=24h"
    | jq 'length'
  expected_output: "0 (or a small straggler count) after deploy; a rising count over successive 24h windows = fix did not land"
```

> Note: `SENTRY_API_TOKEN` and `SENTRY_AUTH_TOKEN` lack issue-read scope — only
> `SENTRY_IAC_AUTH_TOKEN` (Doppler `prd`) works for the issues API. Host
> `de.sentry.io`, org `jikigai-eu`, project `web-platform`.

## Precedent-Diff (Phase 4.4)

The retry-with-exponential-backoff loop is a **pattern-bound behavior** with an
established in-repo precedent. `git grep -nE "BASE_DELAY_MS \* 2 \*\* attempt"
apps/web-platform/server` returns three sibling call sites:

| Site | Constants | Backoff | Body-drain | Retry predicate |
|---|---|---|---|---|
| `server/github-api.ts:21-22,56-95` (canonical) | `MAX_RETRIES = 2`, `BASE_DELAY_MS = 1_000` | `BASE_DELAY_MS * 2 ** attempt` (1s, 2s) | `:72` before delay | 5xx + network/timeout |
| `server/inngest/send-with-retry.ts:33` | `MAX_RETRIES`, `BASE_DELAY_MS` | `BASE_DELAY_MS * 2 ** attempt` | n/a (event send) | transient fetch errors |
| `server/concurrency.ts:82` | inline `< 3`, `attempt < 2` | `2 ** attempt`-style | n/a | transient |
| **This plan** (`generateInstallationToken`) | `INSTALL_TOKEN_MAX_RETRIES = 2`, `INSTALL_TOKEN_BASE_DELAY_MS = 1_000` | `* 2 ** attempt` (1s, 2s) | before delay | **401 only** |

**Deliberate divergence:** this plan retries on 401 only, where `github-api.ts`
retries on 5xx/network. This is correct — the mint's transient failure class is
JWT-replication / clock-skew 401, not server 5xx. The loop SHAPE (constants,
exponential delay, body-drain, fresh-attempt) is adopted verbatim; only the retry
PREDICATE differs by design. No novel pattern is introduced.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Backoff adds latency to a genuinely-broken mint (3s worst case) on interactive routes (kb/upload, kb/sync, pushBranch — corrected at review) | Added latency is zero on the happy path; only the degraded-401 window pays it, where the retry converts failure→success. `tokenCache` collapses a request's repeated mints to one (~3s, not ~6s), well under the routes' 30s `maxDuration`; an unmintable token fails the request regardless. 3s ≪ per-attempt 15s timeout; within octokit's own ~5s retry envelope. |
| Retry loop drops the body-drain and leaks sockets | AC + explicit Phase 3 constraint: `response.text().catch(()=>{})` before each sleep (preserves `:493`). |
| `exp` reduced too far breaks slow exchanges | 540s is 9 min — the token exchange round-trips in <1s typically and is timeout-bounded at 15s; 540s is ample. octokit uses an even tighter 570s-from-`now` with a 30s past-skew on `iat`. |
| Scope creep into the octokit path | Out of scope by Research Reconciliation; octokit's `exp = now + 570` is already safe. AC6 asserts `probe-octokit.ts` untouched. |
| Third-party behavior claim (octokit exp) is wrong | Verified against installed `node_modules/universal-github-app-jwt/index.js` (`now - 30 + 60*10`). Not doc-derived. |

## Test Scenarios

| Scenario | Setup | Expected |
|---|---|---|
| exp margin | mint succeeds; decode Bearer JWT | `exp - now <= 540`, `iat <= now` |
| 1 retry success | 401 → 200 | 2 calls, token returned, 1s advanced |
| 2 retry success | 401 → 401 → 200 | 3 calls, token returned, 1s+2s advanced |
| exhausted retries | 401 → 401 → 401 | 3 calls, throws /401/, reportSilentFallback called |
| no retry on 403 | 403 | 1 call, throws /403/ |
| 401 then 500 | 401 → 500 | 2 calls, throws /500/, reportSilentFallback called |
| fresh JWT per attempt | 401 → 200 | both Authorization headers `Bearer …`, distinct iat |

## Test Strategy

- Runner: **vitest** (`apps/web-platform/package.json scripts.test`). bun test is
  blocked for web-platform (`bunfig.toml` `[test] pathIgnorePatterns = ["**"]`).
- Invocation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-token-hardening.test.ts`
- Fake timers (`vi.useFakeTimers()`) drive the backoff sleeps; advance by
  cumulative backoff (`1_000` then `2_000`, or `3_000` once) per scenario.
- JWT decode uses Node `Buffer.from(seg, "base64url")` (no new dependency).

## Files to Edit

- `apps/web-platform/server/github-app.ts` — `createAppJwt` exp (Phase 2);
  `generateInstallationToken` retry loop (Phase 3).
- `apps/web-platform/test/github-app-token-hardening.test.ts` — exp-margin test +
  widened-retry assertions (Phase 1).

## Files to Create

- None.

## Open Code-Review Overlap

None — checked `gh issue list --label code-review --state open` is not required to
block this; the two files above are not named in any open scope-out at plan time.
(If `/work` finds an open scope-out touching `github-app.ts`, fold in or
acknowledge per the overlap gate.)

## GDPR / Compliance

No regulated-data surface touched. The JWT carries only App ID + timestamps;
error logs already pseudonymize (PEM fingerprint only, no raw key). gdpr-gate not
triggered (no schema, migration, auth-flow user-data, API route, or `.sql`; no
LLM-on-session-data; the `single-user incident` threshold here is an availability
incident, not a data-processing change). Skipped.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's section is complete with a `single-user incident`
  threshold.)
- The existing tests assert `toHaveBeenCalledTimes(2)` in two places
  (`:167`, `:206`) — these WILL fail after the retry widening if not updated.
  Phase 1 updates them to `3`. Do not skip.
- Do NOT touch `server/github/probe-octokit.ts` — it is a separate JWT path
  (`@octokit/app` → `universal-github-app-jwt`) that already leaves a 30s margin
  (`exp = now + 570`). Editing it is out of scope and would expand blast radius.
- The retry loop must drain `response.text()` before each sleep (socket-leak
  guard) and mint a **fresh** JWT per attempt — both are pre-existing behaviors
  that the loop refactor must preserve.
