---
title: "fix: probe-octokit App-JWT diagnostics + retry parity"
type: fix
date: 2026-05-28
branch: feat-one-shot-probe-octokit-jwt-diag
lane: cross-domain
brand_survival_threshold: none
sentry_ids:
  - f3ad8fecf42645f691d67813a4f36cec  # probe path (this PR's target)
  - 8296c9a9e5c74837b38905ca9efca3b7  # sibling 401 (github-app.ts, already addressed by PR 4565)
---

# fix: probe-octokit App-JWT diagnostics + retry parity 🐛

## Enhancement Summary

**Deepened on:** 2026-05-28
**Sections enhanced:** Precedent-diff (Phase 4.4), verify-the-negative (Phase 4.45)
**Hard gates passed:** 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped variable — all PASS.

### Key Improvements
1. **Precedent-diff confirmed (not novel).** The prescribed backoff constants
   match the two in-repo precedents byte-for-byte: `github-api.ts:21-22,77`
   (`MAX_RETRIES=2`, `BASE_DELAY_MS=1_000`, `delay(BASE_DELAY_MS * 2 ** attempt)`)
   and `github-app.ts:467-468,508,517` (`INSTALL_TOKEN_MAX_RETRIES=2`,
   `INSTALL_TOKEN_BASE_DELAY_MS=1_000`, `status === 401 && attempt < MAX`,
   `setTimeout(r, BASE * 2 ** attempt)`). See Research Insights below.
2. **Verify-the-negative confirmed.** The plan's claim "the App JWT / PEM is never
   materialized into the captured `extra`" holds: the only secret reference in
   `probe-octokit.ts` is `readEnv(PRIVATE_KEY_ENV)` passed straight into
   `new App({...})` — never into a log or captured variable. The diagnostic
   capture reads only `err.status` + `err.response.{headers,data}` (GitHub-origin).
3. **No new scheduled job** — edits an existing Inngest cron (`cron-oauth-probe`);
   ADR-033 scheduled-work precedent check is N/A.

### New Considerations Discovered
- The one structural difference from the precedents: probe-octokit authenticates
  via `@octokit/app`'s `App.octokit.request(...)`, the precedents use raw
  `fetch` + `Bearer <jwt>`. Parity is on the **retry shape** (attempt count,
  delays, 401-only predicate, fresh-instance-per-attempt), not the fetch
  mechanism. Already reflected in the Overview + Phase 3.

## Overview

The OAuth-probe Inngest cron (`cron-oauth-probe`) intermittently fails with
`HttpError: A JSON web token could not be decoded` (Sentry
`f3ad8fecf42645f691d67813a4f36cec`, release 0.101.100, prod). The failure
fires inside `createProbeOctokit()` (`apps/web-platform/server/github/probe-octokit.ts`)
when it mints an App JWT via `@octokit/app` and calls
`GET /repos/{owner}/{repo}/installation` to manage the `[ci/auth-broken]`
tracking issue.

This error has been "fixed" repeatedly on the **sibling** path
(`server/github-app.ts`) by widening JWT `exp` margins (PR 4498) and deepening
retries (PR 4565, commit c43da45b), yet the **probe** path keeps recurring.
**Those fixes target the wrong failure class for this path.** This plan does NOT
widen any JWT margin. It does two things, in priority order:

1. **Diagnostic instrumentation first** — capture GitHub's actual HTTP status,
   response body, `x-github-request-id`, and a measured clock-skew on the
   App-JWT request failure, so the **next** occurrence is self-diagnosing
   instead of forcing another guess-and-patch cycle.
2. **Retry parity** — bring `probe-octokit.ts` from its single 1s 401-retry up
   to the canonical 3-attempt exponential backoff (1s, 2s) with a fresh `App`
   instance / JWT per attempt and a 401-only predicate, matching the idiom
   already deployed in `server/github-app.ts` (PR 4565) and codified in
   `server/github-api.ts`.

The recurring guess-and-patch cycle's **meta-cause** is data loss: the current
`probe-octokit.ts` catch (`probe-octokit.ts:72-78`) rethrows only the bare
error, discarding status, body, and request-id. This PR closes that gap. It does
**not** claim to root-cause the JWT decode failure — it makes it diagnosable.

### Why this is NOT an exp-margin problem (verified, not assumed)

Verified against the installed code in this worktree:

- `@octokit/app` mints its App JWT via `universal-github-app-jwt@2.2.2`.
  `node_modules/universal-github-app-jwt/index.js:17` already normalizes escaped
  newlines: `privateKey.replace(/\\n/g, '\n')`. So **PEM `\n`-escaping is not the
  gap on this path.**
- That same file sets `iat = now - 30` and `exp = iat + 60*10` (= now + 570s,
  capped at the 600s GitHub ceiling). So **the JWT is well inside the exp window
  by construction; an `exp`-too-far / expiry 401 is not the failure here.**
- `"A JSON web token could not be decoded"` is GitHub's response for a
  **signature / structural** JWT rejection (malformed header/payload/signature,
  wrong key, base64 corruption), NOT an expiry 401. Margin-shaving cannot fix it.
  This is exactly why the diagnostic capture is the highest-value deliverable:
  the status + body + request-id will tell us whether the recurrences are
  (a) transient GitHub-side JWT-replication 401s that the retry now absorbs, or
  (b) a credential/installation-identity mismatch (a follow-up, see Non-Goals).

> Minor correction to the framing brief: the lib uses `exp = now + 570`
> (`now-30 + 600`), not `now + 570` measured from `now`. Immaterial to the
> conclusion — still inside the ceiling.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task framing) | Codebase reality (verified this worktree) | Plan response |
| --- | --- | --- |
| `universal-github-app-jwt` normalizes escaped `\n` at "index.js line 17" | True. `node_modules/universal-github-app-jwt/index.js:17` = `privateKey.replace(/\\n/g, '\n')`. Lib version 2.2.2. | No PEM-escaping work. |
| Lib uses `iat=now-30, exp=now+570` | `iat = now-30`; `exp = (now-30) + 60*10 = now+570`. Brief's "exp=now+570" is right by value, off by derivation. | No exp-margin work; documented above. |
| `probe-octokit.ts` ~line 75 still on single 1s 401-retry | Confirmed: `probe-octokit.ts:70-78`, one `setTimeout(1000)` then one re-attempt; catch rethrows bare `err`. | Replace with canonical 3-attempt backoff + capture (Phase 2/3). |
| Canonical backoff lives in `server/github-api.ts` (PR 4565 note) | Confirmed. `github-api.ts:21-22,56-96` (`MAX_RETRIES=2`, `BASE_DELAY_MS=1_000`, `delay(BASE_DELAY_MS * 2 ** attempt)`). github-app.ts:506-520 mirrors it 401-only. | Reuse the same constant + loop shape; 401-only predicate. |
| Capture via `reportSilentFallback` or existing observability layer | `server/observability.ts` exports `reportSilentFallback(err, { feature, op, extra, message })` and `warnSilentFallback(...)`. `extra` is free-form `Record<string, unknown>`. Already imported + used in `cron-oauth-probe.ts:32,598,643`. | Use `warnSilentFallback` for the retried-and-recovered case (warning level), `reportSilentFallback` is already the caller's terminal-failure path in cron-oauth-probe.ts. See Phase 1 decision. |
| Error carries status/body/request-id/Date | `@octokit/request-error` `RequestError`: `.status: number`, `.response?: OctokitResponse`. `OctokitResponse.headers: ResponseHeaders` has `date?: string` + `"x-github-request-id"?: string`; `.data` is the body. | Capture all four off the caught error (Phase 1). |
| Existing test to extend | `apps/web-platform/test/server/github/probe-octokit-retry.test.ts` (120 lines, 5 tests, vitest + `vi.mock("@octokit/app")`). | Extend, don't replace (Phase 2 RED). |
| `strip_log_injection` convention in cron-oauth-probe.ts | `stripLogInjection()` at `cron-oauth-probe.ts:67-71`. Lives in the cron file, NOT exported from probe-octokit. | See Sharp Edge: the values captured by probe-octokit (GitHub-origin body) should be sliced + sanitized before they land in any operator-facing surface. Decide ownership in Phase 1. |
| Test command is `bun test` | FALSE. `package.json:"test": "vitest"`; `bunfig.toml [test]` blocks bun discovery. | Test command is `./node_modules/.bin/vitest run <path>`. |

## User-Brand Impact

**If this lands broken, the user experiences:** the OAuth-probe cron either
crashes (no tracking issue filed when prod auth is genuinely broken — a silent
blind spot) or floods Sentry with low-signal noise. The probe is
**platform-owned synthetic traffic** (`probe-octokit.ts:5-16`), not a founder
flow — no end user sees the probe directly. The downstream risk is that a real
OAuth outage goes unsurfaced because the probe's own auth is flaky.

**If this leaks, the user's data is exposed via:** N/A — the diagnostic
`extra` payload carries GitHub API status/body/request-id and a clock-skew
number; the App JWT itself is **never** materialized into the captured payload
(only the resulting error's `.response.data`, which is GitHub's public error
JSON, not the secret key). The PEM and minted JWT stay inside `@octokit/app`.
Confirm in Phase 1 that no code path writes `process.env.GITHUB_APP_PRIVATE_KEY`
or the JWT string into `extra`.

**Brand-survival threshold:** `none`. Synthetic platform traffic, no
founder-data surface, no regulated-data write. (Sensitive-path note: this PR
edits `apps/web-platform/server/**` but introduces no schema/auth/API-route
change and no PII handling; threshold `none` with reason: probe is
platform-owned synthetic traffic with no founder-data or regulated-data
surface.)

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

- [ ] `grep -nE 'GITHUB_APP_PRIVATE_KEY|privateKey|appJwt|\bjwt\b' apps/web-platform/server/github/probe-octokit.ts`
      — confirm the secret/JWT is never read into a logged/captured variable.
- [ ] `grep -n 'date\|x-github-request-id' node_modules/@octokit/types/dist-types/ResponseHeaders.d.ts`
      — confirm header keys (verified: `date?` line 5, `"x-github-request-id"?` line 15).
- [ ] Confirm test runner: `grep '"test"' apps/web-platform/package.json` → `vitest`.
      Run the existing suite green BEFORE edits:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts`.
- [ ] Decide where `stripLogInjection`-equivalent sanitization of the captured
      GitHub body lives (see Sharp Edge). The captured `body` is GitHub-origin
      (not attacker-controlled via probe input), but it flows into Sentry `extra`
      and pino logs — slice to ≤500 chars (mirror `github-app.ts:527`
      `body.slice(0, 500)`) and strip CR/LF before capture.

### Phase 1 — RED: failing tests for diagnostic capture (cq-write-failing-tests-before)

Extend `apps/web-platform/test/server/github/probe-octokit-retry.test.ts`. The
existing `vi.mock("@octokit/app")` harness already removes the network — extend
the mock so the rejected error carries a `response`:

- [ ] Add a `httpErrorWithResponse(message, status, { date, requestId, body })`
      helper that builds an `Error` with `.status` and
      `.response = { status, headers: { date, "x-github-request-id": requestId }, data: body }`.
- [ ] Spy on the observability layer:
      `vi.mock("@/server/observability", ...)` (or the relative path the file
      resolves) exposing a `warnSilentFallback` / `reportSilentFallback` spy.
      **Verify the import specifier** the production file will use against
      `tsconfig` path aliases before freezing the mock (the cron file uses
      `@/server/observability`; probe-octokit currently imports nothing from it).
- [ ] **Test: on a 401 that ultimately fails all attempts, the capture call
      receives status, body (sliced), `x-github-request-id`, and a numeric
      `clockSkewMs`.** Assert the `extra` object shape, e.g.
      `expect(spy).toHaveBeenCalledWith(expect.any(Error), expect.objectContaining({ feature: "cron-oauth-probe" /* or probe-octokit */, op: expect.stringContaining("app-jwt"), extra: expect.objectContaining({ ghStatus: 401, ghRequestId: "REQ-123", ghBody: expect.any(String), clockSkewMs: expect.any(Number) }) }))`.
- [ ] **Test: clock-skew is computed from the response `Date` header** — feed a
      `Date` header 5s ahead of a frozen `Date.now()` and assert
      `clockSkewMs ≈ 5000` (tolerance for the fake-timer base). Use
      `vi.setSystemTime()` to lock local clock.
- [ ] **Test: the captured body is sliced to ≤500 chars and CR/LF-stripped** —
      feed an oversized body with embedded `\n` and assert the captured `ghBody`
      length ≤ 500 and contains no `\r`/`\n`.
- [ ] Run the suite; confirm these new tests FAIL (RED) and the 5 existing tests
      still pass. Command:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts`.

### Phase 2 — RED: failing tests for 3-attempt backoff parity

Still in the same test file:

- [ ] **Test: retries TWICE on consecutive 401s, succeeds on third attempt**
      (`MockApp` called 3×, `mockRequest` called 3×). Advance fake timers by
      `1_000` then `2_000`.
- [ ] **Test: throws after THREE consecutive 401s** (`MockApp` called 3×). Update
      the existing `"throws after two consecutive 401s"` test's expectation from
      `MockApp` 2× → 3× (rename to reflect the new budget) and advance timers 1s+2s.
- [ ] **Test: a fresh `App` instance (fresh JWT) is constructed per attempt** —
      already partially asserted via `MockApp.toHaveBeenCalledTimes`; keep.
- [ ] **Test: still does NOT retry on 404 / 403** (the two existing negative
      tests stay; confirm budget change didn't loosen the 401-only predicate).
- [ ] Confirm RED. The existing impl (single 1s retry) will fail the 3-attempt
      assertions.

> Note: the existing test uses `vi.advanceTimersByTimeAsync(1_000)` for the
> single retry. The new backoff sleeps 1s then 2s — tests must advance
> `1_000` then `2_000` (or `3_000` total) per the `BASE_DELAY_MS * 2 ** attempt`
> schedule. Mirror the timer-advance shape used in any github-app.ts test if one
> exists; otherwise derive from the loop.

### Phase 3 — GREEN: rewrite `createProbeOctokit()` retry + capture

Edit `apps/web-platform/server/github/probe-octokit.ts`:

- [ ] Add module constants mirroring the canonical idiom (cite the source in a
      comment, matching github-app.ts:463-466 style):
      ```ts
      // Mirrors the canonical backoff idiom in server/github-api.ts
      // (MAX_RETRIES=2, BASE_DELAY_MS=1_000 → 1s, 2s) and the parity fix in
      // server/github-app.ts:506-520 (PR 4565, #122537945). 401-only: a 401 on
      // App-JWT installation discovery is the transient JWT-replication class;
      // any non-401 breaks immediately, preserving 404/403/5xx semantics.
      const PROBE_JWT_MAX_RETRIES = 2;       // 3 total attempts
      const PROBE_JWT_BASE_DELAY_MS = 1_000; // 1s, 2s
      ```
- [ ] Rewrite the `try { return await attempt(); } catch { ...single retry... }`
      block (`probe-octokit.ts:70-78`) as a 3-attempt loop: fresh `App` instance
      per attempt (the existing `attempt()` already constructs a new `App` each
      call — keep that), 401-only continue, exponential `setTimeout` sleep.
- [ ] On the **final** failed attempt (loop exhausted with a 401) AND on any
      non-401 that escapes, **capture diagnostics before rethrowing**:
      - `ghStatus` = `(err as RequestError).status`
      - `resp` = `(err as RequestError).response`
      - `ghRequestId` = `resp?.headers?.["x-github-request-id"]`
      - `ghDate` = `resp?.headers?.date`
      - `clockSkewMs` = `ghDate ? Date.now() - new Date(ghDate).getTime() : null`
        (positive = local clock ahead of GitHub — the exact direction that
        produces JWT `iat`-in-future rejections)
      - `ghBody` = sanitize: `String(resp?.data ?? "").replace(/[\r\n]/g, " ").slice(0, 500)`
      - Call the observability helper (see decision below) with
        `{ feature, op: "create-probe-octokit:app-jwt", extra: { ghStatus, ghRequestId, clockSkewMs, ghBody, attempts } }`.
        Do **not** put the PEM or JWT string in `extra`.
- [ ] **Decision — which observability helper:** `createProbeOctokit()` is called
      from inside `cron-oauth-probe.ts`'s `step.run("issue-handling", ...)` which
      ALREADY wraps the call in a try/catch that fires `reportSilentFallback`
      (`cron-oauth-probe.ts:633-649`). To avoid double-reporting the same failure
      at error level, the probe-octokit capture should be the **warning-level
      diagnostic breadcrumb** for the *retried-and-recovered* case AND a
      structured pre-rethrow capture for the *exhausted* case. Use
      `warnSilentFallback` for the recovered case (a 401 that a retry fixed —
      worth a breadcrumb, not an error) and let the existing
      `reportSilentFallback` in the cron handler own the terminal error, BUT
      attach the diagnostic `extra` to the rethrown error so the cron handler's
      capture includes it. **Resolve the exact split in Phase 1 when the test
      shape is fixed** — the test asserts a capture call with the diagnostic
      `extra`; whichever helper carries it must be consistent between test and
      impl. Cite `cq-silent-fallback-must-mirror-to-sentry`: any warn/error
      fallback must reach Sentry (both helpers already do).
- [ ] Import `reportSilentFallback`/`warnSilentFallback` from the same specifier
      the cron file uses (`@/server/observability`).
- [ ] Run suite GREEN:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts`.

### Phase 4 — REFACTOR + typecheck

- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — confirm the
      `RequestError` / `OctokitResponse` typing compiles (import the type from
      `@octokit/request-error` if a cast is needed, or narrow via
      `err && typeof err === "object" && "status" in err`).
- [ ] Confirm no `any` leak on the error narrowing; prefer a small typed
      `extractGitHubErrorDiag(err): { ghStatus?, ghRequestId?, ghDate?, ghBody?, clockSkewMs? }`
      helper if the inline narrowing gets noisy (keeps the loop readable and is
      independently testable).
- [ ] Re-run the full github test slice to confirm no sibling regressions:
      `./node_modules/.bin/vitest run test/server/github/`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (diagnostics):** On an App-JWT request failure, the captured
      observability `extra` contains `ghStatus`, `ghRequestId`, `ghBody`
      (≤500 chars, no CR/LF), and a numeric/`null` `clockSkewMs`. Verified by the
      Phase 1 tests (assert the spy call's `extra` shape).
- [ ] **AC2 (clock-skew direction):** `clockSkewMs` is computed as
      `Date.now() - Date.parse(response.headers.date)` (positive = local ahead),
      asserted by the skew test.
- [ ] **AC3 (retry parity):** `createProbeOctokit()` makes up to 3 total attempts
      on consecutive 401s (`MockApp` called 3×), sleeping 1s then 2s, with a fresh
      `App`/JWT per attempt. Asserted by Phase 2 tests.
- [ ] **AC4 (401-only predicate preserved):** 404 and 403 still do NOT retry
      (`MockApp` called 1×). Existing negative tests pass unchanged.
- [ ] **AC5 (no secret leak):** `grep -nE 'GITHUB_APP_PRIVATE_KEY|privateKey|jwt'`
      over the diagnostic-capture code path returns no occurrence inside the
      `extra` payload construction. Manual + grep.
- [ ] **AC6 (idiom citation):** the new backoff constants/comment cite
      `server/github-api.ts` + `server/github-app.ts:506-520` (PR 4565,
      `#122537945`) so the parity lineage is greppable.
- [ ] **AC7 (suite green):**
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts`
      passes; `./node_modules/.bin/tsc --noEmit` clean.
- [ ] **AC8 (no margin change):** `git diff` touches neither `server/github-app.ts`
      `createAppJwt` margins nor any `exp`/`iat` constant. (This PR's scope guard.)

### Post-merge (operator)

- [ ] **AC9 (self-diagnosing next occurrence):** After deploy, the NEXT
      `f3ad8fecf42645f691d67813a4f36cec`-class Sentry event (if any) carries
      `ghStatus`, `ghRequestId`, `ghBody`, `clockSkewMs` in its `extra`.
      Automation: read via Sentry MCP/API at next occurrence — not a blocking
      pre-merge step (depends on a live recurrence). Verification:
      query Sentry issue `f3ad8fecf42645f691d67813a4f36cec` events for the new
      `extra` keys. No SSH.

## Non-Goals / Deferred

- **Root-causing the JWT decode failure.** This PR makes it diagnosable, not
  necessarily root-caused. If the captured `extra` later reveals a
  credential/installation-identity mismatch — relevant churn: closed bug #4543
  (KB-sync installation_id), PR #4557 (sibling-installation matching), PR #4565,
  runbook install ID `122213433` — that is a **follow-up issue**, filed once the
  instrumented data points at it. Create the tracking issue at that point with
  the captured `ghRequestId` + `ghStatus` as evidence.
- **Touching `server/github-app.ts` / `createAppJwt` margins.** Already
  fixed/deployed (sibling Sentry `8296c9a9e5c74837b38905ca9efca3b7`, PR 4565,
  deployed 15:50:46 CEST). Out of scope.
- **Widening JWT `exp`/`iat` margins on any path.** Explicitly rejected — wrong
  failure class (see Overview).

## Observability

```yaml
liveness_signal:
  what: cron-oauth-probe Sentry heartbeat (monitor slug "scheduled-oauth-probe")
  cadence: hourly (cron "0 * * * *")
  alert_target: Sentry cron monitor (sentry_cron_monitor.scheduled_oauth_probe)
  configured_in: apps/web-platform/server/inngest/functions/cron-oauth-probe.ts:45,671-678
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (server/observability.ts)
  fail_loud: true — App-JWT failures now carry ghStatus/ghRequestId/ghBody/clockSkewMs in extra; the cron handler's existing reportSilentFallback (cron-oauth-probe.ts:643) is the terminal path
failure_modes:
  - mode: App-JWT structural decode 401 (recurring target)
    detection: warnSilentFallback breadcrumb on retry-recovered; reportSilentFallback on exhausted, both with diagnostic extra
    alert_route: Sentry issue f3ad8fecf42645f691d67813a4f36cec
  - mode: clock-skew (local ahead of GitHub → iat-in-future rejection)
    detection: clockSkewMs field in captured extra (positive = local ahead)
    alert_route: Sentry extra field (queryable per-event)
  - mode: installation discovery 404/403 (non-retryable)
    detection: existing cron handler 403→issue_write_403 discriminator (cron-oauth-probe.ts:639-642); 404 rethrows
    alert_route: Sentry op tag
logs:
  where: pino structured logs via createChildLogger("probe-octokit") + Sentry breadcrumbs
  retention: Sentry default (90d) / pino to stdout (Inngest run logs)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts"
  expected_output: "all tests pass incl. diagnostic-capture + 3-attempt-backoff assertions (no ssh)"
```

## Research Insights (deepen-plan)

### Precedent-Diff — backoff idiom is canonical, not novel (Phase 4.4)

The prescribed `createProbeOctokit()` retry loop mirrors two in-repo
precedents. Side-by-side (verified against the installed source this worktree):

| Aspect | `github-api.ts` (#1927) | `github-app.ts:489-520` (PR 4565, #122537945) | This plan's `probe-octokit.ts` |
| --- | --- | --- | --- |
| Max retries | `MAX_RETRIES = 2` (`:21`) | `INSTALL_TOKEN_MAX_RETRIES = 2` (`:467`) | `PROBE_JWT_MAX_RETRIES = 2` |
| Base delay | `BASE_DELAY_MS = 1_000` (`:22`) | `INSTALL_TOKEN_BASE_DELAY_MS = 1_000` (`:468`) | `PROBE_JWT_BASE_DELAY_MS = 1_000` |
| Sleep schedule | `delay(BASE_DELAY_MS * 2 ** attempt)` (`:77`) | `setTimeout(r, BASE * 2 ** attempt)` (`:517`) | `setTimeout(r, BASE * 2 ** attempt)` — 1s, 2s |
| Retry predicate | 5xx OR retryable network err | **401-only** (`:508`) | **401-only** (transient JWT-replication) |
| Fresh creds/attempt | fresh `AbortSignal` per attempt | fresh JWT via `mintAndExchange()` per attempt | fresh `App` instance (fresh JWT) per `attempt()` |
| Body drain before sleep | `await response.text()` (`:72`) | `await response.text()` (`:515`) | N/A — `@octokit/app` consumes the body internally; no raw `Response` to drain |

**Structural difference (not a parity gap):** the two precedents use raw
`fetch` + `Authorization: Bearer <jwt>`; probe-octokit uses
`@octokit/app`'s `App.octokit.request(...)`, which mints + attaches the JWT
internally. Parity is on the retry *shape*, not the fetch mechanism — so there
is no `response.text()` body-drain step (there is no caller-visible `Response`).
The diagnostic capture reads the **thrown `RequestError`'s** `.response` instead.

### Verify-the-negative — secret never enters `extra` (Phase 4.45)

Claim under test (User-Brand Impact + AC5): *"the App JWT / PEM is never
materialized into the captured `extra`."*

`grep -nE 'privateKey|GITHUB_APP_PRIVATE_KEY|appJwt' probe-octokit.ts` →
the only references are `PRIVATE_KEY_ENV` (`:30`) and
`privateKey: readEnv(PRIVATE_KEY_ENV)` (`:61,:107`), both passed directly into
`new App({...})`. The existing `log.warn` (`:75`) is a static string. **Confirms**
the claim: the diagnostic capture reads only `err.status` and
`err.response.{headers,data}` (GitHub-origin error JSON + lower-cased response
headers), none of which contain the secret. The implementer MUST keep it that
way — AC5's grep enforces it.

## Test Strategy

- Runner: **vitest** (`package.json:"test": "vitest"`; `bunfig.toml` blocks bun
  discovery). Command: `./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts`.
- Extend the existing `probe-octokit-retry.test.ts` (do not create a new file).
- Mocks: existing `vi.mock("@octokit/app")` harness (no network). Add a spy on
  `@/server/observability`. Use `vi.useFakeTimers()` + `vi.setSystemTime()` for
  deterministic clock-skew.
- LLM removed from assertion path: N/A (no LLM in this path).

## Files to Edit

- `apps/web-platform/server/github/probe-octokit.ts` — 3-attempt backoff +
  diagnostic capture in `createProbeOctokit()`.
- `apps/web-platform/test/server/github/probe-octokit-retry.test.ts` — extend
  with diagnostic-capture + 3-attempt-backoff tests.

## Files to Create

- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open issue
whose body references `probe-octokit` or `cron-oauth-probe`.

## Sharp Edges

- **Observability-helper double-report.** `createProbeOctokit()` is called from
  inside the cron's `step.run("issue-handling")` try/catch that already calls
  `reportSilentFallback` on throw (`cron-oauth-probe.ts:633-649`). If the probe
  also calls `reportSilentFallback` at error level on the exhausted case, the
  same failure is reported twice. Resolution: probe emits a **warning-level**
  breadcrumb for retry-recovered, and attaches the diagnostic `extra` to the
  rethrown error (or uses `warnSilentFallback`), leaving the cron handler as the
  single terminal error reporter. Lock the exact split when the Phase 1 test
  shape is frozen so test and impl agree on which helper carries the `extra`.
- **`stripLogInjection` ownership.** The sanitizer lives in `cron-oauth-probe.ts`
  (`:67-71`), not in `probe-octokit.ts`, and is not exported. The captured
  GitHub body is GitHub-origin (not attacker-controlled via probe *input*), so a
  full Unicode-separator strip is not strictly required — but the body still
  flows into Sentry `extra` + pino, so apply at minimum `replace(/[\r\n]/g, " ")`
  + `.slice(0, 500)` (mirroring `github-app.ts:527`). Do NOT import the cron
  file's private helper into probe-octokit (creates a back-dependency); inline
  the minimal CR/LF strip at the capture site.
- **Fake-timer advance schedule.** The new backoff sleeps 1s then 2s; the
  existing single-retry test advances only `1_000`. Each multi-attempt test must
  advance `1_000` then `2_000` (per `BASE_DELAY_MS * 2 ** attempt`), and the
  "throws after consecutive 401s" test's `MockApp` expectation moves from 2× to
  3×. Attach the rejection handler before advancing timers (the existing test
  already does this at line 93) to avoid Node's unhandled-rejection race.
- **RequestError typing.** `@octokit/app` surfaces failures as
  `@octokit/request-error` `RequestError` (`.status`, `.response?`). Narrow with
  `"status" in err` / `"response" in err` rather than importing the class if the
  import pulls in extra surface; `OctokitResponse.headers` keys are
  lower-cased (`"x-github-request-id"`, `date`) — verified in
  `node_modules/@octokit/types/dist-types/ResponseHeaders.d.ts:5,15`.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (Section is filled above; threshold `none` with reason.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an observability + retry
hardening change to platform-owned synthetic-probe infrastructure code under
`apps/web-platform/server/`. No user-facing UI, no schema/auth/API-route change,
no regulated-data surface, no new infrastructure (pure code change against an
already-provisioned Inngest cron). Phase 2.7 GDPR gate: skipped (no
regulated-data surface; the captured `extra` is GitHub-origin API error metadata,
not founder PII). Phase 2.8 IaC gate: skipped (no new server/service/secret/
vendor). Phase 2.9 observability gate: satisfied (section above).
