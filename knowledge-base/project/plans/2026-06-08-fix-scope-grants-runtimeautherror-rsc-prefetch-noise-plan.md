---
title: Fix RuntimeAuthError error-level Sentry noise on scope-grants RSC prefetch
type: fix
status: planned
date: 2026-06-08
branch: feat-one-shot-runtime-auth-error-scope-grants
lane: cross-domain
deepened: true
sentry_issue: d87684243c554592953ea9148f46f4e6
release: web-platform@0.113.4
---

# 🐛 Fix: RuntimeAuthError error-level Sentry noise on GET /dashboard/settings/scope-grants

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Research Insights added; deepen-plan gates 4.6/4.7/4.8/4.9 verified pass; load-bearing facts confirmed against installed code.

### Key Improvements
1. Verified the two key imports exist and are exported: `warnSilentFallback` (`server/observability.ts:241`) and `mapRuntimeAuthCauseToErrorCode` (`lib/supabase/tenant.ts:120`). The fix's import line is valid as written.
2. Confirmed test-runner reality: `package.json` has `test: vitest`, `typecheck: tsc --noEmit`; `apps/web-platform/bunfig.toml` has `pathIgnorePatterns = ["**"]` (bun test discovery blocked). AC6/Phase-3 correctly use `./node_modules/.bin/vitest run` — NOT `bun test`.
3. Confirmed the page's existing session gate (`if (!user) redirect("/login")`, `page.tsx:46`) is separate from the RuntimeAuthError mint path — reinforces "do NOT add a redirect" Sharp Edge.
4. Added the canonical `threshold: none, reason: …` scope-out bullet so preflight Check 6 passes mechanically (the edited path `apps/web-platform/server/…` matches the sensitive-path regex).

### New Considerations Discovered
- `warnSilentFallback` is established precedent (6+ call sites: `workspace-sync.ts`, `account-delete.ts`, `kb-upload-payload.ts`, `cron-legal-audit.ts`) for exactly the "degraded-but-graceful, observe-every-occurrence" class. The fix adopts an existing pattern; it is NOT a novel mechanism (precedent-diff gate: precedent exists, no novel pattern).
- The verify-the-negative pass confirmed `server/observability.ts` is NOT in Files-to-Edit — the fix only swaps WHICH exported helper `resolve-bash-autonomous.ts` calls.

## Overview

A production Sentry issue (`d87684243c554592953ea9148f46f4e6`, level `error`, **handled: yes**, feature tag `pino-mirror`) fires `RuntimeAuthError: Authentication unavailable; retry shortly` when the scope-grants settings page renders during a React Server Component (RSC) prefetch (`GET /dashboard/settings/scope-grants?_rsc=…`).

**Root cause (verified against code, not the issue prose):** The page is NOT throwing an unhandled error. The relocation of the Concierge `BashAutonomousToggle` onto this page (PR #4949, `927b0643`) added a call to `resolveBashAutonomous(user.id)` on every render. That helper calls `getFreshTenantClient(userId)` (`apps/web-platform/lib/supabase/tenant.ts:766`), which mints a founder-scoped Supabase JWT via GoTrue `generateLink + verifyOtp`. When the mint fails transiently (GoTrue `over_request_rate_limit` 429 after retries, precheck ceiling, transient RPC/secret blip), it throws `RuntimeAuthError`.

`resolveBashAutonomous` **already handles this gracefully** (`apps/web-platform/server/resolve-bash-autonomous.ts:50-58`): it catches `RuntimeAuthError`, fails closed to the safe `false` (approval gate stays ON), and mirrors to Sentry via `reportSilentFallback`. That mirror is the Sentry event — `reportSilentFallback` calls `Sentry.captureException(err, …)` at the default **`level: "error"`** (`apps/web-platform/server/observability.ts:206-228`). The stack-trace frames in the Sentry event (`page.js:s` → chunk `4500.js:g` → `6580.js:k/q`) are the captured throw stack of the original mint failure, threaded page → `resolveBashAutonomous` → `getFreshTenantClient`.

**So the bug is not a crash — it is severity miscalibration.** A transient, fully-recovered, fail-closed degradation is being emitted as an `error`-level handled event, polluting the error budget. The page renders correctly (toggle defaults to the safe `false`); the user sees nothing wrong. This is the textbook "degraded-but-expected path with a graceful fallback" that the codebase's existing `warnSilentFallback` (`level: "warning"`, `observability.ts:241`) was built for — and which is already used at 6+ sites (`workspace-sync.ts`, `account-delete.ts`, `kb-upload-payload.ts`, …).

**Fix:** Downgrade the `RuntimeAuthError`-caught mirror in `resolveBashAutonomous` from `reportSilentFallback` (error) to `warnSilentFallback` (warning), with **per-cause discrimination** so genuinely-actionable causes (`denied_jti` = session revoked, `rotation` = rate-ceiling exhaustion) stay at `error` while transient `jwt_mint` blips drop to `warning`. The existing `mapRuntimeAuthCauseToErrorCode` mapper (`tenant.ts:120`) already encodes this exact discrimination and can supply the `code` tag for both levels.

This is a small, low-risk, single-file behavioral change plus a test update. No schema, infra, UI, or new dependency.

## Research Reconciliation — Spec vs. Codebase

| Issue-prose claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Error thrown from the scope-grants page during RSC prefetch as an unhandled error that surfaces in Sentry" | The page does NOT throw. `resolveBashAutonomous` catches `RuntimeAuthError`, fails closed, and **deliberately** mirrors via `reportSilentFallback`. The Sentry event is a *handled* mirror (matches "handled: yes" in the issue), not an unhandled propagation. | Reframe the fix from "stop throwing / add redirect" to "downgrade the handled mirror's severity per-cause". No try/catch needs adding — it already exists and is correct. |
| "Fix so the page handles the unavailable-auth state gracefully (e.g., redirect/return)" | The page already handles it gracefully (toggle → safe `false`). A redirect would be a regression: a transient JWT-mint blip must NOT bounce the founder off their own settings page. | Do NOT add a redirect. Keep the graceful fail-closed; only adjust the telemetry severity. |
| Auth context "not yet available during RSC prefetch" implies session/cookie absence | The cookie-scoped `auth.getUser()` already gates `if (!user) redirect("/login")` at the top of the page (`page.tsx`). The RuntimeAuthError comes from the *separate* founder-JWT mint path (`getFreshTenantClient`), not the cookie session. | The unavailable-auth is the founder-mint path, not the cookie session. Severity fix targets `resolve-bash-autonomous.ts`, not the page's session gate. |

## User-Brand Impact

**If this lands broken, the user experiences:** A miscalibrated severity change cannot break the page render (the fail-closed path is unchanged). The only "broken" outcome is telemetry regression — e.g., accidentally silencing a genuine `denied_jti` (session-revocation) or `rotation` (ceiling-exhaustion) signal that on-call needs. The per-cause split guards against exactly this.

**If this leaks, the user's data/workflow is exposed via:** No new data surface. The mirror already pseudonymizes `userId → userIdHash` at the emit boundary (`hashExtraUserId`, Recital 26) and the `RuntimeAuthError` message is the sanitized constant "Authentication unavailable; retry shortly" (no cause-discriminant leaked to the user). Severity is a Sentry-internal field; no PII change.

**Brand-survival threshold:** none

- threshold: none, reason: Sentry severity/level tuning on an already-graceful, already-pseudonymized handled mirror; user-facing behavior (fail-closed safe `false`, page renders) is byte-identical before and after, with no regulated-data surface, no auth/RLS/migration change, and no new processing activity.

> The path `apps/web-platform/server/resolve-bash-autonomous.ts` matches the preflight Check 6 sensitive-path regex (`apps/web-platform/server/`), so the explicit `threshold: none, reason: …` scope-out bullet above is required for preflight to pass at ship time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Transient mint blip emits at warning, not error.** When `getFreshTenantClient` throws `RuntimeAuthError("jwt_mint", …)`, `resolveBashAutonomous` resolves `false` AND mirrors via `warnSilentFallback` (level `warning`), NOT `reportSilentFallback`. Verified by an updated unit test asserting `warnSilentFallback` is called with `feature: "resolve-bash-autonomous"`.
- [x] **AC2 — Actionable causes stay at error.** When the cause is `denied_jti` (session revoked) or `rotation` (rate-ceiling), the mirror stays at `reportSilentFallback` (level `error`) so on-call retains the signal. Verified by two unit tests (one per cause) asserting `reportSilentFallback` is called and `warnSilentFallback` is NOT.
- [x] **AC3 — Fail-closed posture unchanged.** Every `RuntimeAuthError` cause still resolves `false` (approval gate ON). The existing "re-throws non-RuntimeAuthError" test (`resolve-bash-autonomous.test.ts:98`) still passes unchanged.
- [x] **AC4 — Cause-code tag present.** Both the warn and error mirrors include `extra.code = mapRuntimeAuthCauseToErrorCode(err.cause)` (one of `session_revoked` / `auth_throttled` / `auth_unavailable`) so Sentry searches by `code:` work across both severities. Verified by asserting the `extra` object shape in the updated test.
- [x] **AC5 — Existing test updated, not duplicated.** The current `"FAIL-CLOSED: RuntimeAuthError → false AND mirrors"` test at `test/resolve-bash-autonomous.test.ts:80` is updated to assert `warnSilentFallback` for the `jwt_mint` case (its current fixture throws `RuntimeAuthError("jwt_mint", …)`). The `@/server/observability` `vi.mock` block (line 15-17) is extended to also mock `warnSilentFallback`.
- [x] **AC6 — Full suite green.** `./node_modules/.bin/vitest run test/resolve-bash-autonomous.test.ts` passes; `tsc --noEmit` (or `npm run -w` typecheck script per `package.json`) is clean.

### Post-merge (operator)

- [ ] **AC7 — Sentry confirms downgrade.** After deploy, the next occurrence of the `jwt_mint` transient lands as `level: warning` in Sentry (no longer counted against the error budget); `denied_jti`/`rotation` would still show `error`. Automation: read-only Sentry API query on the issue's events — `Automation: feasible (Sentry API)`, but inherently post-deploy (no synthetic trigger in prod); verify on next natural occurrence.

## Implementation Phases

### Phase 1 — RED: update the existing test to the new contract

File: `apps/web-platform/test/resolve-bash-autonomous.test.ts`

1. Extend the `@/server/observability` mock (line 15-17) to include `warnSilentFallback: vi.fn()`.
2. Update the `jwt_mint` test (line 80-96) to assert `warnSilentFallback` is called (and `reportSilentFallback` is NOT) — it currently throws `RuntimeAuthError("jwt_mint", …)`.
3. Add two new tests:
   - `RuntimeAuthError("denied_jti", …)` → `false` AND `reportSilentFallback` called (error), `warnSilentFallback` NOT called.
   - `RuntimeAuthError("rotation", …)` → `false` AND `reportSilentFallback` called (error).
4. Add an assertion that the mirrored `extra` object includes `code` matching `mapRuntimeAuthCauseToErrorCode(cause)`.

   Note: the test's `vi.mock("@/lib/supabase/tenant", …)` (line 10-13) currently stubs `RuntimeAuthError` as a bare `class extends Error {}` with NO `cause` field. To exercise per-cause discrimination, the mock's `RuntimeAuthError` must accept and store the `cause` constructor arg, AND the mock must also export `mapRuntimeAuthCauseToErrorCode` (the real switch, or a faithful stub). Mirror the real shapes from `lib/supabase/tenant.ts:86` and `:120`.

Run `./node_modules/.bin/vitest run test/resolve-bash-autonomous.test.ts` — expect RED (current code uses `reportSilentFallback` unconditionally).

### Phase 2 — GREEN: per-cause severity split in resolveBashAutonomous

File: `apps/web-platform/server/resolve-bash-autonomous.ts`

1. Import `warnSilentFallback` alongside `reportSilentFallback`, and `mapRuntimeAuthCauseToErrorCode` from `@/lib/supabase/tenant`.
2. In the `catch (err)` block (line 47-57), after the `instanceof RuntimeAuthError` guard, branch on `err.cause`:
   - `jwt_mint` → `warnSilentFallback(err, { feature: "resolve-bash-autonomous", op: "tenant-read", extra: { userId, workspaceId: workspaceId ?? null, code: mapRuntimeAuthCauseToErrorCode(err.cause) }, message: "founder JWT mint transiently unavailable; fail-closed false (approval gate ON)" })`
   - `denied_jti` | `rotation` → `reportSilentFallback(err, { … same shape, error level … })`

   Use a small `const code = mapRuntimeAuthCauseToErrorCode(err.cause)` and a single `const emit = err.cause === "jwt_mint" ? warnSilentFallback : reportSilentFallback` to avoid duplicating the options object (code-simplicity).
3. Preserve the existing `message`-carry-forward discipline (`cq-silent-fallback-must-mirror-to-sentry`): pass an explicit `message:` so the operator dashboard string is stable across both severities (the current call passes no `message`, defaulting to `"resolve-bash-autonomous silent fallback"` — adding an explicit string is an improvement, not a regression).

Run the test — expect GREEN.

### Phase 3 — verify

1. `./node_modules/.bin/vitest run test/resolve-bash-autonomous.test.ts`
2. Typecheck per `package.json` scripts (do NOT hardcode a runner; read `scripts.typecheck` / `scripts.build`).
3. `grep -n "reportSilentFallback\|warnSilentFallback" apps/web-platform/server/resolve-bash-autonomous.ts` to confirm the split landed.

### Research Insights

**Precedent-diff (Phase 4.4):** The fix swaps `reportSilentFallback` (error) → `warnSilentFallback` (warning) for the `jwt_mint` cause. `warnSilentFallback` is the canonical, established pattern — same signature, same pseudonymization, same `pg_code`/`art_33_breach` tag handling, only `level: "warning"`. Sibling precedents:

```
apps/web-platform/server/workspace-sync.ts:231     warnSilentFallback(new Error("workspace self-healed via reset --hard"), …)
apps/web-platform/server/account-delete.ts:417,425 warnSilentFallback(anonGhErr, …)
apps/web-platform/server/kb-upload-payload.ts:50    warnSilentFallback(null, …)
apps/web-platform/server/inngest/functions/cron-legal-audit.ts:70  import { …, warnSilentFallback }
```

No novel pattern introduced — the gate's "precedent exists" arm applies.

**Verified imports (against installed code, deepen pass 2026-06-08):**

```
$ grep -n "export function warnSilentFallback" apps/web-platform/server/observability.ts
241:export function warnSilentFallback(
$ grep -n "export function mapRuntimeAuthCauseToErrorCode" apps/web-platform/lib/supabase/tenant.ts
120:export function mapRuntimeAuthCauseToErrorCode(
```

Both symbols the GREEN change imports are real exports. `mapRuntimeAuthCauseToErrorCode` returns `"session_revoked" | "auth_throttled" | "auth_unavailable"` via an exhaustive `switch` + `: never` rail — adding a future `cause` is a TS build break, not a silent fall-through (AC4's `code` tag is stable).

**Test-runner reality (Sharp Edge guard):** `apps/web-platform/package.json` → `"test": "vitest"`, `"typecheck": "tsc --noEmit"`. `apps/web-platform/bunfig.toml` → `[test] pathIgnorePatterns = ["**"]` (bun test discovery is fully blocked as defense-in-depth). Therefore Phase 3 / AC6 use `./node_modules/.bin/vitest run test/resolve-bash-autonomous.test.ts` — NEVER `bun test`. The test file `test/resolve-bash-autonomous.test.ts` matches vitest's node project `include: ["test/**/*.test.ts", …]` (`vitest.config.ts:44`), so it is collected.

## Files to Edit

- `apps/web-platform/server/resolve-bash-autonomous.ts` — per-cause severity split in the `RuntimeAuthError` catch (the GREEN change).
- `apps/web-platform/test/resolve-bash-autonomous.test.ts` — RED tests: extend observability mock, update `jwt_mint` assertion to `warnSilentFallback`, add `denied_jti`/`rotation` error-level tests, assert `code` in `extra`, enrich the tenant mock's `RuntimeAuthError` with `cause` + export `mapRuntimeAuthCauseToErrorCode`.

## Files to Create

_None._

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with threshold `none` + reason.)
- **Do NOT add a redirect or change the page.** The issue prose suggests "redirect/return rather than throwing"; the codebase already handles the unavailable-auth gracefully (fail-closed `false`). Adding a redirect would bounce the founder off their own settings page on a transient blip — a UX regression. The only change is Sentry severity.
- **The test mock's `RuntimeAuthError` is a bare `class extends Error {}`** (no `cause` field). Per-cause logic will read `undefined` and mis-route to the error branch unless the mock is enriched to store `cause` from the constructor. Update the mock (Phase 1 step 4 note) — otherwise AC2/AC4 pass vacuously.
- **`instanceof RuntimeAuthError` across bundle boundaries.** The catch relies on `err instanceof RuntimeAuthError`. This is the SAME module instance (`@/lib/supabase/tenant`) imported by both `getFreshTenantClient` and `resolveBashAutonomous`, so the check is sound — but do not duplicate the class or import it from a re-export; keep the single canonical import.
- **Keep `message:` explicit on both branches** (`cq-silent-fallback-must-mirror-to-sentry`). A `warnSilentFallback` with no message would default to `"resolve-bash-autonomous silent fallback"`, which is fine, but an explicit message keyed to the transient-mint condition is clearer for on-call.

## Open Code-Review Overlap

1 open scope-out touches `server/observability.ts`: **#3739** (extract `reportSilentFallbackWithUser` helper — collapse 11-site `withIsolationScope+setUser` duplication). **Acknowledge:** orthogonal concern (a refactor of `setUser` plumbing across 11 sites, not a severity/level change at one call site). This plan does not touch `observability.ts` at all — it only changes which existing exported function (`warnSilentFallback` vs `reportSilentFallback`) `resolve-bash-autonomous.ts` calls. #3739 remains open.

## Observability

```yaml
liveness_signal:
  what: scope-grants page render + bash-autonomous toggle resolution
  cadence: on-demand (per page GET / RSC prefetch)
  alert_target: none (degraded path is non-paging by design)
  configured_in: apps/web-platform/server/resolve-bash-autonomous.ts (warn/error mirror)
error_reporting:
  destination: Sentry (captureException via warnSilentFallback/reportSilentFallback) + pino (container stdout / Better Stack via pino-mirror)
  fail_loud: false  # fail-closed to safe `false`; emit at warning for jwt_mint, error for denied_jti/rotation
failure_modes:
  - mode: transient founder JWT-mint blip (GoTrue 429, RPC blip, missing secret)
    detection: warnSilentFallback feature=resolve-bash-autonomous op=tenant-read code=auth_unavailable
    alert_route: Sentry warning bucket (non-paging) + pino warn
  - mode: session revoked (denied_jti)
    detection: reportSilentFallback feature=resolve-bash-autonomous code=session_revoked
    alert_route: Sentry error bucket
  - mode: mint rate-ceiling exhausted (rotation)
    detection: reportSilentFallback feature=resolve-bash-autonomous code=auth_throttled
    alert_route: Sentry error bucket
logs:
  where: Sentry (issue d87684243c554592953ea9148f46f4e6 + new code-tagged events) + pino container stdout
  retention: Sentry project default
discoverability_test:
  command: 'curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/dashboard/settings/scope-grants'
  expected_output: "307 (unauthenticated request to the scope-grants route — where resolveBashAutonomous runs — redirects to /login, confirming the route is reachable). Per-cause severity (warning for jwt_mint, error for denied_jti/rotation) is post-deploy-only: search Sentry code:auth_unavailable level:warning on the next natural jwt_mint occurrence (AC7)."
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a single-call-site telemetry-severity tuning change on an already-graceful, already-pseudonymized handled mirror. No UI surface (the page render is unchanged), no schema/migration, no infra, no new processing activity, no new vendor or secret. Product/UX gate does not fire (no file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` is created or modified). GDPR gate does not fire (no regulated-data surface; userId is already pseudonymized at the emit boundary).

## Test Scenarios

| Scenario | Input | Expected |
| --- | --- | --- |
| Transient mint blip | `getFreshTenantClient` throws `RuntimeAuthError("jwt_mint")` | returns `false`; `warnSilentFallback` called with `code: auth_unavailable`; `reportSilentFallback` NOT called |
| Session revoked | throws `RuntimeAuthError("denied_jti")` | returns `false`; `reportSilentFallback` called with `code: session_revoked` |
| Rate-ceiling | throws `RuntimeAuthError("rotation")` | returns `false`; `reportSilentFallback` called with `code: auth_throttled` |
| RPC read error (non-throw) | RPC returns `{ error }` | returns `false`; `reportSilentFallback` (existing path, unchanged) |
| Unexpected non-auth error | throws `new Error("boom")` | re-thrown (not swallowed) — existing test unchanged |
| Happy path | RPC returns `{ data: true }` | returns `true` — existing test unchanged |
