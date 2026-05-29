---
title: "fix: Flagsmith getIdentityFlags timeout floods Sentry at error-level on /login"
type: fix
date: 2026-05-29
lane: single-domain
sentry_id: ac2d712121d94ad9ab154a16f6178fa7
release: web-platform@0.101.100
---

# fix: Flagsmith getIdentityFlags timeout floods Sentry at error-level on /login

## Overview

A production Sentry alert (`auth-callback-no-code-burst`, ID `ac2d712121d94ad9ab154a16f6178fa7`)
fired on `GET /login` with the exception chain:

> `TimeoutError: The operation was aborted due to timeout`
> → `Error: getIdentityFlags failed and no default flag handler was provided`

The original fix-goal framing was: *"the request fails hard because there is no default
flag handler — add one so the login page degrades gracefully."*

**Research falsifies that premise.** The login page already degrades gracefully. The Sentry
event is a *recovered-path observability mirror*, not a user-facing failure. The real defects
are (a) the recovered timeout is reported at `level: "error"` instead of `warning`, and (b)
there is no per-key debounce on the mirror, so a Flagsmith edge slowdown produces a burst of
identical error events that tripped the alert. The fix is a severity + debounce change in
`fetchRuntimeFlagsFromFlagsmith`, **not** an SDK `defaultFlagHandler`.

## Problem Statement / Motivation

### What actually happens (traced end-to-end)

1. The root layout `apps/web-platform/app/layout.tsx:48-49` calls
   `resolveIdentity(supabase)` then `getFeatureFlags(identity)` on **every** route render,
   including `/login` (anonymous → `ANON_IDENTITY`, `role: "prd"`, `orgId: null`).
2. `getFeatureFlags` → `getRuntimeSnapshot(role, orgId)`
   (`apps/web-platform/lib/feature-flags/server.ts:119-126`) → on cache miss →
   `fetchRuntimeFlagsFromFlagsmith` (`server.ts:94-117`).
3. `server.ts:103` calls `c.getIdentityFlags(...)`. The Flagsmith SDK
   (`flagsmith-nodejs@8.1.0`) issues a POST to the identities endpoint via
   `getJSONResponse → retryFetch`, which uses `AbortSignal.timeout(requestTimeoutMs)`
   (`node_modules/flagsmith-nodejs/sdk/utils.ts:82`). Our `REQUEST_TIMEOUT_SECONDS = 0.2`
   (`server.ts:11`) sets a 200ms ceiling.
4. On a slow edge response the abort fires → `fetch` rejects with `TimeoutError`
   ("The operation was aborted due to timeout"). This bubbles to the SDK's
   `getIdentityFlags` catch (`node_modules/flagsmith-nodejs/sdk/index.ts:241-247`). Because
   we do **not** configure `defaultFlagHandler`, the SDK re-throws
   `new Error('getIdentityFlags failed and no default flag handler was provided', { cause: error })`.
5. That re-thrown Error is caught by **our** `try/catch` at `server.ts:109-116`, which calls
   `reportSilentFallback(err, { feature: "feature-flags", op: "flagsmith.getIdentityFlags", ... })`
   and returns `null`.
6. `getRuntimeSnapshot` (`server.ts:123`) sees `null` and substitutes
   `runtimeEnvFallback()` (env-var mirror per ADR-038 "Fallback semantics"). The snapshot is
   cached 30s. **The page renders normally.**

So the user is unaffected. The Sentry event is produced *by* `reportSilentFallback`
(`apps/web-platform/server/observability.ts:164-203`), which mirrors to pino (hence the
event's `feature = pino-mirror` / `pino-mirror` provenance) and calls
`Sentry.captureException(err, …)`. Because `err instanceof Error`, it lands as `handled: yes`
at **`level: "error"`** — which is what makes it page-worthy and what tripped the alert.

### Two real defects

- **Severity mismatch.** A 200ms Flagsmith timeout that is *immediately recovered* by the
  env-var fallback is a degraded-but-expected path, not an error. `observability.ts`
  already provides `warnSilentFallback` (`observability.ts:211-241`) documented verbatim
  for *"a third-party timeout with a graceful fallback … worth observing but shouldn't
  count as an error."* This call site is the textbook case but uses the error-level helper.
- **No debounce → burst.** `reportSilentFallback` emits one Sentry event per call. The
  30s snapshot cache bounds repeats *per `(role, orgId)` key*, but the anon `/login` path
  is hammered by health-checks / crawlers (the Sentry request shows `curl/8.5.0`), and any
  edge slowdown lasting > a few seconds produces a burst of identical events across the
  cache-cold window. `observability.ts:267` defines `MIRROR_DEBOUNCE_MS = 5 * 60 * 1000`
  and `mirrorWithDebounce(err, ctx, userId, errorClass)` (`observability.ts:357-368`) built
  *exactly* for "a misconfigured prod or a runaway loop could fire the same silent-fallback
  condition repeatedly." This call site does not use it.

### Why NOT add `defaultFlagHandler`

The original goal proposed configuring the SDK's `defaultFlagHandler`. Adding it would make
the SDK swallow the throw and return `new Flags({ flags: {}, defaultFlagHandler })`
(`node_modules/flagsmith-nodejs/sdk/index.ts:248-252`) — meaning `flags.isFeatureEnabled(name)`
returns the handler's default for **all** runtime flags. That is *worse* than our current
env-var fallback (which mirrors actual prd-segment state per ADR-038) and it would **delete
the observability signal entirely** (our `catch` never runs, so no pino/Sentry mirror at all).
Our app-level catch + env fallback is the superior graceful-degradation mechanism and is
already in place. The fix tunes the *reporting*, it does not change the *degradation*.

## Proposed Solution

In `apps/web-platform/lib/feature-flags/server.ts`, change the single
`reportSilentFallback(...)` call in `fetchRuntimeFlagsFromFlagsmith` (`server.ts:110-114`) to
`mirrorWithDebounce(...)` at **warning** severity for the recovered-timeout/recovered-error
path, keyed for debounce.

Concretely:

1. Import `mirrorWithDebounce` (and keep the existing import path
   `@/server/observability`). `mirrorWithDebounce` internally calls `reportSilentFallback`
   (error level). To get **warning** level we instead need a debounced *warn* path — see
   the design decision in Technical Considerations below: extend observability with a
   `warnSilentFallback`-backed debounce wrapper (`mirrorWarnWithDebounce`) OR pass a
   severity into the existing debounce. The plan's chosen approach (see Technical
   Considerations) is to add a thin `mirrorWarnWithDebounce` sibling that reuses the same
   `TtlDedupMap` instance so dedup keys do not double-count across the two severities.
2. Register the `errorClass` string in the `mirrorWithDebounce` registry doc block
   (`observability.ts:253-265`): add a `feature-flags` family with
   `flagsmith:getidentityflags-timeout`.
3. Dedup key: `userId = identity-derived key` is not available at this site (anon path has
   `userId: null`), so key on the **flag cache key** instead — `${role}:${orgId ?? "__anon__"}`
   — which is the natural per-segment bucket and matches the 30s snapshot cache key shape.
   Pass it as the `userId` positional arg to the debounce helper (the helper treats it as an
   opaque in-process dedup token; it is never emitted — see `observability.ts:363`).

The net effect: a Flagsmith timeout on `/login` emits at most **one warning** per
`(role, orgId, errorClass)` per 5 minutes, the page keeps rendering via env fallback, and the
`auth-callback-no-code-burst`-style alert no longer fires on this recovered path.

## Technical Considerations

### Severity helper: reuse vs. extend

`observability.ts` today exposes:
- `reportSilentFallback` (error level, no debounce) — current call site.
- `warnSilentFallback` (warning level, no debounce).
- `mirrorWithDebounce` (debounced, **hard-wired to `reportSilentFallback` → error**,
  `observability.ts:367`).

There is no debounced *warn* helper. Two options:

| Option | Approach | Trade-off |
| --- | --- | --- |
| **A (chosen)** | Add `mirrorWarnWithDebounce(err, ctx, key, errorClass)` reusing the **same** `_mirrorDebounce` `TtlDedupMap` instance, calling `warnSilentFallback` instead of `reportSilentFallback`. | ~8 lines; keeps one dedup map so an error-class and warn-class claim for the same key cannot both fire inside the window. Mirrors the existing helper exactly. |
| B | Parameterize `mirrorWithDebounce` with a `level` arg. | Touches the existing helper's signature → all current callers must pass the arg or rely on a default; wider blast radius for a 1-call-site need. |

Decision: **Option A.** Smaller blast radius, no signature change to the existing helper,
single shared dedup map. (Final shape is open to plan-review / deepen-plan; if a reviewer
prefers B, the call-site change is identical.)

### `cq-silent-fallback-must-mirror-to-sentry`

The AGENTS.md rule `cq-silent-fallback-must-mirror-to-sentry` requires silent fallbacks to
mirror to Sentry. `warnSilentFallback`/`mirrorWarnWithDebounce` **does** mirror to Sentry
(at `level: "warning"`, `observability.ts:225-236`) — the rule is satisfied; only the
severity changes. Verify the rule's exact wording at work-time does not mandate
*error*-level specifically (it does not — it mandates *mirroring*).

### Negative-cache behaviour (no change, but confirm)

`getRuntimeSnapshot` already caches the env-fallback result for 30s (`server.ts:123-124`),
so a timeout does not re-hit Flagsmith on every request within the window for the same
`(role, orgId)`. This is correct and stays. The debounce is the *Sentry-emission* bound; the
snapshot cache is the *Flagsmith-call* bound. They are orthogonal and both wanted.

### Performance / NFR

No new network calls, no new allocations on the hot path beyond the existing
`TtlDedupMap.tryClaim` (amortized O(1), `observability.ts:315-343`). The change reduces
Sentry event volume on the degraded path.

## Research Insights (deepen-plan 2026-05-29)

### Precedent-diff: `mirrorWarnWithDebounce` (Phase 4.4 gate)

The chosen Option A adds a warn-level sibling of the existing error-level `mirrorWithDebounce`.
Precedent verified in-repo:

- **Existing helper** (`apps/web-platform/server/observability.ts:357-368`):
  ```ts
  const _mirrorDebounce = new TtlDedupMap<string>(MIRROR_DEBOUNCE_MS, MIRROR_SWEEP_INTERVAL);
  export function mirrorWithDebounce(err, ctx, userId, errorClass): void {
    if (!_mirrorDebounce.tryClaim(`${userId}:${errorClass}`, Date.now())) return;
    reportSilentFallback(err, ctx);   // ← error level
  }
  ```
- **New helper** (identical shape, one-line body diff — calls `warnSilentFallback` instead):
  ```ts
  export function mirrorWarnWithDebounce(err, ctx, key, errorClass): void {
    if (!_mirrorDebounce.tryClaim(`${key}:${errorClass}`, Date.now())) return;
    warnSilentFallback(err, ctx);     // ← warning level (observability.ts:211)
  }
  ```
  Reuses the **same** `_mirrorDebounce` instance, so the dedup window is shared across
  severities (intentional — a single key cannot fire both an error-class and a warn-class
  mirror inside the window). `warnSilentFallback` mirrors to Sentry at `level: "warning"`
  (`observability.ts:225-236`) — satisfies `cq-silent-fallback-must-mirror-to-sentry` (the
  rule text mandates mirroring pino `logger.error`/**`warn`** to Sentry; severity is not
  constrained, verified against `AGENTS.rest.md:8`).

### Collision verification (shared `_mirrorDebounce` map)

Current callers of `mirrorWithDebounce(...)` grepped 2026-05-29:
`apps/web-platform/server/attachment-pipeline.ts:162` (keys on a real `userId` +
`extract-pdf:*` errorClass) and the test file. The new call keys on
`${role}:${orgId ?? "__anon__"}` + errorClass `flagsmith:getidentityflags-timeout` — a
disjoint key space. No collision is possible; both the dedup token shape and the errorClass
prefix differ.

### Test placement

A dedicated dedup test already exists at
`apps/web-platform/test/observability-mirror-debounce.test.ts` (covers `mirrorWithDebounce`
claim/expiry/distinct-key semantics). The new `mirrorWarnWithDebounce` should get a sibling
case there asserting it (a) emits at warn level via `warnSilentFallback` and (b) dedupes on
the shared map. The feature-flags behavioural assertions (AC1-AC3) stay in
`apps/web-platform/lib/feature-flags/server.test.ts`. The server test mocks
`@/server/observability` (`server.test.ts:13-15`) — extend that mock to expose
`mirrorWarnWithDebounce` (and keep `reportSilentFallback`) so AC1's "warn-path called,
error-path not called" assertion is observable.

### Verify-the-negative pass (Phase 4.45)

- Plan claim *"`/login` already renders via env fallback"* — **confirmed**: the catch at
  `server.ts:109-116` returns `null`, and `getRuntimeSnapshot:123` substitutes
  `runtimeEnvFallback()`. No throw escapes to `app/layout.tsx`.
- Plan claim *"adding `defaultFlagHandler` deletes the observability signal"* — **confirmed**:
  with a handler set, the SDK's catch (`node_modules/flagsmith-nodejs/sdk/index.ts:248-252`)
  returns `new Flags({...})` instead of throwing, so our `server.ts` catch never runs and no
  mirror is emitted.
- Plan claim *"no new PII surface; dedup key never emitted"* — **confirmed**:
  `TtlDedupMap.tryClaim` stores the key in an in-process `Map` only (`observability.ts:306`);
  `mirrorWithDebounce`'s comment (`observability.ts:363`) states the key is "never emitted".

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing new — `/login` already renders via
  the env-var fallback regardless of this change. A regression in the change (e.g.,
  accidentally removing the `catch` or the fallback return) would surface as a 500 on the
  root layout for *every* page during a Flagsmith outage. The fix must preserve the
  `catch → return null → runtimeEnvFallback()` path byte-for-byte; only the report call
  inside the catch changes.
- **If this leaks, the user's data is exposed via:** N/A — no user data is added to the
  Sentry payload. The dedup key (`${role}:${orgId}`) is in-process only and never emitted
  (`observability.ts:363`); `orgId` is already present in the existing `extra` and is
  pseudonymized only for `userId` (none here). No new PII surface.
- **Brand-survival threshold:** `none` — the change reduces alert noise on an
  already-graceful path; no user-facing surface, no data surface.
- `threshold: none, reason: edits to apps/web-platform/server/observability.ts only add a debounced warn-level mirror sibling and adjust one feature-flags call site's report severity — no auth, secret, token, schema, or PII handling is added or changed, and the user-facing flag-resolution behavior (env-var fallback) is unchanged.`

  *(Scope-out bullet required by deepen-plan Phase 4.6 / preflight Check 6 because
  `apps/web-platform/server/observability.ts` matches the sensitive-path regex on the
  `apps/web-platform/server` prefix. The other edited file,
  `apps/web-platform/lib/feature-flags/server.ts`, does not match the regex.)*

## Observability

```yaml
liveness_signal:
  what: "Sentry warning events tagged feature=feature-flags, op=flagsmith.getIdentityFlags (degraded-path heartbeat); pino warn line mirrored to container stdout / Better Stack"
  cadence: "at most 1 per (role,orgId,errorClass) per 5 min (MIRROR_DEBOUNCE_MS); on demand when Flagsmith edge is slow"
  alert_target: "Sentry web-platform project — warning level (no auto-page; visible in issue stream)"
  configured_in: "apps/web-platform/server/observability.ts:211 (warnSilentFallback) + new mirrorWarnWithDebounce; call site apps/web-platform/lib/feature-flags/server.ts:110"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (warning level after fix); pino mirror via logger.warn"
  fail_loud: "If env-var fallback ALSO can't represent a flag, the flag resolves to its FLAG_* default (false when unset) — observable as the warning event plus the flag-off behaviour; a true hard failure (catch removed) would surface as a 500 on the root layout"

failure_modes:
  - mode: "Flagsmith edge timeout (200ms ceiling) on /login render"
    detection: "Sentry warning event feature=feature-flags op=flagsmith.getIdentityFlags; debounced to 1/5min/key"
    alert_route: "Sentry issue stream (warning) — no page; trend visible in issue volume"
  - mode: "Sustained Flagsmith outage (every request times out)"
    detection: "Steady warning cadence across all (role,orgId) keys; env-fallback serves prd-mirror state"
    alert_route: "Sentry warning volume + Better Stack pino warn rate"
  - mode: "Regression: catch/fallback removed → hard 500 on root layout"
    detection: "Sentry error (unhandled) on app/layout.tsx render; vitest regression test (AC) fails in CI"
    alert_route: "Sentry error (paging) + CI red"

logs:
  where: "Container stdout (pino) → Better Stack; Sentry web-platform project"
  retention: "Sentry default project retention; Better Stack per plan"

discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/login
  expected_output: "200"
  note: "The user-facing invariant this fix protects is that /login keeps rendering (200) even when the Flagsmith flag-fetch times out — graceful degradation via runtimeEnvFallback(). A no-SSH operator-runnable probe. The warn-level Sentry signal is asserted by the vitest suite (./node_modules/.bin/vitest run lib/feature-flags/server.test.ts test/observability-mirror-debounce.test.ts lib/feature-flags/timeout-mirror-integration.test.ts) and observed in the Sentry web-platform issue stream at warning level."
```

## Acceptance Criteria

- [x] **AC1 — Severity.** On a `getIdentityFlags` rejection (timeout or any error),
      `fetchRuntimeFlagsFromFlagsmith` reports the recovered fallback at **warning** level
      (via `warnSilentFallback` / `mirrorWarnWithDebounce`), not error level. Verified by a
      vitest test asserting the warn-path helper is called and the error-path helper is not.
- [x] **AC2 — Graceful degradation preserved.** On rejection, `getRuntimeSnapshot` still
      returns `runtimeEnvFallback()` and never throws. A vitest test makes
      `mockGetIdentityFlags` reject with a `TimeoutError`-shaped error and asserts
      `getFeatureFlags(ANON_IDENTITY)` resolves (does not reject) and returns the env-fallback
      snapshot. (Regression test for the Sentry bug.)
- [x] **AC3 — Debounce.** Repeated rejections for the same `(role, orgId)` within
      `MIRROR_DEBOUNCE_MS` produce **one** mirror emission. Vitest test: two consecutive
      cache-cold rejections for the same key → mirror helper invoked once. (Requires resetting
      the snapshot cache between calls so the second call re-enters `fetchRuntimeFlagsFromFlagsmith`.)
- [x] **AC4 — errorClass registry.** The new `errorClass` string is added to the registry
      doc block in `observability.ts` (`mirrorWithDebounce` registry, ~`observability.ts:253`)
      so the bucket is documented and cannot silently collide.
- [x] **AC5 — No `defaultFlagHandler` added to the SDK config.** `client()`
      (`server.ts:68-79`) is unchanged w.r.t. flag-handling semantics; the app-level
      catch + env fallback remains the degradation mechanism. (Guards against re-introducing
      the rejected approach.)
- [x] **AC6 — Lint/type/test green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
      and `./node_modules/.bin/vitest run lib/feature-flags/server.test.ts` pass. (Web-platform
      runs vitest exclusively — `bunfig.toml` sets `[test] pathIgnorePatterns = ["**"]`, so
      `bun test` reports "filter did not match". Use the vitest binary directly.)

## Test Scenarios

### Regression (the Sentry bug)
- Given the Flagsmith SDK `getIdentityFlags` rejects with a `TimeoutError`
  ("The operation was aborted due to timeout"), when `getFeatureFlags(ANON_IDENTITY)` is
  called (the `/login` render path), then it resolves with the env-fallback snapshot and the
  mirror is emitted at **warning** level (not error), and the call does not reject.

### Severity
- Given a rejected `getIdentityFlags`, when the catch runs, then the warn-path helper is
  invoked with `feature: "feature-flags"`, `op: "flagsmith.getIdentityFlags"` and the error
  is `instanceof Error` (so it lands as `level: "warning"` in Sentry), and
  `reportSilentFallback` (error level) is NOT invoked.

### Debounce
- Given two cache-cold rejections for the same `(role, orgId)` within 5 minutes (snapshot
  cache reset between them via `__resetFeatureFlagsForTests`), when both run, then the mirror
  helper emits exactly once.
- Given rejections for two distinct `(role, orgId)` keys, when both run, then the mirror
  helper emits twice (distinct dedup buckets).

### Edge
- Given `client()` returns `null` (no `FLAGSMITH_ENVIRONMENT_KEY`), when
  `fetchRuntimeFlagsFromFlagsmith` runs, then it returns `null` without emitting a mirror
  (unchanged behaviour — the missing-key path is not a timeout/error).

## Dependencies & Risks

- **No new dependencies.** Uses existing `flagsmith-nodejs@8.1.0` and the existing
  `observability.ts` helpers (plus one thin new sibling helper).
- **Risk: dedup map shared across severities.** Adding `mirrorWarnWithDebounce` on the same
  `_mirrorDebounce` instance means an error-class and a warn-class claim for the *same key*
  share the window. For this site there is only the warn path, so no collision; the registry
  doc (AC4) records the bucket. Deepen-plan should confirm no existing caller uses the same
  `${role}:${orgId}` key shape against `_mirrorDebounce` (grep `mirrorWithDebounce(` —
  current callers key on real `userId`, not `role:org`, so collision is structurally
  impossible).
- **Risk: severity rule.** Confirm `cq-silent-fallback-must-mirror-to-sentry` does not
  mandate error level (it mandates *mirroring*; warning mirrors satisfy it).
- **Risk: test reaching the catch twice.** The 30s snapshot cache will short-circuit the
  second call unless reset; AC3 test must call `__resetFeatureFlagsForTests()` between the two
  rejections, which also resets the Flagsmith client — re-stub `mockGetIdentityFlags` to reject
  again. Note: `__resetFeatureFlagsForTests` does NOT reset the observability dedup map; the
  test must also call `__resetMirrorDebounceForTests()` (and the warn-debounce reset if a
  separate map is ever introduced) to isolate from prior tests.

## References & Research

- **Call site (edit target):** `apps/web-platform/lib/feature-flags/server.ts:94-117`
  (`fetchRuntimeFlagsFromFlagsmith`); report call at `:110-114`; client config at `:68-79`;
  snapshot cache at `:119-126`; timeout constant at `:11`.
- **Render path:** `apps/web-platform/app/layout.tsx:48-49` (`resolveIdentity` +
  `getFeatureFlags` on every route incl. `/login`). `/login` page:
  `apps/web-platform/app/(auth)/login/page.tsx`.
- **Observability helpers (edit target):** `apps/web-platform/server/observability.ts` —
  `reportSilentFallback:164`, `warnSilentFallback:211`, `mirrorWithDebounce:357`,
  `MIRROR_DEBOUNCE_MS:267`, `TtlDedupMap:305`, registry doc block `:253-265`,
  `__resetMirrorDebounceForTests:375`.
- **SDK behaviour (read-only evidence):** `flagsmith-nodejs@8.1.0` —
  `getIdentityFlags` re-throw `node_modules/flagsmith-nodejs/sdk/index.ts:241-247`;
  `getJSONResponse → retryFetch` `:343-382`; `AbortSignal.timeout`
  `node_modules/flagsmith-nodejs/sdk/utils.ts:82`. The wrapped Error message
  `'getIdentityFlags failed and no default flag handler was provided'` is `index.ts:244`.
- **Existing test:** `apps/web-platform/lib/feature-flags/server.test.ts` (mocks
  `flagsmith-nodejs` and `@/server/observability`; will need the observability mock extended
  to spy the warn-path helper).
- **ADR:** `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
  — "Fallback semantics (load-bearing)" §71-82 (env var mirrors prd-segment state;
  fallback on SDK error/timeout/missing key). `ADR-043` (per-org targeting).
- **Test runner:** `apps/web-platform/package.json:15` (`"test": "vitest"`);
  `apps/web-platform/bunfig.toml` `[test] pathIgnorePatterns = ["**"]` (#1469) — bun test
  blocked; use `./node_modules/.bin/vitest run <path>`.
- **Open code-review overlap:** None (queried `gh issue list --label code-review --state open`
  for bodies containing `feature-flags/server` → no matches, 2026-05-29).
