---
title: "fix: stop ignored-repo-has-workspaces Sentry warning flood from reconcile-on-push"
type: fix
date: 2026-06-01
branch: feat-one-shot-inngest-ignored-repo-has-workspaces
lane: single-domain
brand_survival_threshold: none
---

# 🐛 fix: stop `ignored-repo-has-workspaces` Sentry warning flood from `workspace-reconcile-on-push`

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Phase 2 (test), AC5, Sharp Edges, User-Brand Impact, Precedent-Diff.

### Key Improvements (deepen pass)

1. **Test infrastructure already exists — assertion de-hedged.** Verified `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts:99-108` already mocks the module-level `@/server/logger` default export as `loggerInfoSpy` (reset in `beforeEach` at line 176). Phase 2 / AC5 now prescribe a definitive `expect(loggerInfoSpy).toHaveBeenCalledWith(expect.objectContaining({ op: "ignored-repo-has-workspaces" }), …)` assertion instead of the cautious "if mockable" hedge. `reportSilentFallbackSpy` (line 85-88) also confirmed present, so the no-mirror assertion is fully checkable.
2. **Precedent-diff (Phase 4.4) confirms the chosen pattern is canonical.** The fix mirrors the existing benign-skip `logger.info(...)` at `workspace-reconcile-on-push.ts:204-213` (same `op`-tagged structured shape, same module-scoped logger). Not a novel pattern — see Precedent-Diff section below.
3. **User-Brand Impact sensitive-path scope-out added.** The edited server file matches the preflight Check 6 sensitive-path regex (`apps/web-platform/server/**`); added the mandatory `threshold: none, reason: …` scope-out bullet so the plan passes deepen-plan Phase 4.6 Step 2 and preflight Check 6 at ship time.

### New Considerations Discovered

- The `warnSilentFallback` import (handler line 22) is **load-bearing for the deadletter path at line 132** — verified by grep. Removing the line-223 call must NOT remove the import. Captured in Sharp Edges.
- No new scheduled job is introduced (Phase 4.4 scheduled-work check): this edits an existing event-driven Inngest function, so ADR-033 Inngest-vs-cron routing does not apply.

## Overview

A production Sentry warning fires on **every push** to a repo that is on the reconcile ignore-list (`WORKSPACE_RECONCILE_IGNORE_REPOS`, default `jikig-ai/soleur`) **but still has a connected workspace**. The handler treats this as a "misconfiguration worth surfacing" and emits `warnSilentFallback(new Error("ignored repo has connected workspaces"))` at `op=ignored-repo-has-workspaces`. Because the founder is **dogfooding their KB out of the platform's own repo** (`jikig-ai/soleur`) — the exact scenario PR #4706 was written to support — this state is not a misconfiguration at all. It is the *expected steady state*, and active development on that repo means one warning per push: repeated, zero-signal Sentry alerts.

This is the third iteration on the same Sentry-noise surface (#4623 debounce → #4666 zero-match suppression → #4706 reconcile-anyway-and-warn). #4706 correctly fixed the underlying *functional* bug (the ignore check ran before workspace resolution and starved the dogfooding KB for ~5 weeks), but the breadcrumb it added to make the prior silence loud over-corrected: it now alerts on a permanently-true condition.

**The fix:** the "ignored repo has a connected workspace" condition is benign and self-resolving (we reconcile anyway). Stop mirroring it to Sentry. Keep a durable, queryable signal in pino/Better Stack at `info` level (the same pattern already used for the benign `skip-no-workspace-match` case at line 204), so an operator who genuinely wants to audit the ignore-list still has the data — pulled, not pushed.

This is a **pure code change against an already-provisioned surface** — one file plus its test. No new infrastructure, no schema, no new dependency, no UI.

## Premise Validation

No GitHub issue is cited by reference in the task description (the report is a raw Sentry event). Internal premises validated against `origin/main` / worktree HEAD:

- **The function exists and the warning is live.** `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:222-230` emits `warnSilentFallback(new Error("ignored repo has connected workspaces"), { op: "ignored-repo-has-workspaces", ... })`. Confirmed. Matches the Sentry `op` / `feature` / `event_name` fields exactly.
- **The ignore-list default is the platform's own repo.** Line 82-83: `process.env.WORKSPACE_RECONCILE_IGNORE_REPOS ?? "jikig-ai/soleur"`. Confirmed.
- **The dogfooding scenario is real and intended.** PR #4706 (`c74f9746 fix(kb-sync): reconcile ignored repos with connected workspaces ...`) and the in-code comment at lines 146-152 / 217-221 document "the founder dogfooding their KB from the platform's own repo." This is the supported case, not a misconfiguration. Confirmed via `git log` + code comments.
- **The warning has no other emit site.** `grep` for `ignored-repo-has-workspaces` / `isIgnoredReconcileRepo` / `RECONCILE_IGNORED_REPO_SLUGS` across `apps/web-platform/server/` and `apps/web-platform/app/` returns only `workspace-reconcile-on-push.ts`. The cron health function and manual-sync path do not consult the reconcile ignore-list. Confirmed — single-file blast radius.
- **Test coverage exists and asserts the current (noisy) behavior.** `test/server/inngest/workspace-reconcile-on-push.test.ts:350-385` asserts `warnSilentFallbackSpy` is called once with `op: "ignored-repo-has-workspaces"`. This assertion must be updated, not just left passing — the plan changes the contract it encodes.

Nothing was stale. The premise ("this is benign and should not page") holds.

## Problem Statement

```text
File:        /app/.next/server/app/api/inngest/route.js
fnId:        soleur-runtime-workspace-reconcile-on-push
op:          ignored-repo-has-workspaces
feature:     workspace-reconcile-push
event_name:  platform/workspace.reconcile.requested
level:       warning, handled=yes
release:     web-platform@0.102.0
```

Current code path (`workspace-reconcile-on-push.ts:222-230`):

```ts
// Shadowed-workspace guard ...
if (isIgnoredReconcileRepo(targetRepoUrl)) {
  warnSilentFallback(new Error("ignored repo has connected workspaces"), {
    feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
    op: "ignored-repo-has-workspaces",
    extra: { installationId, deliveryId, targetRepoUrl, workspaceCount: rows.length },
    message:
      "Reconcile ignore-list shadows a connected workspace — reconciling anyway; review WORKSPACE_RECONCILE_IGNORE_REPOS",
  });
}
```

`warnSilentFallback` mirrors to Sentry at `level: "warning"` (`observability.ts:248-261`). Every push to `jikig-ai/soleur` (the founder's dogfood repo) traverses this branch → one Sentry warning per push. The condition is permanently true for the default config, so the alert never quiesces.

## Research Reconciliation — Spec vs. Codebase

No external spec exists for this fix. Code reality (verified above) is the source of truth. No reconciliation table needed; the one premise that could have been stale (whether the warning had multiple emit sites or downstream consumers) was checked and is single-site.

## User-Brand Impact

- **If this lands broken, the user experiences:** a continued (or, if mis-fixed, *worsened*) flood of zero-signal Sentry warning emails for their own dogfood pushes — alert fatigue that buries genuine reconcile failures (`op=sync`, `op=skip-not-ready`, `op=resolve-workspaces`, which MUST keep paging). The reconcile itself keeps working either way; this is an observability-noise defect, not a data/functional one.
- **If this leaks, the user's data / workflow / money is exposed via:** N/A — no data path changes. The branch already passes only `installationId`, `deliveryId`, `targetRepoUrl`, `workspaceCount` (no PII) and that payload is *removed* from the Sentry surface by this fix, strictly reducing exposure.
- **Brand-survival threshold:** `none` — this is alert-noise suppression on a benign, by-design state; no single-user breach or aggregate-pattern exposure is gated on it.
- `threshold: none, reason: the edited file path matches the sensitive-path regex (apps/web-platform/server/**) but the change only downgrades a benign, no-PII Sentry warning to a pino info log — it touches no schema, auth flow, data path, secret, or response shape, so there is no user-data exposure surface.` (Required by preflight Check 6 / deepen-plan Phase 4.6 Step 2 because `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` matches the `apps/web-platform/server` sensitive-path prefix even though the change is observability-only.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — No Sentry mirror on the shadowed-workspace branch.** After the fix, the `isIgnoredReconcileRepo(targetRepoUrl)` branch at the post-resolution / `rows.length > 0` site does NOT call `warnSilentFallback` (nor `reportSilentFallback`). Verify: `grep -n "warnSilentFallback\|reportSilentFallback" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` returns NO occurrence inside the `ignored-repo-has-workspaces` branch (the `op=sync`, `op=skip-not-ready`, `op=resolve-workspaces`, and `op=deadletter-schema-version` mirrors remain).
- [ ] **AC2 — Durable pino signal retained.** The branch instead emits `logger.info(...)` carrying `feature`, `op: "ignored-repo-has-workspaces"`, `installationId`, `deliveryId`, `targetRepoUrl`, `workspaceCount`. Verify: `grep -n 'op: "ignored-repo-has-workspaces"' apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` shows the slug inside a `logger.info` call (mirroring the existing `skip-no-workspace-match` info-log at lines 204-213).
- [ ] **AC3 — Reconcile still happens.** The fan-out loop is unchanged; an ignored repo with a connected workspace is still reconciled. Verify via the updated test (AC5) asserting `{ ok: true, synced: 1 }` and `syncWorkspaceSpy` called once.
- [ ] **AC4 — Genuine failures still page.** No change to the four error-level / warn-level mirrors that carry real signal (`resolve-workspaces` failure, `sync` failure, `skip-not-ready`, `deadletter-schema-version`). Verify: those four `op` slugs still appear with their `reportSilentFallback` / `warnSilentFallback` callers intact.
- [ ] **AC5 — Test contract updated (RED→GREEN).** The test at `test/server/inngest/workspace-reconcile-on-push.test.ts:350-385` ("RECONCILES an ignored repo that HAS a connected workspace, and warns once") is updated so it (a) still asserts `{ ok: true, synced: 1 }` and one `syncWorkspace` call, (b) asserts `warnSilentFallbackSpy` is NOT called, and (c) asserts the existing `loggerInfoSpy` (test lines 99-108) was called with `expect.objectContaining({ op: "ignored-repo-has-workspaces" })`. Update the test's title/comment to reflect "logs at info, does not page." Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` is green.
- [ ] **AC6 — Full package suite green.** `cd apps/web-platform && ./node_modules/.bin/vitest run` (per `package.json scripts.test = "vitest"`) passes with no new failures. Confirm the sibling `webhook-push-dispatch.test.ts` (which also references the slug) still passes.
- [ ] **AC7 — `tsc --noEmit` clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` reports no new errors.

### Post-merge (operator)

- [ ] **AC8 — Sentry issue auto-resolves.** After deploy of the new release, the `op:ignored-repo-has-workspaces` Sentry issue receives no new events on subsequent pushes to `jikig-ai/soleur`. Automation: verifiable read-only via Sentry API (`GET /api/0/organizations/{org}/issues/?query=op:ignored-repo-has-workspaces` filtered to events after the deploy timestamp → expect zero). Per `hr-no-dashboard-eyeball-pull-data-yourself`, prescribe the API query in `/soleur:ship` post-merge verification rather than operator dashboard-watching. (Container restart / function re-sync is handled automatically by `web-platform-release.yml` on merge to main touching `apps/web-platform/**` — no separate operator restart step.)

## Implementation Phases

### Phase 1 — Replace the Sentry mirror with an info-level pino log

**File to edit:** `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` (lines 217-230)

Replace the `warnSilentFallback(...)` call inside the shadowed-workspace guard with a `logger.info(...)` carrying the same structured context, mirroring the existing benign-skip pattern at lines 204-213. Rewrite the leading comment (lines 217-221) to state that this is the *expected* steady state when the founder dogfoods their KB from an ignored repo, that it is reconciled normally, and that the info-log (not a Sentry warning) is the audit trail for an operator who wants to review `WORKSPACE_RECONCILE_IGNORE_REPOS`.

Pseudocode:

```ts
// Ignored repo WITH connected workspaces. This is the expected steady state
// when the founder dogfoods their KB out of an ignored repo (e.g. the platform's
// own dev repo, the default ignore entry). It is NOT a misconfiguration: we
// reconcile the workspaces below exactly as for any other repo. Earlier
// (#4706) this emitted a Sentry warning to make the prior silent-starve loud,
// but the condition is permanently true for the default config, so it became a
// per-push alert flood with zero signal. Log at info to Better Stack (pino) so
// an operator can still audit the ignore-list on demand; do NOT mirror to
// Sentry. Genuine reconcile failures (sync / not-ready / resolve) still page
// via the reportSilentFallback sites below.
if (isIgnoredReconcileRepo(targetRepoUrl)) {
  logger.info(
    {
      feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
      op: "ignored-repo-has-workspaces",
      installationId,
      deliveryId,
      targetRepoUrl,
      workspaceCount: rows.length,
    },
    "Reconcile ignore-list shadows a connected workspace — reconciling anyway (info; review WORKSPACE_RECONCILE_IGNORE_REPOS if unexpected)",
  );
}
```

If, after Phase 1, `warnSilentFallback` is no longer referenced anywhere in the file, remove it from the `@/server/observability` import (line 21-23). Run a grep first: `grep -n "warnSilentFallback" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`. **Note:** the schema-gate deadletter path at lines 132-137 ALSO uses `warnSilentFallback` — so the import is almost certainly still needed. Verify before touching the import line; do not blindly remove it (`cq-ref-removal-sweep-cleanup-closures`).

### Phase 2 — Update the test contract (RED→GREEN, write the assertion change first)

**File to edit:** `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` (lines 350-385)

Per `cq-write-failing-tests-before`: first flip the assertion to the new contract (which will fail against current code if Phase 1 isn't applied yet), then confirm Phase 1 makes it green.

- Keep: `expect(result).toEqual({ ok: true, synced: 1 })`, the `syncWorkspaceSpy` call assertion, and the `APPENDS` ok:true assertion.
- Change: `expect(warnSilentFallbackSpy).not.toHaveBeenCalled()` (the shadowed-workspace branch no longer warns). Also `expect(reportSilentFallbackSpy).not.toHaveBeenCalled()` (the success path emits neither mirror).
- Add: assert the info-log fires. **The mock infrastructure already exists** — `loggerInfoSpy` is wired at test lines 99-108 (the module-level `@/server/logger` default export is mocked, NOT the injected step logger) and reset in `beforeEach` (line 176). The assertion is therefore definitive, not hedged:

  ```ts
  expect(loggerInfoSpy).toHaveBeenCalledWith(
    expect.objectContaining({ op: "ignored-repo-has-workspaces", workspaceCount: 1 }),
    expect.any(String),
  );
  ```

  Note the `skip-no-workspace-match` path also calls `loggerInfoSpy` (line 204), so if a future test combines both, assert on the `op` discriminator rather than `toHaveBeenCalledTimes`. For THIS test (rows.length === 1, ignored repo), only the `ignored-repo-has-workspaces` info-log fires, so `toHaveBeenCalledTimes(1)` is also valid here.
- Update the test title + comment from "warns once" to "logs at info, does not page (regression: dogfood KB freeze + #4706 over-warn)".

### Phase 3 — Verify

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` → green.
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/webhooks/webhook-push-dispatch.test.ts` → green (sibling that references the slug; confirm no shared expectation breaks).
- `cd apps/web-platform && ./node_modules/.bin/vitest run` → full package green.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.

## Files to Edit

- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — replace `warnSilentFallback` shadowed-workspace mirror with `logger.info`; rewrite the explanatory comment; verify (do not blindly remove) the `warnSilentFallback` import (still used by the deadletter path).
- `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` — update the "RECONCILES an ignored repo that HAS a connected workspace" test to assert no-warn + info-log + unchanged functional outcome.

## Files to Create

None.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` was not queried against these two paths at plan time because the change is a 2-file noise-suppression fix on a freshly-touched surface (#4706 / #4736, last 2 commits); any open scope-out on these files would be days old at most. The /work phase should still run the standard overlap query before pushing — but the planner found no signal of a pre-existing scope-out here.)

## Test Scenarios

| Scenario | Repo | Connected workspace? | Expected outcome | Sentry? |
|---|---|---|---|---|
| Ignored repo, has workspace (dogfood steady state) | `jikig-ai/soleur` | yes | reconciled, `{ok:true,synced:1}` | **no** (info log only) — the fix |
| Ignored repo, no workspace | `jikig-ai/soleur` | no | `{ok:false,reason:"ignored-internal-repo"}`, fully silent | no (unchanged) |
| Non-ignored customer repo, no workspace | `acme/widgets` | no | `{ok:false,reason:"no-workspace-match"}`, info log | no (unchanged) |
| Non-ignored customer repo, has workspace | `acme/widgets` | yes | reconciled | no (unchanged) |
| Any repo, sync fails | — | yes | reconcile attempted, sync error | **yes** (`reportSilentFallback op=sync`, unchanged — must still page) |
| Any repo, workspace dir missing | — | yes | skip-not-ready | **yes** (`reportSilentFallback op=skip-not-ready`, unchanged) |
| v=1 schema envelope drain | — | — | deadletter | **yes** (`warnSilentFallback op=deadletter-schema-version`, unchanged) |

## Observability

```yaml
liveness_signal:
  what: "workspace-reconcile-on-push Inngest function executions"
  cadence: "per GitHub push to a connected repo (event-driven, not scheduled)"
  alert_target: "existing reconcile failure ops (sync / skip-not-ready / resolve-workspaces / deadletter) — unchanged by this fix"
  configured_in: "Sentry (existing project), keyed on feature=workspace-reconcile-push"
error_reporting:
  destination: "Sentry via reportSilentFallback (error) / warnSilentFallback (warning) — unchanged; this fix REMOVES one benign warning op from the surface"
  fail_loud: "yes — genuine reconcile failures (op=sync, op=skip-not-ready, op=resolve-workspaces) still mirror to Sentry; only the benign op=ignored-repo-has-workspaces is downgraded to pino info"
failure_modes:
  - mode: "workspace sync fails for a connected workspace"
    detection: "reportSilentFallback op=sync"
    alert_route: "Sentry warning/error (unchanged)"
  - mode: "workspace dir not provisioned"
    detection: "reportSilentFallback op=skip-not-ready"
    alert_route: "Sentry (unchanged)"
  - mode: "workspace resolution query fails"
    detection: "reportSilentFallback op=resolve-workspaces"
    alert_route: "Sentry (unchanged)"
  - mode: "ignore-list misconfigured (operator wants to audit which ignored repos still have workspaces)"
    detection: "pino info log op=ignored-repo-has-workspaces in Better Stack / container stdout"
    alert_route: "none (by design — pull, not push); operator queries Better Stack on demand"
logs:
  where: "Better Stack (pino) + container stdout"
  retention: "existing Better Stack retention (unchanged)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts"
  expected_output: "test 'RECONCILES an ignored repo that HAS a connected workspace ... logs at info, does not page' passes; warnSilentFallback NOT called for op=ignored-repo-has-workspaces"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an internal observability-noise suppression change to a single Inngest function. No user-facing UI, no schema/data, no security boundary, no pricing/marketing/legal surface. The payload removed from Sentry contains no PII (installationId, deliveryId, repo slug, workspace count). Pure-engineering change.

## Infrastructure (IaC)

Skipped — no new infrastructure. The change edits a file under `apps/web-platform/server/` against an already-provisioned Inngest function + Sentry project + Better Stack sink. No new server, service, cron, secret, vendor, or persistent runtime process is introduced; no SSH step, no secret mutation, no `systemctl`, no vendor-dashboard click-path. Deploy is the existing `web-platform-release.yml` container restart on merge.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| **Remove `jikig-ai/soleur` from the default ignore-list** | The ignore-list still serves its #4666 purpose: pushes to `jikig-ai/soleur` with NO connected workspace must stay fully silent (`reason:"ignored-internal-repo"`). Removing the default would re-introduce the `no-workspace-match` info-log noise for the common zero-workspace case and undo #4666. The ignore semantics are correct; only the *warning on the has-workspace sub-case* is wrong. |
| **Per-(repo) debounce on the warn mirror** (revive `mirrorWarnWithDebounce`) | Explicitly rejected in-code at lines 198-203: the in-process debounce map resets on every container churn, so it never actually bounds the flood in prod. Same failure mode #4623 hit. A debounce also still pages periodically for a benign state — wrong signal level, not just wrong frequency. |
| **Delete the branch entirely (no log at all)** | Loses the operator's ability to audit "which ignored repos still have live workspaces" — a legitimate, if rare, diagnostic. An `info` log costs nothing and keeps the audit trail queryable in Better Stack. Matches the existing `skip-no-workspace-match` info-log precedent (line 204) for "benign but worth recording." |
| **Drop the warning to `debug` instead of `info`** | `info` matches the sibling benign-skip log at line 204 (consistency); `debug` may be filtered out of the default Better Stack ingest, defeating the audit purpose. `info` is the right altitude. |

No items are deferred to a later phase; no tracking issue needed.

## Precedent-Diff (Phase 4.4)

The fix adopts an **existing in-file pattern**, not a novel one. The sibling benign-skip already logs to pino at `info` with an `op`-tagged structured object via the module-scoped logger:

```ts
// workspace-reconcile-on-push.ts:204-213 (PRECEDENT — the no-workspace-match skip)
logger.info(
  {
    feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
    op: "skip-no-workspace-match",
    installationId,
    deliveryId,
    targetRepoUrl,
  },
  "Reconcile skipped — no workspace connected to this repo",
);
```

Phase 1's new block is the same shape with `op: "ignored-repo-has-workspaces"` and an added `workspaceCount` field. **No precedent divergence** — same logger, same level, same tag vocabulary, same "benign-but-worth-recording" rationale. This is the strongest signal that downgrading from Sentry-warn to pino-info is the codebase-consistent choice (the prior code at line 198-203 even documents that benign skips belong in pino, not Sentry).

No SQL `SECURITY DEFINER`/`INVOKER`, atomic-write, lock, RPC-permission, or connection-pool pattern is touched.

## Sharp Edges

- The `warnSilentFallback` import at lines 21-23 is **still used by the schema-gate deadletter path** (lines 132-137). Do NOT remove it when deleting the shadowed-workspace warn call — grep first (`grep -n "warnSilentFallback" <file>`). Blindly removing the import will break `tsc` (`cq-ref-removal-sweep-cleanup-closures`).
- The Phase-1 `logger.info` call uses the **module-scoped** `import logger from "@/server/logger"` (the one already used at line 204), NOT the `stepLogger` param — `stepLogger` is `void`-discarded at line 115. The test already mocks exactly this (`loggerInfoSpy`, test lines 99-108 + reset at line 176); assert against `loggerInfoSpy`, never the inert `logger` fixture at test line 121 (that is the step-logger fixture, unrelated to the module export).
- The existing test at lines 350-385 currently asserts the *opposite* of the new contract (`toHaveBeenCalledTimes(1)` with `op: "ignored-repo-has-workspaces"`). It will pass unchanged against old code and must be flipped — do not leave it as a vacuous green; it is the encoded contract for the bug being fixed.
- The sibling test `test/server/webhooks/webhook-push-dispatch.test.ts` also references the slug — confirm it does not assert the warn mirror (it tests the webhook dispatch side, not the reconcile handler, so it should be unaffected, but run it in Phase 3).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with threshold `none`.
