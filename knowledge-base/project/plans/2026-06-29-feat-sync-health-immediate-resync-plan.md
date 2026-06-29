---
title: "feat: immediate re-sync after arm-1 backfill (#5689 item 2)"
issue: 5689
parent_issue: 5675
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-29-sync-health-immediate-resync-brainstorm.md
spec: knowledge-base/project/specs/feat-sync-health-immediate-resync/spec.md
branch: feat-sync-health-immediate-resync
pr: 5696
plan_review: applied (DHH + Kieran + code-simplicity, 2026-06-29)
---

# feat: immediate re-sync after arm-1 backfill (#5689 item 2)

## Overview

Arm-1 of `cron-workspace-sync-health.ts` (#5675/#5684) backfills a missing
`github_installation_id` onto solo `repo_status='ready'` workspaces, restoring
webhook **reachability** — but it does not sync the current default-branch HEAD.
For a low-activity solo repo the KB stays stale for days (until the next push)
while the UI claims "ready/connected." **Approach A (CTO+CPO+CLO consensus):**
right after a successful backfill, call the existing `syncWorkspace()` helper
**inside arm-1's existing per-workspace `step.run` boundary**, then write a
truthfully-labeled `kb_sync_history` audit row. **On a successful sync, lag: days
→ 0.** (On sync *failure* the row is not re-synced by arm-1 — see re-entrancy note
in 2.5 / Sharp Edges — loudness then comes from arm-2's `stale-sync-failed`
signal, not a retry.)

**Scope is item 2 ONLY.** Item 1 (producer investigation) is soak-gated until
~2026-07-06 (arm-1 merged 2026-06-29T13:06:55Z) and stays OPEN under #5689 — do
not plan or implement it here.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Pass `{userId: ownerId ?? workspaceId}`, mirror reconcile-on-push's owner/owner-less branch | **Arm-1 has no `ownerId`** — it resolves only `ownerLogin` = github_username (`:263`, consumed `:282`). reconcile-on-push's `ownerId` comes from a `workspace_members` lookup arm-1 never does. Arm-1 only reconciles `isSolo` findings (`decideArm1Reconcile` skips team, `:162-163`), and for solo `workspaces.id === users.id` (ADR-038 N2). | **Single path, no owner lookup:** `userId: f.workspaceId`; `appendKbSyncRowForWorkspace(service, f.workspaceId, row)` (p_user_id = workspaceId = users.id, `session-sync.ts:741`). |
| Pass arm-1's handler `logger` to `syncWorkspace` | `syncWorkspace`'s 3rd param is a pino `Logger` (`workspace-sync.ts:103`); arm-1's handler logger is the loose `{info,warn,error}` shape (`_cron-shared.ts:95`) — not assignable. | Import the module logger (`import logger from "@/server/logger"`) and pass THAT, mirroring reconcile-on-push (`:38/:331`). |
| `op` value for the sync | `op` is a **closed union** `"delete"\|"rename"\|"upload"\|"push"\|"manual"` (`:105`) → Sentry slug `workspace-sync-${op}` (`:155`). System resyncs already use `op:"manual"` (`c4-writer.ts:126,315`). | **Reuse `op:"manual"`** (codebase precedent; no second union widening). The truthful discriminator is the audit `trigger`, not the op slug. |
| New `kb_sync_history` trigger value | `trigger` TS union `"webhook_push"\|"manual"\|"session"` (`session-sync.ts:639`); column free-form JSONB (mig 017, no CHECK). Grep confirms **nothing reads/switches on `trigger`** (write-only; sparkline uses `{date,count}`, KbSyncStatus discriminates on `ok`/shape). | Widen union → add `"reconcile_backfill"`. No migration. |
| Reuse `workspaceDirExists` | **Private, un-exported** local in reconcile-on-push (`:103`); no shared copy. (`workspacePathForWorkspaceId` `:792` and `syncWorkspace` ARE exported — OK.) | Duplicate the ~6-line `fs.stat().isDirectory()` inline in arm-1 (taste: duplication > coupling), or extract to `workspace-resolver.ts`. Plan picks **inline duplicate**. |
| Audit row shape | `SyncWorkspaceResult = {ok:true, recovered?} \| {ok:false, error, errorClass}` (`:24`). reconcile-on-push writes `ok` + `error_class: syncResult.errorClass` (`:355`). | FR4 mirrors that shape exactly. |

## Implementation Phases

### Phase 1 — Type widening (contract first)
1.1 Widen `kb_sync_history` `trigger` union at `session-sync.ts:639` → add
   `"reconcile_backfill"`. `git grep -n '"webhook_push"'` apps + test to confirm
   write-only (verified at plan time; re-confirm at /work).

### Phase 2 — Arm-1 in-arm re-sync
2.1 In the `decision.kind === "reconciled"` branch of
   `reconcile-${f.workspaceId}` (`cron-workspace-sync-health.ts:289-295`), after
   `writeRepoColsToWorkspace` commits the backfill, derive
   `workspacePathForWorkspaceId(f.workspaceId)` (`workspace-resolver.ts:792`).
2.2 Guard with an inline `workspaceDirExists` (duplicate the `fs.stat().isDirectory()`
   shape from reconcile-on-push `:103`). On **missing dir**, write the audit row
   with `error_class: ERROR_CLASS_WORKSPACE_NOT_READY`, `ok:false` — do **not** throw.
2.3 On dir present, import the module logger and call
   `syncWorkspace(decision.installId, path, logger, {userId: f.workspaceId, op: "manual"})`.
   (Solo invariant: `f.workspaceId === users.id`, ADR-038 N2 — `userId` is a real
   user id here, not a mislabel.)
2.4 Append a `kb_sync_history` row via `appendKbSyncRowForWorkspace(service,
   f.workspaceId, row)` with `trigger: "reconcile_backfill"`, `ok`, and
   `error_class: result.errorClass` on failure.
2.5 On `result.ok === false`, mirror to Sentry via `reportSilentFallback`
   (feature `SENTRY_FEATURE` = `workspace-sync-health`, op `reconcile-backfill-sync`)
   and **continue** the loop — do not abort the cron. Backfill is already committed,
   so the row leaves arm-1's `repo_status='ready' AND github_installation_id IS NULL`
   scan (`:209-211`): a failed sync never re-backfills and **arm-1 will not re-sync
   it** on a later fire. Heal of a *failed* sync is therefore push-driven; arm-2
   (`scan-stale-sync-failed`) provides the standing loudness in the meantime.
2.6 Extend the arm-1 completion log (`{reconciled, skipped, transient}`, `:325-327`)
   with a `synced` count — the only positive-liveness signal (Sentry fires only on
   failure; `reconciled − synced` is an at-a-glance failure count, no query).

### Phase 3 — Tests (`test/server/inngest/cron-workspace-sync-health.test.ts`)
3.1 Reconciled solo workspace (dir present) → backfill AND `kb_sync_history` row
   `{trigger:"reconcile_backfill", ok:true}`; assert in the same test that arm-1
   emits **no Inngest event** (I6).
3.2 Reconciled workspace, missing dir → row `ERROR_CLASS_WORKSPACE_NOT_READY`,
   step does not throw.
3.3 Re-fire after successful backfill → no second sync (row no longer matches scan
   predicate).
3.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green (AC gate).

## Files to Edit
- `apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts` — arm-1 in-arm sync + inline `workspaceDirExists` + module-logger import (Phase 2).
- `apps/web-platform/server/session-sync.ts` — widen `trigger` union (1.1).
- `apps/web-platform/test/server/inngest/cron-workspace-sync-health.test.ts` — tests (Phase 3).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — one-line note on the existing 2026-06-29 reconcile amendment (see below).

## Files to Create
- None.

## User-Brand Impact

**If this lands broken, the user experiences:** a reconciled solo workspace whose
KB tree stays empty/stale even though the UI says "ready" — or, if the sync write
mis-fires, a corrupted/duplicated `kb_sync_history` audit trail.
**If this leaks, the user's data is exposed via:** N/A — the sync pulls the user's
own connected repo into the user's own workspace (same tenant/region, no
cross-tenant flow); CLO confirmed no new processing.
**Brand-survival threshold:** single-user incident.

> CPO sign-off carried forward from the 2026-06-29 brainstorm (item 2 approved to
> ship now at single-user-incident threshold). `user-impact-reviewer` runs at PR review.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — carried forward from brainstorm `## Domain Assessments`.

### Engineering (CTO)
**Status:** reviewed (carry-forward) — Approach A dominates the synthetic-event path (vacuous + breaks I6); preserves I1/I6, no migration. Watch step duration; fallback A′ (defer to arm-3) only if soak shows step times creeping.
### Product (CPO)
**Status:** reviewed (carry-forward) — broken onboarding promise → single-user incident; ship now, independent of the item-1 soak; silent self-heal, no user notification.
### Legal (CLO)
**Status:** reviewed (carry-forward) — no material legal surface; audit row must carry a truthful trigger (satisfied by `reconcile_backfill`).

### Product/UX Gate
**Tier:** none — no UI surface in Files to Edit (Inngest cron only).

## GDPR / Compliance Gate (Phase 2.7)
CLO assessed at brainstorm: no new processing (user's own repo → own workspace, same tenant/region, no new sub-processor/data category). No regulated-data surface in Files to Edit. Disposition: CLO clearance; deepen-plan may re-confirm.

## Infrastructure (IaC) (Phase 2.8)
None — pure code change against an already-provisioned cron.

## Observability

```yaml
liveness_signal:
  what: arm-1 completion log gains a `synced` count alongside reconciled/skipped/transient
  cadence: daily (cron-workspace-sync-health fire)
  alert_target: Better Stack (pino info) — no new alert
  configured_in: cron-workspace-sync-health.ts:325-327
error_reporting:
  destination: Sentry via reportSilentFallback (feature SENTRY_FEATURE="workspace-sync-health", op "reconcile-backfill-sync")
  fail_loud: true — pages automatically via the EXISTING feature-only alert `workspace_sync_health` (apps/web-platform/infra/sentry/issue-alerts.tf:508-540, no op filter). NO new tf owed.
failure_modes:
  - mode: in-arm syncWorkspace returns ok:false (sync_failed)
    detection: kb_sync_history row {trigger:"reconcile_backfill", ok:false, error_class}
    alert_route: Sentry feature-only alert workspace_sync_health (op "reconcile-backfill-sync")
  - mode: reconciled workspace has no dir (ready row, missing dir)
    detection: kb_sync_history row error_class ERROR_CLASS_WORKSPACE_NOT_READY
    alert_route: same feature-only alert
logs:
  where: Better Stack (pino) + kb_sync_history (Supabase, trigger="reconcile_backfill")
  retention: kb_sync_history capped per append_kb_sync_row cap; Better Stack per plan
discoverability_test:
  command: Supabase MCP — count kb_sync_history rows where trigger='reconcile_backfill' and ok=false (NO ssh)
  expected_output: 0 residual failures post-soak; non-zero is the in-arm-sync failure signal
```

**Same-fire double-signal (acknowledged, benign):** a failed in-arm sync writes the
latest `{trigger:"reconcile_backfill", ok:false}` row; later in the SAME fire arm-2
`scan-stale-sync-failed` reads that latest row (`:396-401`) and also emits
`stale-sync-failed` — both under `feature=workspace-sync-health`. Sentry folds by
fingerprint and the feature-only alert pages once; no action needed.

## Architecture Decision (ADR/C4)

Not a new architectural decision. `workspace-reconcile-on-push` **already performs
this exact git pull today**; arm-1 doing it a few hours earlier is a latency change
within ADR-033 I1/I6 (no event, no new edge/actor), not a new boundary.

- **ADR:** append **one sentence** to ADR-044's existing 2026-06-29 solo-backstop
  reconcile amendment ("arm-1 also performs an immediate in-arm `syncWorkspace`
  after backfill, audited under the `reconcile_backfill` trigger; I6 preserved").
  Not a formal new amendment, not a PR-gating AC.
- **C4 views:** **no element/edge change** (checked all three `.c4`): `founder`
  actor (`model.c4:8`), `github` system (`:171`), Supabase store, and the
  solo-Owner→own-workspace access relationship are all unchanged and already
  modeled; crons are modeled at `inngest`-container granularity. The git pull
  reuses GitHub, already exercised by reconcile-on-push.

## Acceptance Criteria (Pre-merge)
- [x] AC1: Reconciled solo workspace (dir present) → backfilled `github_installation_id` AND `kb_sync_history` row `{trigger:"reconcile_backfill", ok:true}`; same test asserts no Inngest event (test 3.1).
- [x] AC2: Reconciled workspace, missing dir → row `ERROR_CLASS_WORKSPACE_NOT_READY`, step does not throw (test 3.2).
- [x] AC3: Re-fire after successful backfill → no second sync (test 3.3).
- [x] AC4: Failed in-arm sync mirrors to Sentry and does NOT abort the cron (other findings still process).
- [x] AC5: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green after the `trigger` widening.

## Open Code-Review Overlap
None — 63 open `code-review` issues queried (2026-06-29); none reference `cron-workspace-sync-health`, `workspace-sync`, or `session-sync`.

## Test Scenarios
Phase 3 (3.1–3.4). Runner: vitest via `apps/web-platform/vitest.config.ts` (`test/**/*.test.ts`); the existing `test/server/inngest/cron-workspace-sync-health.test.ts` is on-glob.

## Sharp Edges
- `op` is a closed union reaching a Sentry slug — pass `op:"manual"` (system-resync convention, `c4-writer.ts:126/315`), never a free-form string.
- `syncWorkspace` needs the pino **module** logger (`@/server/logger`), NOT arm-1's handler logger — or tsc fails (Kieran P1-2).
- Arm-1 has no `ownerId` — use `f.workspaceId` directly (solo: `=== users.id`, ADR-038 N2); do NOT copy reconcile-on-push's owner/owner-less branch (Kieran P1-1).
- `workspaceDirExists` is private in reconcile-on-push — duplicate inline (Kieran P2-1).
- Backfill MUST commit before the sync (re-entrancy). On sync *failure* arm-1 does NOT retry; "days→0" applies to successful syncs only (Kieran P2-4).
- Three files share the `ADR-033` number — cite the cron-invariants doc by filename.
- Plan-review dissent recorded: Kieran verified widening `op→"reconcile"` would also be safe (no slug-enumerating alert); not adopted because the `trigger` value + dedicated `reconcile-backfill-sync` op already discriminate (DHH + code-simplicity, 2-1).
