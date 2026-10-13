---
title: "Tasks — fix Flagsmith getIdentityFlags timeout mirror severity + debounce"
plan: knowledge-base/project/plans/2026-05-29-fix-getidentityflags-timeout-mirror-severity-and-debounce-plan.md
lane: single-domain
date: 2026-05-29
---

# Tasks

## Phase 0 — Preconditions

- [x] 0.1 Re-read `apps/web-platform/server/observability.ts:357-377` (`mirrorWithDebounce`,
      `_mirrorDebounce`, `__resetMirrorDebounceForTests`) and `:211-241` (`warnSilentFallback`).
- [x] 0.2 Re-read `apps/web-platform/lib/feature-flags/server.ts:94-126` (catch + snapshot
      cache) and `:13-15` mock contract in `server.test.ts`.
- [x] 0.3 Confirm `cq-silent-fallback-must-mirror-to-sentry` (AGENTS.rest.md) permits warn-level
      mirroring (it does — text says `logger.error`/`warn`).
- [x] 0.4 Preflight Check 6 dry sanity: edited files are `lib/feature-flags/server.ts`
      (not sensitive) + `server/observability.ts` (sensitive → scope-out bullet present in plan).

## Phase 1 — RED (write failing tests)

- [x] 1.1 In `apps/web-platform/test/observability-mirror-debounce.test.ts`, add a case for the
      new `mirrorWarnWithDebounce`: emits via `warnSilentFallback` (warn level), dedupes on the
      shared `_mirrorDebounce` map per `${key}:${errorClass}`, distinct keys emit separately.
- [x] 1.2 In `apps/web-platform/lib/feature-flags/server.test.ts`, extend the
      `@/server/observability` mock (`:13-15`) to spy `mirrorWarnWithDebounce` AND
      `reportSilentFallback`.
- [x] 1.3 AC2 regression test: `mockGetIdentityFlags` rejects with a `TimeoutError`-shaped
      error; assert `getFeatureFlags(ANON_IDENTITY)` resolves (does not reject) and returns the
      env-fallback snapshot.
- [x] 1.4 AC1 severity test: on rejection, warn-path helper called with
      `feature: "feature-flags"`, `op: "flagsmith.getIdentityFlags"`; `reportSilentFallback`
      NOT called.
- [x] 1.5 AC3 debounce test: two cache-cold rejections for the same `(role, orgId)` (reset
      snapshot cache via `__resetFeatureFlagsForTests()` AND debounce map via
      `__resetMirrorDebounceForTests()` between setup) → warn helper invoked once; distinct
      keys → invoked twice.
- [x] 1.6 Run `./node_modules/.bin/vitest run lib/feature-flags/server.test.ts test/observability-mirror-debounce.test.ts` from `apps/web-platform` — confirm RED.

## Phase 2 — GREEN (implement)

- [x] 2.1 Add `mirrorWarnWithDebounce(err, ctx, key, errorClass)` to
      `apps/web-platform/server/observability.ts` (reuse `_mirrorDebounce`, call
      `warnSilentFallback`). Mirror the `mirrorWithDebounce` shape exactly.
- [x] 2.2 Register the new errorClass `flagsmith:getidentityflags-timeout` (family
      `feature-flags`) in the registry doc block (~`observability.ts:253-265`).
- [x] 2.3 In `apps/web-platform/lib/feature-flags/server.ts`, change the
      `reportSilentFallback(...)` call in `fetchRuntimeFlagsFromFlagsmith` (`:110-114`) to
      `mirrorWarnWithDebounce(err, { feature: "feature-flags", op: "flagsmith.getIdentityFlags", extra: { role, orgId } }, \`${role}:${orgId ?? "__anon__"}\`, "flagsmith:getidentityflags-timeout")`.
      Update the import. Leave the `return null` + `runtimeEnvFallback()` path untouched.
- [x] 2.4 Confirm `client()` (`server.ts:68-79`) is unchanged — NO `defaultFlagHandler` added (AC5).
- [x] 2.5 Run the two test files — confirm GREEN.

## Phase 3 — Verify

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] 3.2 `./node_modules/.bin/vitest run lib/feature-flags/server.test.ts test/observability-mirror-debounce.test.ts` — all pass (AC6).
- [x] 3.3 Grep guard: `grep -n "defaultFlagHandler" apps/web-platform/lib/feature-flags/server.ts`
      returns nothing (AC5).
- [x] 3.4 Grep guard: the feature-flags catch no longer calls `reportSilentFallback` (AC1).
