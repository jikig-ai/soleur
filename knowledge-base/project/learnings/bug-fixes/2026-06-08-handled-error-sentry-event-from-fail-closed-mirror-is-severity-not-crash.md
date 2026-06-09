# A `handled: yes` error-level Sentry event from a graceful fail-closed mirror is a severity-calibration bug, not a crash

## Problem

Production Sentry issue `d87684243c554592953ea9148f46f4e6` (web-platform, `level: error`, **`handled: yes`**, feature tag `pino-mirror`) fired `RuntimeAuthError: Authentication unavailable; retry shortly` on `GET /dashboard/settings/scope-grants?_rsc=…` (an RSC prefetch). The issue prose framed it as an unhandled crash and prescribed the fix: "handle the unavailable-auth state gracefully (e.g., redirect/return rather than throwing)."

## Root cause (the prose was wrong)

The page was **not** throwing an unhandled error. PR #4949 relocated the Concierge `BashAutonomousToggle` onto this page, adding a `resolveBashAutonomous(user.id)` call on every render. That helper mints a founder-scoped Supabase JWT (`getFreshTenantClient`); a transient mint blip (GoTrue 429, RPC hiccup, missing secret) throws `RuntimeAuthError`.

`resolveBashAutonomous` **already** caught it, failed closed to the safe `false` (approval gate stays ON), and **deliberately** mirrored to Sentry via `reportSilentFallback` — which calls `captureException` at the default `level: "error"`. The Sentry event *is* that mirror (hence `handled: yes`), not an unhandled propagation. The page renders correctly; the user sees nothing wrong. The real defect: a fully-recovered, fail-closed transient was emitted at `error` level, polluting the error budget.

## Solution

Per-cause severity split in the existing catch block — do NOT add a redirect (that would bounce the founder off their own settings page on a transient blip):

```ts
const code = mapRuntimeAuthCauseToErrorCode(err.cause);
const emit = err.cause === "jwt_mint" ? warnSilentFallback : reportSilentFallback;
emit(err, { feature: "resolve-bash-autonomous", op: "tenant-read",
  extra: { userId, workspaceId: workspaceId ?? null, code },
  message: `founder tenant auth unavailable (${code}); fail-closed false (approval gate ON)` });
return false;
```

`jwt_mint` (transient) → `warnSilentFallback` (warning, off the error budget); `denied_jti` (session revoked) and `rotation` (rate-ceiling) stay `reportSilentFallback` (error) so on-call keeps the actionable signal. Both carry a queryable `extra.code` via the existing `mapRuntimeAuthCauseToErrorCode` mapper.

## Key Insight

`handled: yes` on an error-level Sentry event is the tell: a `try/catch` deliberately captured it, so the question is **"is `error` the right level?"** not "why is it crashing?". When a degraded path is fully recovered and fail-closed, the fix is `warn`-vs-`error` calibration (per-cause when the error carries a cause discriminant), never a behavioral change like a redirect. Read the throw→catch→mirror chain in code before trusting a Sentry alert's prose diagnosis; the stack frames in the event are the *captured* throw stack, not an uncaught-exception stack. Caveat: a `warning`-level downgrade still trips Sentry alert *rules* that match on tags rather than level (see [[2026-05-27-sentry-warning-level-still-triggers-alert-rules]]) — confirm the rule keys off level/error-budget, not just `feature`.

Related: [[2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods]] (same "recovered fallback shouldn't be error-level" family), [[2026-06-01-loud-breadcrumb-over-warns-when-guarded-state-is-default-steady-state]].

## Session Errors

1. **`npm run -w apps/web-platform typecheck` → `npm ERR! No workspaces found`.** The plan's AC6 and `tasks.md` Phase 3 prescribed this form, but the repo-root `package.json` declares no `workspaces` field. Recovery: ran `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the app package's real `typecheck` script). **Prevention:** already documented in [[2026-05-13-npm-workspaces-flag-fails-without-root-workspaces-declaration]] and [[2026-06-05-web-platform-lint-gate-is-non-functional-tsc-vitest-are-authoritative]]; the recurrence is that `/soleur:plan` keeps generating the `-w` form into tasks.md. Routing a one-line correction to the plan skill's Sharp Edges so generated typecheck steps use `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Tags
category: bug-fixes
module: web-platform/observability
```
