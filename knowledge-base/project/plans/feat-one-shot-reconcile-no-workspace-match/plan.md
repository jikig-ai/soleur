---
title: "fix: downgrade reconcile no-workspace-match Sentry severity to warning"
type: fix
lane: single-domain
brand_survival_threshold: none
date: 2026-05-29
related_sentry: github-c8bb0ef6-5b4b-11f1-9e36-15b1cdbe4fa2
---

# Fix: Reconcile-on-Push "no workspace matched" Surfaces as Sentry Error Instead of Expected-Skip Warning

## Overview

The Inngest function `workspace-reconcile-on-push` (fnId `workspace-reconcile-on-push`, event `platform/workspace.reconcile.requested`) is logging an **error-level** Sentry event — `Error: no workspace matched (installation_id, repo)` (Sentry event `github-c8bb0ef6-5b4b-11f1-9e36-15b1cdbe4fa2`, release `web-platform@0.101.100`, `handled=yes`, `feature=pino-mirror`) — for a condition that is, by design, an **expected, non-actionable no-op**: a GitHub push webhook arriving for an `(installation_id, repo)` pair that has zero connected workspaces (app uninstalled, repo not yet onboarded, two-users-same-fork where one disconnected, or a stale/replayed webhook).

**The code is already a graceful skip — it does not throw.** Contrary to the initial bug framing ("looks up a workspace... finds no match, then throws"), the handler at `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:131-140` calls `reportSilentFallback(...)` and `return { ok: false, reason: "no-workspace-match" }`. No `throw`, no burned retry. The `handled=yes` Sentry tag confirms this is a captured report, not an uncaught exception.

**The actual root cause is the call site uses `reportSilentFallback` (error level) for an expected condition, when a warn-level sibling already exists.** Verified at `observability.ts:164-203`: `reportSilentFallback` always calls `logger.error(...)` and, for the `Error` branch, `Sentry.captureException(err, ...)` at error level by construction — correct for actionable failures, wrong for an expected skip. **There is already a `warnSilentFallback` (`observability.ts:211-241`)** with the identical `SilentFallbackOptions` contract that emits `logger.warn(...)` + `Sentry.captureException(err, { level: "warning", ... })` / `captureMessage(..., { level: "warning" })`. Its docstring: *"use for degraded-but-expected paths ... where every occurrence is worth observing but shouldn't count as an error."* It is already in production use (`account-delete.ts:401,409`, `kb-upload-payload.ts:50`, `kb-preview-metadata.ts:69,110,125`).

**The fix is therefore a one-symbol swap, not a helper change:** call `warnSilentFallback` instead of `reportSilentFallback` at the no-match call site (and add a warn-level mirror to the schema-deadletter drain, which currently emits nothing). No new option, no change to the 40+ existing `reportSilentFallback` callers, no risk to the shared helper. (The earlier draft's premise — "extend `reportSilentFallback` with a `severity` param" — was over-engineering; the warn-level variant already exists. The `severity: "breach_attempt"`/`level: "fatal"` strings elsewhere in the file belong to `mirrorP0Deduped`/`mirrorCrossTenantViolation`, different functions.) Brand-survival threshold: **none** (one Inngest function file; swaps which observability helper two expected-drain sites call).

## Research Reconciliation — Spec vs. Codebase

The original bug report and the first planning draft were built on a file tree that does not exist in this repo, and the second draft assumed a `severity` option that the helper does not have. Both sets of divergences are recorded so no downstream phase inherits the fiction.

| Claim (bug report / earlier drafts) | Codebase reality (verified) | Plan response |
|---|---|---|
| File at `web-platform/src/lib/inngest/functions/...` | Real path: `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` (259 lines) | Use real path throughout. |
| Handler "throws" on no-match | Calls `reportSilentFallback(...)` then `return { ok:false, reason:"no-workspace-match" }` — no throw (`:131-140`) | Root cause re-derived. |
| `retries: 3`; consider `NonRetriableError` | `createFunction` config is `retries: 1` (`:255`); no-match never throws → never retries | Retry framing dropped. |
| Separate `workspace-resolver.ts` with a camelCase mapping bug; `resolveWorkspaceForReconcile` returns `null` | Resolution is an inline Supabase query in the handler (`.from("workspaces").select("id").eq(...)`, `:107-119`). `@/server/workspace-resolver` exports only `workspacePathForWorkspaceId` (a path builder) | Resolver-bug item dropped — fiction. |
| Telemetry via `recordReconcileOutcome` / `ReconcileOutcome` union (dead code to wire) | No such module/symbol. Observability = `reportSilentFallback` (`@/server/observability`) + `appendKbSyncRow` (`@/server/session-sync`) | Telemetry-wiring item dropped. |
| **Fix = pass `severity: "warning"` to `reportSilentFallback`** (draft 2) | No `severity` field exists, BUT a `warnSilentFallback` sibling already exists (`observability.ts:211-241`) with the same contract at `level: "warning"`, already used at 7+ sites | **No helper change.** Swap the call to the existing `warnSilentFallback`. |
| Test runner is bun / empty package.json | `apps/web-platform/package.json:15` `"test": "vitest"`; `bunfig.toml` blocks bun test discovery (`pathIgnorePatterns=["**"]`, #1469). Real test: `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` (vitest, `vi.mock`) | Test plan rewritten for **vitest**; extend the existing test file. |

## User-Brand Impact

**If this lands broken, the user experiences:** No user-visible behavioral change in the happy path — reconcile already skips correctly. The danger is a *broken* helper extension: if the new `severity` routing accidentally swallows the `Error` branch or drops the pino mirror, genuine failures (DB error on `resolve-workspaces`, per-workspace `sync` failure) would stop reaching Sentry/logs, so a user's KB silently stops syncing on push with no operator signal. Mitigated by defaulting `severity` to `"error"` (existing behavior) and only opting the two expected-drain sites into `"warning"`.

**If this leaks, the user's data / workflow / money is exposed via:** Not applicable. The change moves two Sentry events from `error` to `warning` level and adds an optional helper parameter. The reported `extra` payload (`installationId`, `deliveryId`, `targetRepoUrl`) is unchanged; no new field, no PII. `userId` pseudonymization in the helper is untouched.

**Brand-survival threshold:** none — observability-severity plumbing on an expected no-op path plus a defaulted helper parameter. reason: the diff touches `observability.ts` (the silent-fallback helper) and one Inngest function's two expected-drain call sites (+ tests); it changes Sentry `severity` routing only and does not touch any sensitive path in the preflight Check 6 canonical regex (no `server/auth`, `server/stripe`, `server/byok`, no migration, no API route, no Doppler/secret/workflow file).

## Goals / Non-Goals

**Goals**
- A push for an un-onboarded / disconnected / stale `(installation_id, repo)` is reported at **`warning`** level via the existing `warnSilentFallback` — out of the error budget, non-paging, still queryable, still mirrored to Sentry (`cq-silent-fallback-must-mirror-to-sentry` satisfied).
- The schema-gate deadletter drain (`v != WORKSPACE_RECONCILE_SCHEMA_V`, `:87-95`) — the other expected-drain path, currently emitting **no** Sentry report at all — becomes observable at `warning` level (closes a `cq-silent-fallback-must-mirror-to-sentry` gap without adding error noise).
- Genuine failure paths keep `reportSilentFallback` (error level): `resolve-workspaces` DB error (`:121-129`), per-workspace `sync` failure (`:194-200`), `workspace dir missing` (`:163-169`).

**Non-Goals**
- **Changing `observability.ts` at all.** The warn-level helper already exists; this is a call-site swap in one file.
- Changing no-match control flow (already a correct non-throwing skip).
- Touching the webhook emit path (`app/api/webhooks/github/route.ts`).
- Changing `retries`, concurrency, fan-out.
- Reclassifying `workspace dir missing` (not-ready) — see Open Questions.

## Technical Approach

`reportSilentFallback` (error level) and `warnSilentFallback` (warning level) are sibling helpers with the **identical** `SilentFallbackOptions` contract; the only difference is `logger.warn` + `Sentry.captureException(err, { level: "warning", ... })` vs `logger.error` + error-level capture. The fix routes the two expected-drain sites to the warn variant. The import line in the handler (`:20`) must add `warnSilentFallback`.

### Helper choice — no helper change

`warnSilentFallback` is the in-repo precedent for exactly this class:
```
observability.ts:211  export function warnSilentFallback(err, options): void
observability.ts:223    logger.warn({ err, feature, op, ...transformedExtra }, message ?? ...)
observability.ts:228    Sentry.captureException(err, { level: "warning", tags, extra: transformedExtra })
```
Already used at `account-delete.ts:401,409`, `kb-upload-payload.ts:50`, `kb-preview-metadata.ts:69,110,125`. Adopting it for the reconcile skip aligns to the established pattern; no change to `observability.ts` and zero blast radius on the other 40+ `reportSilentFallback` callers.

## Implementation Steps

1. **Add the import** — `workspace-reconcile-on-push.ts:20`. Change
   `import { reportSilentFallback } from "@/server/observability";`
   to `import { reportSilentFallback, warnSilentFallback } from "@/server/observability";`.

2. **Swap the no-match skip to warn level** — `workspace-reconcile-on-push.ts:133-138`. Replace the `reportSilentFallback(` call with `warnSilentFallback(`; options object unchanged:
   ```ts
   warnSilentFallback(new Error("no workspace matched (installation_id, repo)"), {
     feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
     op: "skip-no-workspace-match",
     extra: { installationId, deliveryId, targetRepoUrl },
     message: "Reconcile skipped — no workspace connected to this repo",
   });
   ```
   Expected outcome: same `feature`/`op`/`extra`/`message`, same return; Sentry event drops from error to warning.

3. **Add a warn-level mirror to the schema-gate deadletter** — `workspace-reconcile-on-push.ts:93-95`. Currently emits nothing before `return`. Add:
   ```ts
   if (gate.deadletter) {
     warnSilentFallback(new Error("reconcile event drained (schema version)"), {
       feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
       op: "deadletter-schema-version",
       extra: { installationId, deliveryId, schemaV: v },
       message: "Reconcile drained — unsupported schema version",
     });
     return { ok: false, reason: gate.reason };
   }
   ```
   `deliveryId` is destructured at `:80`; `v` is in scope at `:86`.

4. **Leave genuine-failure sites on `reportSilentFallback`** — `:121-129` (`resolve-workspaces`), `:163-169` (`workspace dir missing`), `:194-200` (`sync`). Verify by inspection none were switched to the warn variant. These keep error level.

5. **Update the existing test** — `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts`. The test mocks `@/server/observability` (currently `{ reportSilentFallback, hashUserId }`). Add `warnSilentFallback: vi.fn()` to the mock factory and import the spy. Then:
   - In `reconcile — no workspace match`, change the assertion from `reportSilentFallbackSpy` to a new `warnSilentFallbackSpy` with `expect.objectContaining({ feature: "workspace-reconcile-push", op: "skip-no-workspace-match" })`, AND assert `reportSilentFallbackSpy` was NOT called on this path.
   - In `reconcile — schema gate (v=1 drains)`, add an assertion that `warnSilentFallbackSpy` was called with `expect.objectContaining({ op: "deadletter-schema-version" })`.
   - Confirm the `sync failure` and `workspace dir not provisioned` tests still assert on `reportSilentFallbackSpy` (error level) — these must stay on the error helper.

6. **Run the suite** — `cd apps/web-platform && npx vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` (runner is **vitest** per `package.json:15`; do NOT use `bun test` — `bunfig.toml` blocks it). Then typecheck per `package.json scripts` (`npx tsc --noEmit` if no dedicated script). `observability.test.ts` needs no change — the warn helper is already covered by its existing production use; optionally add a one-line assertion there that `warnSilentFallback` emits `level: "warning"` if coverage is desired, but it is not required by this fix.

## Testing Strategy

- **Unit — call-site contract (primary regression guard):** the existing reconcile test, updated so the no-match and deadletter paths assert on `warnSilentFallbackSpy` (not `reportSilentFallbackSpy`). Directly guards the Sentry error from recurring — if a future edit reverts to `reportSilentFallback`, the test fails.
- **Negative guard (do-not-regress actionable paths):** the `sync failure` and `workspace dir not provisioned` tests continue to assert on `reportSilentFallbackSpy` — confirming the genuine-failure paths stay error level.
- **No helper test needed:** `warnSilentFallback` is unchanged and already production-used; `observability.test.ts` requires no edit. (Optional: add a single assertion that `warnSilentFallback(new Error(), {feature})` calls `Sentry.captureException` with `level: "warning"` — nice-to-have, not load-bearing for this fix.)
- **Manual verification:** confirm the two swapped sites import and call `warnSilentFallback`, and the three genuine-failure sites still call `reportSilentFallback`.

## Observability

```yaml
liveness_signal:
  what: "Sentry warning-level events tagged feature=workspace-reconcile, op=skip-no-workspace-match (and op=deadletter-schema-version)"
  cadence: "Per qualifying push webhook (expected, sporadic — un-onboarded/stale pushes)"
  alert_target: "None — warning level is intentionally below the paging threshold; queryable in Sentry, not alerting"
  configured_in: "apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts (severity:warning) routed by reportSilentFallback in apps/web-platform/server/observability.ts"
error_reporting:
  destination: "Sentry (web-platform project) — error paths via reportSilentFallback (error level), expected-skip paths via warnSilentFallback (warning level); structured log via logger.error / logger.warn"
  fail_loud: "Genuine failures (resolve-workspaces DB error, sync failure, workspace dir missing) keep reportSilentFallback → error-level Sentry + error budget. This fix narrows error-level to actionable paths only; observability.ts is unchanged so the other 40+ reportSilentFallback callers are unaffected."
failure_modes:
  - mode: "Workspace resolution DB query fails"
    detection: "reportSilentFallback (error), op=resolve-workspaces"
    alert_route: "Sentry error-level (unchanged by this fix)"
  - mode: "Per-workspace sync fails"
    detection: "reportSilentFallback (error), op=sync; kb_sync_history row ok=false error_class=sync_failed"
    alert_route: "Sentry error-level (unchanged)"
  - mode: "No workspace connected to repo (expected skip)"
    detection: "warnSilentFallback (warning), op=skip-no-workspace-match; return {ok:false, reason:'no-workspace-match'}"
    alert_route: "Sentry warning-level (queryable, non-paging) — the target state of this fix"
  - mode: "Unsupported schema version (expected drain)"
    detection: "warnSilentFallback (warning), op=deadletter-schema-version; return {ok:false, reason:'schema_v=...'}"
    alert_route: "Sentry warning-level (newly observable — was a silent return before)"
logs:
  where: "Server structured logger (pino) — logger.warn for the two downgraded paths, logger.error for genuine failures; mirrored to Sentry by the same helper"
  retention: "Per existing pino/Sentry retention; no change introduced by this fix"
discoverability_test:
  command: "cd apps/web-platform && npx vitest run test/server/inngest/workspace-reconcile-on-push.test.ts"
  expected_output: "Suite passes; reconcile test asserts warnSilentFallback called with op=skip-no-workspace-match and op=deadletter-schema-version, and that reportSilentFallback is NOT called on those paths but IS called on sync/not-ready paths"
```

## Risks & Mitigations

| Risk | Likelihood × Impact | Early warning | Mitigation |
|---|---|---|---|
| Downgrading no-match to warning hides a real mass-miss regression (compose-before-normalize / repo_url drift) under a non-paging level | Med × Med | Spike in `op=skip-no-workspace-match` warnings for onboarded repos | Warning still carries `installationId`+`targetRepoUrl` → queryable; `repo-url-sql-parity` test guards the dominant match-regression cause; optional threshold alert (Open Questions). |
| Accidentally switching an actionable site (`sync`/`resolve`/`not-ready`) to the warn helper while editing | Low × High | Genuine failures stop paging | Swap only the two named sites; Step 4 + inspection + the negative-guard tests verify the rest stay on `reportSilentFallback`. |
| Test mock for `@/server/observability` doesn't include `warnSilentFallback` → handler call throws "not a function" under test | Med × Low | Reconcile test errors at import | Step 5 explicitly adds `warnSilentFallback: vi.fn()` to the mock factory. |
| Adding the deadletter mirror changes the `drains v=1` test expectation | Low × Low | Reconcile test fails | The current `drains v=1` test only asserts return value + that sync wasn't called; Step 5 adds the new warn assertion intentionally. |

## Acceptance Criteria

- [ ] `observability.ts` is unchanged (no helper edit).
- [ ] `workspace-reconcile-on-push.ts:20` imports `warnSilentFallback` alongside `reportSilentFallback`.
- [ ] No-match site (`:133`) calls `warnSilentFallback` (was `reportSilentFallback`); resulting Sentry event is warning-level. (Goal 1)
- [ ] Schema-gate deadletter drain (`:93-95`) emits `warnSilentFallback` with `op:"deadletter-schema-version"` before returning. (Goal 2)
- [ ] `resolve-workspaces` (`:122`), `sync` (`:195`), `workspace dir missing` (`:164`) still call `reportSilentFallback` → remain error-level. (Goal 3)
- [ ] Reconcile test mock adds `warnSilentFallback: vi.fn()`; asserts it is called with `{ op:"skip-no-workspace-match" }` and `{ op:"deadletter-schema-version" }`, and that `reportSilentFallback` is NOT called on those paths but IS on sync/not-ready.
- [ ] `cd apps/web-platform && npx vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` passes; typecheck clean.
- [ ] No new field added to any Sentry `extra` payload (no PII introduced); `feature`/`message`/`return` shape unchanged on the no-match path.

## Open Questions

- **Should `workspace dir missing` (not-ready, `:163-169`) also be `warning`?** Expected during provisioning but could mask stuck provisioning. Left at error for now (out of scope); reclassify with a time-since-onboard heuristic if it becomes recurring noise.
- **Threshold alert on the warning?** A Sentry saved-search / metric alert on `op=skip-no-workspace-match` count-per-hour would catch a mass-miss regression the level downgrade otherwise quiets. Out of scope for the code fix; per `hr-no-dashboard-eyeball-pull-data-yourself`, if pursued, prescribe the Sentry API query + deterministic threshold, not dashboard-watching.
- **`info` vs `warning`?** Chose `warning` to keep a weak queryable signal for onboarded-repo regressions; revisit to `info` only if warning volume proves pure noise.

## Domain Review

**Domains relevant:** none

No cross-domain implications — observability-severity plumbing on one helper plus one Inngest function's expected-skip paths. No product/UI surface, no legal/compliance/regulated-data surface (no schema, auth, API route, or PII), no new infrastructure. The Sentry report payload is unchanged.

## Infrastructure (IaC)

No new infrastructure. The change edits one application source file (`apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`) and its test. Sentry severity routing reuses the existing `warnSilentFallback` helper; no Terraform, no new secret, no new vendor, no new runtime process.
