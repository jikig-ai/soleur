---
title: "fix: downgrade reconcile no-workspace-match Sentry severity from error to warning"
type: fix
lane: single-domain
brand_survival_threshold: none
date: 2026-05-29
related_sentry: "Sentry event github-c8bb0ef6 (2026-05-29, web-platform)"
status: implemented
---

# Fix: `workspace-reconcile-on-push` reports an expected skip at error level

## Overview

The Inngest function `workspace-reconcile-on-push` (event `platform/workspace.reconcile.requested`)
logs an **error-level** Sentry event — `Error: no workspace matched (installation_id, repo)`
(`github-c8bb0ef6-...`, `handled=yes`, `level=error`) — for a condition that is by design an
**expected, non-actionable no-op**: a push webhook for an `(installation_id, repo)` with zero
connected workspaces (app uninstalled, repo not yet onboarded, two-users-same-fork where one
disconnected, or a stale/replayed webhook).

The code is **already a graceful skip** — it does not throw (`handled=yes` confirms a captured
report, not an uncaught exception). The bug is that the skip is mirrored via `reportSilentFallback`,
which emits at **error** level, when a warn-level sibling (`warnSilentFallback`) already exists for
exactly this "degraded-but-expected" class.

## Root cause (verified against live source, `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`)

```ts
const rows = workspaces.rows ?? [];
if (rows.length === 0) {
  reportSilentFallback(new Error("no workspace matched (installation_id, repo)"), {   // error level
    feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
    op: "skip-no-workspace-match",
    extra: { installationId, deliveryId, targetRepoUrl },
    message: "Reconcile skipped — no workspace connected to this repo",
  });
  return { ok: false, reason: "no-workspace-match" };
}
```

`reportSilentFallback` (`server/observability.ts:164`) calls `logger.error` + error-level
`Sentry.captureException`. `warnSilentFallback` (`server/observability.ts:211`) has the **identical**
`(err, { feature, op, extra, message })` contract but emits `logger.warn` + `Sentry.captureException(err, { level: "warning" })`.

Adjacent gap: the **schema-version deadletter** branch (an expected drain of in-flight v=1 events)
currently `return`s with **no** Sentry mirror at all — a `cq-silent-fallback-must-mirror-to-sentry`
gap. This fix adds a warn-level mirror there too.

`retries: 1` on the function (so the error event is not multiplied by retries, but is still
false-positive error-budget noise on every qualifying push).

## Implementation (as built)

1. `workspace-reconcile-on-push.ts:20` — add `warnSilentFallback` to the `@/server/observability` import.
2. No-match branch — swap `reportSilentFallback(` → `warnSilentFallback(`; options object unchanged
   (`op: "skip-no-workspace-match"`). Sentry event drops from error to warning.
3. Schema-version deadletter branch — add a `warnSilentFallback(...)` mirror (`op:
   "deadletter-schema-version"`, `extra: { installationId, deliveryId, schemaV: v }`) before the
   existing `return`.
4. Genuine-failure sites stay on `reportSilentFallback` (error level): `resolve-workspaces` DB error,
   per-workspace `sync` failure, `workspace dir missing`.
5. Test (`test/server/inngest/workspace-reconcile-on-push.test.ts`) — add a `warnSilentFallback` spy
   to the `@/server/observability` mock; the no-match test now asserts `warnSilentFallback` (op
   `skip-no-workspace-match`) AND that `reportSilentFallback` is NOT called; the schema-gate test
   asserts `warnSilentFallback` (op `deadletter-schema-version`); the `sync` and `dir-missing` tests
   continue to assert `reportSilentFallback` (error level).

## Acceptance criteria

- [x] No-match path mirrors to Sentry at **warning** via `warnSilentFallback`; `reportSilentFallback`
      not called on that path.
- [x] Schema-version deadletter path emits a warning-level mirror (was a silent return).
- [x] Genuine-failure paths (`resolve-workspaces`, `sync`, `dir-missing`) stay error-level.
- [x] `./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` passes.
- [x] `npx tsc --noEmit` — exit 0.
- [x] No new field in any Sentry `extra` payload (no PII); return shapes unchanged.

## Observability

After deploy the `no-workspace-match` skip and the schema-version drain land in Sentry at
`level=warning` (out of the error budget, still queryable), tagged
`feature=workspace-reconcile-push op=skip-no-workspace-match | op=deadletter-schema-version`.
Genuine reconcile failures remain `level=error`. `observability.ts` is unchanged, so the other
`reportSilentFallback` callers are unaffected. No new infra, migration, secret, or PII.

## Rollback

Single-commit revert. No migrations, no infra, no config.
