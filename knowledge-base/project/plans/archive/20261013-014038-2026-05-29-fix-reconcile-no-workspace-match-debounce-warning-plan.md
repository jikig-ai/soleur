---
title: "fix: debounce the reconcile no-workspace-match warning mirror so it stops flooding Sentry alert rules"
type: fix
lane: single-domain
brand_survival_threshold: none
date: 2026-05-29
related_sentry: "github-c8bb0ef6-* (workspace-reconcile-push, op=skip-no-workspace-match, level=warning, handled=yes); grouped under alert rule auth-callback-no-code-burst"
related_pr: 4597
status: draft
---

# Fix: `workspace-reconcile-on-push` floods Sentry on the expected no-workspace-match skip

## Enhancement Summary

**Deepened on:** 2026-05-29
**Gates run:** 4.4 precedent-diff (PASS — pattern non-novel), 4.45 verify-the-negative (PASS),
4.6 User-Brand Impact halt (PASS — threshold `none` + server/** scope-out), 4.7 Observability
(PASS — 5/5 fields, no SSH), 4.8 PAT-shaped var halt (PASS — none).

### Key findings (live-verified)

1. **PR #4597 already shipped the error→warning downgrade** (merged main 2026-05-29 11:59Z, commit
   `d11099af`). This plan is the *volume* follow-up, not a re-do of the severity change.
2. **Severity alone does not stop the Sentry alert flood** — confirmed by the #4571 precedent learning:
   Sentry `EventFrequencyCondition` rules count events regardless of `level`. The volume bound is
   **debounce**. The current `warnSilentFallback` path is undebounced → still floods.
3. **The fix primitive already exists and is in production**: `mirrorWarnWithDebounce`
   (`observability.ts:386`) at `lib/feature-flags/server.ts:117`, with the identical call shape and the
   same motivating alert (`auth-callback-no-code-burst`). Adoption is a ~6-line emit-site swap.
4. **No matching-logic defect** — zero workspaces for an install/repo is the correct answer (ADR-044);
   the skip is right, only the reporting cadence is wrong. This is firmly **option (b)**.
5. **Rule citations verified active**: `cq-write-failing-tests-before`, `hr-no-dashboard-eyeball`.
   KB-path citations resolve. Code-review overlap (#3739, #3703) acknowledged as non-overlapping.

## Overview

The Inngest function `workspace-reconcile-on-push` (`fnId=soleur-runtime-workspace-reconcile-on-push`,
event `platform/workspace.reconcile.requested`) emits a **warning-level** Sentry event —
`Error: no workspace matched (installation_id, repo)` (`op=skip-no-workspace-match`,
`feature=workspace-reconcile-push`, `handled=yes`, `level=warning`) — on **every** push webhook
for an installation that has a founder row but **zero connected workspaces** (ADR-044: app installed,
repo not yet onboarded to any workspace; a disconnected fork; or a stale/replayed delivery). This is
an **expected, non-actionable no-op**, yet it is being escalated to Sentry as recurring "New issue"
notifications and is noisy enough that the operator notices it grouped alongside the
`auth-callback-no-code-burst` alert volume.

This is a **follow-up to PR #4597** (merged to main 2026-05-29 11:59Z), which already downgraded this
path from `reportSilentFallback` (error) to `warnSilentFallback` (warning). That change was *necessary
but insufficient*: per the #4571 precedent learning
[`2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods.md`](../learnings/2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods.md),
**Sentry `EventFrequencyCondition` alert rules count events regardless of `level`** — flipping
error→warning does not reduce alert volume. The actual volume bound is **debounce**.

The fix: route the no-workspace-match skip through the existing `mirrorWarnWithDebounce`
(`server/observability.ts:386`) — the exact primitive built for the #4571 Flagsmith-timeout flood —
keyed on `(installationId, targetRepoUrl)` with a dedicated `errorClass`, so the same expected skip
for the same install/repo mirrors at most once per 5-minute window. `mirrorWarnWithDebounce` gates the
whole `warnSilentFallback` call (the pino `logger.warn` AND the Sentry mirror), so both are capped per
window; the first occurrence per key per window still carries the full pino + Sentry signal, so a
genuine onboarding-drift case still surfaces (queryable in Better Stack / container logs) while the
per-push Sentry-alert noise is removed.

## Premise Validation

- **Cited route handler** `app/api/inngest/route.js`: the path is `route.ts` (TypeScript), not
  `.js`. Verified present at `apps/web-platform/app/api/inngest/route.ts`; `workspaceReconcileOnPush`
  is registered in its `functions: [...]` array (line 113). Premise holds with the extension corrected.
- **Cited function source**: `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`
  exists; the no-match site is lines 139–153.
- **"is this a workspace-lookup bug or an expected skip?"** — Verified **expected skip**. The webhook
  (`app/api/webhooks/github/route.ts:275–307`) dispatches a reconcile event for every reconcilable push
  on any installation that resolves to a founder. The handler resolves workspaces by
  `(github_installation_id, repo_url)` (lines 115–127); `repo_url` is composed via
  `normalizeRepoUrl("https://github.com/" + fullName)` (compose-before-normalize, ADR-044 P0). When the
  install has no workspace connected to that repo, the query correctly returns zero rows. There is **no
  matching-logic defect** — the TS↔SQL normalize parity is the sole match contract and is covered by
  `test/repo-url-sql-parity.test.ts` and the slug→URL parity test (AC7). So this is **option (b)**:
  the skip is correct; only the *reporting* needs tuning. The answer is now "debounce the warn mirror,"
  not "lower severity" (already done in #4597).
- **PR #4597 state**: `gh pr view 4597` → `state: MERGED`, `mergedAt: 2026-05-29T11:59:53Z`, base `main`.
  The downgrade commit `d11099af` is on origin/main; the live file matches main (no diff). This branch
  is the dedicated follow-up.
- **`auth-callback-no-code-burst`**: a real Sentry issue-alert rule defined in
  `apps/web-platform/infra/sentry/issue-alerts.tf:55–88` (`EventFrequencyCondition`-style, dedup
  `frequency = 62`). The bug report's "grouped under" is the operator observing alert-rule noise; this
  plan does not edit the Terraform alert rule (the fix is at the emit site).

## Research Reconciliation — Spec vs. Codebase

| Premise (from issue) | Codebase reality | Plan response |
| --- | --- | --- |
| Route handler at `app/api/inngest/route.js` | File is `route.ts` (TypeScript) | Corrected; reference `.ts` throughout. No edit to route file. |
| Warnings firing at `level=warning`, escalated as recurring Sentry "New issue" | `warnSilentFallback` unconditionally calls `Sentry.captureMessage`/`captureException` per occurrence; no debounce | Route through `mirrorWarnWithDebounce` (5-min per-key TTL) — the volume bound. |
| "fix the workspace lookup OR downgrade severity" | Lookup is correct (zero rows is the right answer); severity already `warning` (PR #4597) | Neither (a) nor a second severity flip — debounce the existing warn mirror (the unaddressed half of #4571's "severity alone is insufficient" insight). |

## Root cause (verified against live source)

`workspace-reconcile-on-push.ts:139–153`:

```ts
const rows = workspaces.rows ?? [];
if (rows.length === 0) {
  warnSilentFallback(new Error("no workspace matched (installation_id, repo)"), {  // warn, NO debounce
    feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,           // "workspace-reconcile-push"
    op: "skip-no-workspace-match",
    extra: { installationId, deliveryId, targetRepoUrl },
    message: "Reconcile skipped — no workspace connected to this repo",
  });
  return { ok: false, reason: "no-workspace-match" };
}
```

`warnSilentFallback` (`observability.ts:211–241`) emits `logger.warn` + `Sentry.captureException(err,
{ level: "warning", ... })` on **every** call. With one reconcile event dispatched per push on any
founder-bearing-but-workspace-less install, this is an unbounded warn-level Sentry stream.

`mirrorWarnWithDebounce` (`observability.ts:386–394`) is the ready-made fix: it `tryClaim`s a per-key
TTL slot on the shared `_mirrorDebounce` `TtlDedupMap` (5-min window, `MIRROR_DEBOUNCE_MS`) and only
then calls `warnSilentFallback`. Its dedup key is an opaque in-process token (never emitted). The
registry docstring at `observability.ts:253–266` lists `errorClass` strings; adding a new caller
requires registering a distinct `errorClass` so key spaces stay disjoint.

## User-Brand Impact

**If this lands broken, the user experiences:** no user-facing change — this only tunes an
operator-side observability mirror. A bug (e.g. a too-aggressive dedup key) would at worst *under-report*
an expected no-op. Note the debounce caps BOTH the pino `logger.warn` and the Sentry mirror (it gates
the whole `warnSilentFallback`), but the first occurrence per `(installationId, repoUrl)` per 5-min
window still emits the full pino + Sentry signal, so a genuine onboarding-drift case stays diagnosable
in Better Stack / container logs.

**If this leaks, the user's data is exposed via:** nothing new. `extra` carries `installationId`
(numeric), `deliveryId`, and `targetRepoUrl` — already emitted by the current warn mirror; no userId is
introduced. The dedup key is `(installationId, targetRepoUrl)`, an in-process token never sent to Sentry.

**Brand-survival threshold:** none.

`threshold: none, reason: edits touch apps/web-platform/server/** (observability emit-site routing + one Inngest handler line) — the deterministic Phase 4.6 sensitive-path regex matches server/**; this is an observability-only change with no auth/PII/regulated-data surface.`

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- Confirm `mirrorWarnWithDebounce` signature `(err, ctx, key, errorClass)` at `observability.ts:386`.
- Confirm `WORKSPACE_RECONCILE_SENTRY_FEATURE === "workspace-reconcile-push"` at `session-sync.ts:308`.
- Confirm test runner: `apps/web-platform/package.json` `scripts.test = "vitest"`; `bunfig.toml` has
  `[test] pathIgnorePatterns` blocking bun discovery. Use `./node_modules/.bin/vitest run <file>`
  (NOT `bun test`).

### Phase 1 — RED (write failing test first, per cq-write-failing-tests-before)
In `test/server/inngest/workspace-reconcile-on-push.test.ts`:
- The existing "no workspace match" test (lines 266–284) asserts `warnSilentFallbackSpy` is called.
  Re-point it (or add a sibling) to assert the path now goes through `mirrorWarnWithDebounce`.
- Add a **debounce** test: call the handler **twice** with the same `(installationId, fullName)` and
  zero workspaces within the window; assert the underlying warn-mirror fires **once**, and the second
  call is suppressed. Use `__resetMirrorDebounceForTests()` in `beforeEach` so cross-test state does not
  leak (mirror the dispatcher reset pattern).
- Add a **distinct-key** test: two different `(installationId, fullName)` pairs each mirror once (keys
  disjoint).
- Update the mock in `vi.mock("@/server/observability", ...)` (lines 86–90) to export
  `mirrorWarnWithDebounce` (and keep `__resetMirrorDebounceForTests` if asserting real dedup, OR spy
  `mirrorWarnWithDebounce` directly and assert call args/count — prefer the spy form for determinism,
  matching the existing `warnSilentFallbackSpy` style).

### Phase 2 — GREEN (handler edit)
In `workspace-reconcile-on-push.ts`, replace the `warnSilentFallback(...)` no-match call (lines 146–151)
with:

```ts
mirrorWarnWithDebounce(
  new Error("no workspace matched (installation_id, repo)"),
  {
    feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
    op: "skip-no-workspace-match",
    extra: { installationId, deliveryId, targetRepoUrl },
    message: "Reconcile skipped — no workspace connected to this repo",
  },
  `${installationId}:${targetRepoUrl}`,                      // in-process dedup token, never emitted
  "workspace-reconcile-push:no-workspace-match",             // distinct errorClass (registry below)
);
```

- Update the import on line 20: add `mirrorWarnWithDebounce` (keep `reportSilentFallback`; it is still
  used by the genuine-failure paths — `resolve-workspaces` error, `skip-not-ready`, `sync`).
- **Decide on the schema-version deadletter branch (lines 96–101):** it also calls `warnSilentFallback`
  on `op=deadletter-schema-version`. This is a one-time drain (v=1 events stop after ~24h replay), so it
  is naturally self-limiting and likely does NOT need debounce. Recommend **leave as-is** but note the
  decision in the plan body; if it is observed flooding, the same `mirrorWarnWithDebounce` treatment with
  errorClass `workspace-reconcile-push:deadletter-schema-version` applies. (Scope-out, not folded in —
  no evidence it floods.)

### Phase 3 — Registry + tsc
- Extend the `errorClass` registry docstring in `observability.ts:253–266` with the new
  `workspace-reconcile-push:no-workspace-match` entry (and the conditional deadletter one if Phase 2
  folds it in). This satisfies the registry-maintenance contract in the docstring.
- Run `./node_modules/.bin/tsc --noEmit` (or the package's typecheck script) — must be clean.

## Acceptance Criteria

### Pre-merge (PR)
- [x] `workspace-reconcile-on-push.ts` no-match path calls `mirrorWarnWithDebounce` with key
      `` `${installationId}:${targetRepoUrl}` `` and errorClass `workspace-reconcile-push:no-workspace-match`;
      verify via `grep -n "mirrorWarnWithDebounce" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` returns exactly 1 call site.
- [x] `grep -n "reportSilentFallback\|warnSilentFallback" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`
      still shows `reportSilentFallback` on the genuine-failure paths (resolve error / skip-not-ready /
      sync) — the debounce change MUST NOT touch those error-level mirrors.
- [x] Key-stability test: two identical-key no-match invocations produce the same dedup key (helper coalesces); the coalescing window itself is owned by `test/observability-mirror-debounce.test.ts` per the feature-flags precedent.
- [x] Distinct-key test: two different `(installationId, repoUrl)` → distinct keys (helper does not over-coalesce).
- [x] `errorClass` registry docstring in `observability.ts` lists the new entry.
- [x] `./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` — all 9 pass.
- [x] `tsc --noEmit` clean.
- [x] PR body uses `Closes #<issue>` if a tracking issue exists (this is a code fix, not ops-remediation).

### Post-merge (operator)
- [ ] None required. Deploy is the standard web-platform release (`web-platform-release.yml#migrate` is
      N/A — no migration). After deploy, the `workspace-reconcile-push` / `op=skip-no-workspace-match`
      Sentry stream should drop to ≤1 event per `(installationId, repoUrl)` per 5 min.
      Automation: post-deploy Sentry verification is a read-only API query (per hr-no-dashboard-eyeball);
      if a verification step is wanted, query the Sentry issues API filtered on
      `feature:workspace-reconcile-push op:skip-no-workspace-match` and assert event-count cadence — do
      NOT eyeball the dashboard.

## Observability

```yaml
liveness_signal:
  what: pino logger.warn on the FIRST no-match skip per (installationId, repoUrl) per 5-min window
        (debounced together with the Sentry mirror) → container stdout / Better Stack
  cadence: ≤1 per (installationId, repoUrl) per 5-min window (per-push repetition suppressed)
  alert_target: none (informational; the Sentry mirror is the alert surface)
  configured_in: apps/web-platform/server/observability.ts (mirrorWarnWithDebounce → warnSilentFallback)
error_reporting:
  destination: Sentry (warning level), now debounced ≤1 per (installationId, repoUrl) per 5 min
  fail_loud: false (expected no-op; intentionally debounced)
failure_modes:
  - mode: genuine workspace-resolve DB error
    detection: reportSilentFallback op=resolve-workspaces (error level, unchanged)
    alert_route: Sentry error budget
  - mode: workspace dir not provisioned
    detection: reportSilentFallback op=skip-not-ready (error level, unchanged)
    alert_route: Sentry error budget
  - mode: per-workspace sync failure
    detection: reportSilentFallback op=sync (error level, unchanged)
    alert_route: Sentry error budget
logs:
  where: container stdout (pino) → Better Stack; Sentry issues (debounced)
  retention: Sentry 30-90 days; Better Stack per plan
discoverability_test:
  command: ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts
  expected_output: all tests pass incl. debounce + distinct-key assertions
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — observability/tooling change at a single Inngest handler emit
site, reusing an existing debounce primitive. No new user-facing surface, no schema, no auth, no
regulated-data path.

## Risks & Mitigations

### Precedent diff (4.4 gate) — pattern is NOT novel

`mirrorWarnWithDebounce` is already in production use at `lib/feature-flags/server.ts:117` (#4571).
This plan adopts the **identical call shape**; verified side-by-side:

| Aspect | Flagsmith precedent (`server.ts:108-126`) | This plan (reconcile no-match) |
| --- | --- | --- |
| helper | `mirrorWarnWithDebounce(err, ctx, key, errorClass)` | same |
| dedup key (in-process, never emitted) | `` `${role}:${orgId ?? "__anon__"}` `` | `` `${installationId}:${targetRepoUrl}` `` |
| errorClass | `flagsmith:getidentityflags-timeout` | `workspace-reconcile-push:no-workspace-match` |
| TTL | shared `_mirrorDebounce`, 5-min `MIRROR_DEBOUNCE_MS` | same instance, same window |
| degradation kept on every occurrence | pino `logger.warn` | pino `logger.warn` |
| motivating alert | `auth-callback-no-code-burst` flood | same alert family |

The precedent comment even cites the **same** `auth-callback-no-code-burst` alert this bug report
names — confirming this is the same flood class with the same fix. No novel pattern; reviewers can
scrutinize the key-shape choice and errorClass uniqueness only.

- **Shared `_mirrorDebounce` map collision.** `mirrorWarnWithDebounce` and `mirrorWithDebounce` share
  one `TtlDedupMap`. Mitigation: the new `errorClass` (`workspace-reconcile-push:no-workspace-match`) is
  distinct from every registered class, so key spaces are disjoint (per the docstring contract). The
  key prefix `(installationId, repoUrl)` is also distinct from the flagsmith `(role, orgId)` shape.
- **Under-reporting a genuine onboarding gap.** If an install legitimately should have a workspace but
  doesn't (config drift), debounce caps the Sentry signal at 1/5min — but the per-occurrence
  `logger.warn` stdout signal is unbounded and queryable, so the diagnostic is not lost. This matches
  the #4571 precedent decision (tune the report, not the degradation).
- **Precedent fidelity.** `git grep` precedent: `mirrorWarnWithDebounce` already in production use at
  `lib/feature-flags/server.ts:117` (#4571). This plan adopts the identical call shape; no novel pattern.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above; threshold `none` with
  the server/** scope-out reason bullet.)
- Test runner is **vitest**, not bun — `apps/web-platform/bunfig.toml` blocks bun test discovery. Any AC
  that says `bun test <file>` reports "filter did not match" even when the file exists. Use
  `./node_modules/.bin/vitest run <path>`.
- The prior plan for this surface lives in
  `knowledge-base/project/plans/feat-one-shot-reconcile-no-workspace-match/plan.md`
  (`status: implemented`, PR #4597). It is the *severity* fix; this plan is the *volume* follow-up. Do
  not conflate or re-implement the error→warning swap — it is already on main.

## Open Code-Review Overlap

Two open `code-review` issues name `observability.ts` but neither overlaps this change:

- **#3739** (extract `reportSilentFallbackWithUser` helper to collapse 11-site userId-carrying
  `withIsolationScope+setUser` duplication) — **Acknowledge.** Different concern: it refactors
  *error-level userId-carrying* `reportSilentFallback` sites. The no-match path carries no userId and
  uses the warn-level debounce primitive; no shared edit. Scope-out remains open.
- **#3703** (add client-pii-grep CI + lefthook gate) — **Acknowledge.** Targets
  `lib/client-observability.ts` + `sentry.client.config.ts`, not the server emit site. No overlap.

No open issue touches `workspace-reconcile-on-push.ts` or the `mirrorWarnWithDebounce` /
`warnSilentFallback` server emit path.
