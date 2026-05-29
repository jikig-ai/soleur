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

**The actual root cause is that `reportSilentFallback` has no severity control — it hardcodes error level.** Verified at `observability.ts:174-201`: the helper always calls `logger.error(...)` and, for the `Error`-instance branch, `Sentry.captureException(err, ...)` — which is **error-level by construction**. `SilentFallbackOptions` (`:102`) has only `{ feature, op?, extra?, message? }`; there is **no `severity` field**. So *every* `reportSilentFallback` call — including this expected skip — is reported at error level. The earlier draft's premise ("just pass `severity: 'warning'`") was wrong: that option does not exist today. (The `severity: "breach_attempt"` strings elsewhere in the file belong to `mirrorCrossTenantViolation` (`:229`), a different function — not `reportSilentFallback`.)

**The fix therefore has two parts:** (1) extend `reportSilentFallback` to accept an optional `severity?: "error" | "warning" | "info"` (default `"error"`, preserving all 40+ existing call sites' behavior) that routes `logger.warn`/`logger.info` + `Sentry.captureException(..., { level })` / `captureMessage(..., { level })` accordingly; (2) pass `severity: "warning"` at the no-match call site (and the schema-deadletter drain). This keeps the helper the single mirror boundary (`cq-silent-fallback-must-mirror-to-sentry`) while letting expected fallbacks stop polluting the error budget. Brand-survival threshold: **none** (observability-severity plumbing; no auth/data/credential/billing surface).

## Research Reconciliation — Spec vs. Codebase

The original bug report and the first planning draft were built on a file tree that does not exist in this repo, and the second draft assumed a `severity` option that the helper does not have. Both sets of divergences are recorded so no downstream phase inherits the fiction.

| Claim (bug report / earlier drafts) | Codebase reality (verified) | Plan response |
|---|---|---|
| File at `web-platform/src/lib/inngest/functions/...` | Real path: `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` (259 lines) | Use real path throughout. |
| Handler "throws" on no-match | Calls `reportSilentFallback(...)` then `return { ok:false, reason:"no-workspace-match" }` — no throw (`:131-140`) | Root cause re-derived. |
| `retries: 3`; consider `NonRetriableError` | `createFunction` config is `retries: 1` (`:255`); no-match never throws → never retries | Retry framing dropped. |
| Separate `workspace-resolver.ts` with a camelCase mapping bug; `resolveWorkspaceForReconcile` returns `null` | Resolution is an inline Supabase query in the handler (`.from("workspaces").select("id").eq(...)`, `:107-119`). `@/server/workspace-resolver` exports only `workspacePathForWorkspaceId` (a path builder) | Resolver-bug item dropped — fiction. |
| Telemetry via `recordReconcileOutcome` / `ReconcileOutcome` union (dead code to wire) | No such module/symbol. Observability = `reportSilentFallback` (`@/server/observability`) + `appendKbSyncRow` (`@/server/session-sync`) | Telemetry-wiring item dropped. |
| **Fix = pass `severity: "warning"` to `reportSilentFallback`** | `SilentFallbackOptions` (`observability.ts:102`) has NO `severity` field; helper hardcodes `logger.error` + `captureException`/`captureMessage(level:"error")` (`:184,189,192-196`) | **Helper must be extended first** (Step 1); then the call site can pass it. |
| Test runner is bun / empty package.json | `apps/web-platform/package.json:15` `"test": "vitest"`; `bunfig.toml` blocks bun test discovery (`pathIgnorePatterns=["**"]`, #1469). Real test: `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` (vitest, `vi.mock`) | Test plan rewritten for **vitest**; extend the existing test file. |

## User-Brand Impact

**If this lands broken, the user experiences:** No user-visible behavioral change in the happy path — reconcile already skips correctly. The danger is a *broken* helper extension: if the new `severity` routing accidentally swallows the `Error` branch or drops the pino mirror, genuine failures (DB error on `resolve-workspaces`, per-workspace `sync` failure) would stop reaching Sentry/logs, so a user's KB silently stops syncing on push with no operator signal. Mitigated by defaulting `severity` to `"error"` (existing behavior) and only opting the two expected-drain sites into `"warning"`.

**If this leaks, the user's data / workflow / money is exposed via:** Not applicable. The change moves two Sentry events from `error` to `warning` level and adds an optional helper parameter. The reported `extra` payload (`installationId`, `deliveryId`, `targetRepoUrl`) is unchanged; no new field, no PII. `userId` pseudonymization in the helper is untouched.

**Brand-survival threshold:** none — observability-severity plumbing on an expected no-op path plus a defaulted helper parameter. reason: the diff touches `observability.ts` (the silent-fallback helper) and one Inngest function's two expected-drain call sites (+ tests); it changes Sentry `severity` routing only and does not touch any sensitive path in the preflight Check 6 canonical regex (no `server/auth`, `server/stripe`, `server/byok`, no migration, no API route, no Doppler/secret/workflow file).

## Goals / Non-Goals

**Goals**
- Add an optional `severity?: "error" | "warning" | "info"` to `SilentFallbackOptions`, **defaulting to `"error"`** so all existing call sites are byte-for-byte behavior-preserving. Route: `warning` → `logger.warn` + Sentry level `"warning"`; `info` → `logger.info` + Sentry level `"info"`; `error`/unset → current behavior (`logger.error` + `captureException` / `captureMessage(level:"error")`).
- A push for an un-onboarded / disconnected / stale `(installation_id, repo)` is reported at **`warning`** level — out of the error budget, non-paging, still queryable.
- The schema-gate deadletter drain (`v != WORKSPACE_RECONCILE_SCHEMA_V`, `:87-95`) — the other expected-drain path, currently emitting **no** Sentry report at all — becomes observable at `warning` level (closes a `cq-silent-fallback-must-mirror-to-sentry` gap without adding error noise).
- Genuine failure paths keep error level: `resolve-workspaces` DB error (`:121-129`), per-workspace `sync` failure (`:194-200`), `workspace dir missing` (`:163-169`).

**Non-Goals**
- Changing no-match control flow (already a correct non-throwing skip).
- Touching the webhook emit path (`app/api/webhooks/github/route.ts`).
- Changing `retries`, concurrency, fan-out.
- Migrating any of the other 40+ `reportSilentFallback` call sites to a new severity (they keep the `error` default).
- Reclassifying `workspace dir missing` (not-ready) — see Open Questions.
- A separate `warnSilentFallback`/`infoSilentFallback` wrapper (no such sibling exists; an option on the existing helper is the smaller change).

## Technical Approach

`reportSilentFallback` is the single Sentry-mirror boundary. Today its level is fixed at `error`. The minimal, behavior-preserving change is an optional `severity` that defaults to the current behavior and routes the logger + Sentry level together.

### Helper extension (observability.ts)

Add to the interface (`:102-...`):
```ts
export interface SilentFallbackOptions {
  feature: string;
  op?: string;
  extra?: Record<string, unknown>;
  message?: string;
  /**
   * Sentry/pino level. Defaults to "error". Expected, non-actionable
   * fallbacks (stale webhooks, drained schema-version events, no-workspace
   * skips) SHOULD pass "warning" or "info" so they don't page or pollute
   * the error budget.
   */
  severity?: "error" | "warning" | "info";
}
```

Rewrite the body (`:174-201`) to route by severity while preserving the Error/non-Error branch and the try/catch guard:
```ts
export function reportSilentFallback(err: unknown, options: SilentFallbackOptions): void {
  const { feature, op, extra, message, severity = "error" } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;

  const transformedExtra = hashExtraUserId(extra);

  const logFn = severity === "warning" ? logger.warn : severity === "info" ? logger.info : logger.error;
  logFn({ err, feature, op, ...transformedExtra }, message ?? `${feature} silent fallback`);

  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { level: severity, tags, extra: transformedExtra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(message ?? `${feature} silent fallback`, {
        level: severity,
        tags,
        extra: { err, ...transformedExtra },
      });
    }
  } catch {
    return;
  }
}
```
Notes:
- `Sentry.captureException` accepts a `level` in its `CaptureContext` (same `SeverityLevel` union as `captureMessage`), so the Error branch can be downgraded too. **Confirm at /work** against the installed `@sentry/nextjs` types (`grep -n "level" node_modules/@sentry/types/.../*.d.ts` or the re-export) — if the installed version's `captureException` overload does not accept `level`, fall back to wrapping with `Sentry.withScope(scope => { scope.setLevel(severity); Sentry.captureException(err, { tags, extra }); })`. Either way the no-match path is an `Error` instance, so this branch is the load-bearing one.
- Default `severity = "error"` means the spread/destructure leaves all existing callers identical (they pass no `severity`).
- `logger.warn`/`logger.info` exist on the pino logger (the handler's `HandlerArgs.logger` type and the module `logger` both expose `warn`/`info`/`error`).

### Precedent

The helper's own docstring already anticipates this distinction ("Use when ... a warning about a condition that should never be common in steady state") but never exposed the knob. `oauth-probe-sentinels.ts` handles expected probe failures as a sibling expected-fallback class; aligning the reconcile skip to `warning` matches that intent.

## Implementation Steps

1. **Extend the helper** — `apps/web-platform/server/observability.ts`. Add `severity?: "error" | "warning" | "info"` to `SilentFallbackOptions` and route logger + Sentry level as shown above. Default `"error"`. Expected outcome: all existing call sites unchanged; new opt-in available.

2. **Downgrade the no-match skip** — `workspace-reconcile-on-push.ts:133-138`. Add `severity: "warning"`:
   ```ts
   reportSilentFallback(new Error("no workspace matched (installation_id, repo)"), {
     feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
     op: "skip-no-workspace-match",
     extra: { installationId, deliveryId, targetRepoUrl },
     message: "Reconcile skipped — no workspace connected to this repo",
     severity: "warning",
   });
   ```

3. **Mirror the schema-gate deadletter at `warning`** — `workspace-reconcile-on-push.ts:93-95`. Currently emits nothing before `return`. Add:
   ```ts
   if (gate.deadletter) {
     reportSilentFallback(new Error("reconcile event drained (schema version)"), {
       feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
       op: "deadletter-schema-version",
       extra: { installationId, deliveryId, schemaV: v },
       message: "Reconcile drained — unsupported schema version",
       severity: "warning",
     });
     return { ok: false, reason: gate.reason };
   }
   ```
   `deliveryId` is destructured at `:80`; `v` is in scope at `:86`.

4. **Leave genuine-failure sites unchanged** — `:121-129` (`resolve-workspaces`), `:163-169` (`workspace dir missing`), `:194-200` (`sync`). Verify by inspection none gained `severity`. These keep the `error` default.

5. **Extend the existing test** — `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts`. The `reports no-workspace-match` test currently asserts `expect.objectContaining({ op: "skip-no-workspace-match" })`. Tighten to include severity:
   ```ts
   expect(reportSilentFallback).toHaveBeenCalledWith(
     expect.any(Error),
     expect.objectContaining({ op: "skip-no-workspace-match", severity: "warning" }),
   );
   ```
   And extend the existing `drains v=1` test to also assert the deadletter mirror:
   ```ts
   expect(reportSilentFallback).toHaveBeenCalledWith(
     expect.any(Error),
     expect.objectContaining({ op: "deadletter-schema-version", severity: "warning" }),
   );
   ```
   (The test mocks `reportSilentFallback` as a `vi.fn()`, so it does not exercise the real helper's routing — that is fine; the call-site contract is what the regression guard needs.)

6. **Add a helper-routing unit test** — extend or add to `apps/web-platform/test/observability.test.ts`. Assert that `reportSilentFallback(new Error("x"), { feature: "f", severity: "warning" })` calls `Sentry.captureException` with `level: "warning"` (or `withScope`+`setLevel("warning")` per the chosen branch) and `logger.warn` (not `logger.error`); and that omitting `severity` still routes to `error`/`captureException` default. This is the guard that protects the 40+ existing callers from a regression.

7. **Run the suite** — `cd apps/web-platform && npx vitest run test/server/inngest/workspace-reconcile-on-push.test.ts test/observability.test.ts` (runner is **vitest** per `package.json:15`; do NOT use `bun test` — `bunfig.toml` blocks it). Then typecheck per `package.json scripts` (confirm the exact script at /work; `npx tsc --noEmit` if none).

## Testing Strategy

- **Unit — call-site contract (primary regression guard):** the existing reconcile test, tightened to assert `severity: "warning"` on the no-match and deadletter mirrors. Directly guards the Sentry error from recurring.
- **Unit — helper routing (protects existing callers):** new `observability.test.ts` assertions that `severity` routes Sentry level + logger fn correctly AND that the default remains `error` (so the 40+ unchanged call sites cannot silently flip level). This is the highest-value new test because the helper change is the widest-blast-radius edit.
- **Negative guard:** confirm no existing `observability.test.ts` assertion that pins `level: "error"` for a default call breaks — if one exists, the default-preserving design keeps it green; if it does break, the helper change regressed the default and must be fixed.
- **Manual verification:** re-read the rewritten helper to confirm the Error branch (load-bearing for no-match) carries the level through; confirm pino mirror still fires on all paths.

## Observability

```yaml
liveness_signal:
  what: "Sentry warning-level events tagged feature=workspace-reconcile, op=skip-no-workspace-match (and op=deadletter-schema-version)"
  cadence: "Per qualifying push webhook (expected, sporadic — un-onboarded/stale pushes)"
  alert_target: "None — warning level is intentionally below the paging threshold; queryable in Sentry, not alerting"
  configured_in: "apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts (severity:warning) routed by reportSilentFallback in apps/web-platform/server/observability.ts"
error_reporting:
  destination: "Sentry (web-platform project) via reportSilentFallback; Error branch → captureException(level), non-Error → captureMessage(level); structured log via logger.warn/info/error"
  fail_loud: "Genuine failures (resolve-workspaces DB error, sync failure, workspace dir missing) keep severity=error → error-level Sentry + error budget. This fix narrows error-level to actionable paths only; the helper default stays error so the other 40+ callers are unaffected."
failure_modes:
  - mode: "Workspace resolution DB query fails"
    detection: "reportSilentFallback severity=error (default), op=resolve-workspaces"
    alert_route: "Sentry error-level (unchanged by this fix)"
  - mode: "Per-workspace sync fails"
    detection: "reportSilentFallback severity=error (default), op=sync; kb_sync_history row ok=false error_class=sync_failed"
    alert_route: "Sentry error-level (unchanged)"
  - mode: "No workspace connected to repo (expected skip)"
    detection: "reportSilentFallback severity=warning, op=skip-no-workspace-match; return {ok:false, reason:'no-workspace-match'}"
    alert_route: "Sentry warning-level (queryable, non-paging) — the target state of this fix"
  - mode: "Unsupported schema version (expected drain)"
    detection: "reportSilentFallback severity=warning, op=deadletter-schema-version; return {ok:false, reason:'schema_v=...'}"
    alert_route: "Sentry warning-level (newly observable — was a silent return before)"
logs:
  where: "Server structured logger (pino) — logger.warn for the two downgraded paths, logger.error for genuine failures; mirrored to Sentry by the same helper"
  retention: "Per existing pino/Sentry retention; no change introduced by this fix"
discoverability_test:
  command: "cd apps/web-platform && npx vitest run test/server/inngest/workspace-reconcile-on-push.test.ts test/observability.test.ts"
  expected_output: "Both suites pass; reconcile test asserts reportSilentFallback called with op=skip-no-workspace-match AND severity=warning, and op=deadletter-schema-version AND severity=warning; observability test asserts severity routes Sentry level + logger fn and defaults to error"
```

## Risks & Mitigations

| Risk | Likelihood × Impact | Early warning | Mitigation |
|---|---|---|---|
| Helper change regresses the 40+ existing callers (e.g., default flips off error level, or pino mirror dropped) | Med × High | `observability.test.ts` fails; existing error-level events vanish from Sentry | Default `severity="error"` reproduces current behavior exactly; Step 6 test pins the default; re-read confirms pino mirror fires on every branch. |
| Installed `@sentry/nextjs` `captureException` overload rejects `{ level }` | Med × Med | `tsc` error on the Error branch | Step 1 note: fall back to `Sentry.withScope(s => { s.setLevel(severity); Sentry.captureException(err, { tags, extra }); })`. Confirm against `node_modules/@sentry/*` types at /work. |
| Downgrading no-match to warning hides a real mass-miss regression (compose-before-normalize / repo_url drift) under a non-paging level | Med × Med | Spike in `op=skip-no-workspace-match` warnings for onboarded repos | Warning still carries `installationId`+`targetRepoUrl` → queryable; `repo-url-sql-parity` test guards the dominant match-regression cause; optional threshold alert (Open Questions). |
| Accidentally downgrading an actionable site while editing the function | Low × High | Genuine failures stop paging | Scope `severity` edits to exactly the two named sites; Step 4 + inspection verify the rest keep the default. |
| Deadletter mirror breaks the existing `drains v=1` test if it asserted zero `reportSilentFallback` calls | Low × Low | Reconcile test fails | The current `drains v=1` test only asserts the return value; Step 5 adds the new assertion intentionally. |

## Acceptance Criteria

- [ ] `SilentFallbackOptions` gains `severity?: "error" | "warning" | "info"` defaulting to `"error"`; `reportSilentFallback` routes logger fn + Sentry level by it; omitting `severity` is byte-for-byte behavior-preserving. (Goal 1)
- [ ] `observability.test.ts` asserts `severity:"warning"` → `logger.warn` + Sentry level `"warning"`, and unset → `error`/`captureException` default.
- [ ] `workspace-reconcile-on-push.ts` no-match site (`:133`) passes `severity:"warning"`; resulting Sentry event is warning-level. (Goal 2)
- [ ] Schema-gate deadletter drain emits a `warning`-level `reportSilentFallback` (`op:"deadletter-schema-version"`) before returning. (Goal 3)
- [ ] `resolve-workspaces` (`:122`), `sync` (`:195`), `workspace dir missing` (`:164`) sites unchanged → remain error-level. (Goal 4)
- [ ] Reconcile test asserts `reportSilentFallback` called with `{ op:"skip-no-workspace-match", severity:"warning" }` and `{ op:"deadletter-schema-version", severity:"warning" }`.
- [ ] `cd apps/web-platform && npx vitest run test/server/inngest/workspace-reconcile-on-push.test.ts test/observability.test.ts` passes; typecheck clean.
- [ ] No new field added to any Sentry `extra` payload (no PII introduced); `feature`/`message`/`return` shape unchanged on the no-match path.

## Open Questions

- **`captureException` level support in the installed Sentry version?** Resolved at /work by reading `node_modules/@sentry/*` types; the plan provides the `withScope` fallback if the `{ level }` overload is absent.
- **Should `workspace dir missing` (not-ready, `:163-169`) also be `warning`?** Expected during provisioning but could mask stuck provisioning. Left at error for now (out of scope); reclassify with a time-since-onboard heuristic if it becomes recurring noise.
- **Threshold alert on the warning?** A Sentry saved-search / metric alert on `op=skip-no-workspace-match` count-per-hour would catch a mass-miss regression the level downgrade otherwise quiets. Out of scope for the code fix; per `hr-no-dashboard-eyeball-pull-data-yourself`, if pursued, prescribe the Sentry API query + deterministic threshold, not dashboard-watching.
- **`info` vs `warning`?** Chose `warning` to keep a weak queryable signal for onboarded-repo regressions; revisit to `info` only if warning volume proves pure noise.

## Domain Review

**Domains relevant:** none

No cross-domain implications — observability-severity plumbing on one helper plus one Inngest function's expected-skip paths. No product/UI surface, no legal/compliance/regulated-data surface (no schema, auth, API route, or PII), no new infrastructure. The Sentry report payload is unchanged.

## Infrastructure (IaC)

No new infrastructure. The change edits two application source files (`apps/web-platform/server/observability.ts`, `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`) and their tests. Sentry severity routing is application-layer; no Terraform, no new secret, no new vendor, no new runtime process.
