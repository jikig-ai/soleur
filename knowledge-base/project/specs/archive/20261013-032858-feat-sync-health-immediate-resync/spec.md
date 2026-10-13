---
feature: sync-health-immediate-resync
issue: 5689
parent_issue: 5675
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-06-29-sync-health-immediate-resync-brainstorm.md
---

# Spec: Immediate re-sync after arm-1 backfill (#5689 item 2)

## Problem Statement

Arm-1 of `cron-workspace-sync-health.ts` (#5675/#5684, merged 2026-06-29) backfills
a missing `github_installation_id` onto solo `repo_status='ready'` workspaces,
repairing webhook **reachability**. But it does not sync the current default-branch
HEAD — the workspace's KB stays stale until the **next** push. For a low-activity
solo repo (connect-and-walk-away), that is days, while the UI claims "ready/connected."
This is a single-user-incident-grade broken onboarding promise.

## Goals

- After a successful arm-1 backfill, immediately sync the workspace's current
  default-branch HEAD so the KB matches what the UI promises.
- Record the sync truthfully in `kb_sync_history` with a distinct, non-`webhook_push`
  trigger value.
- Preserve ADR-033 invariants I1 (all IO inside `step.run`) and I6 (arm-1 emits no
  Inngest events).

## Non-Goals

- **Item 1 (producer investigation)** — out of scope; soak-gated until ~2026-07-06,
  stays under #5689.
- Synthetic `workspace/reconcile-on-push` event emission (Approach B) — rejected.
- Any user-visible notification of the sync — silent self-heal only (CPO).
- Team-workspace handling — inherits arm-1's solo-only scope.
- A DB migration — `kb_sync_history.trigger` is free-form JSONB.

## Functional Requirements

- **FR1.** When arm-1's per-workspace step backfills `github_installation_id`
  (`decision.kind === "reconciled"`), it then attempts an immediate
  `syncWorkspace(resolvedInstallId, workspacePathForWorkspaceId(workspaceId), …)`
  in the same `step.run("reconcile-${workspaceId}")` boundary.
- **FR2.** The backfill column write commits **before** the sync attempt, so a sync
  failure leaves the row reachable (self-heals next fire) and never double-backfills.
- **FR3.** Before syncing, reuse the existing `workspaceDirExists` guard. On a missing
  dir (ready row, no dir), take the existing skip-and-audit branch
  (`ERROR_CLASS_WORKSPACE_NOT_READY`) — do not error the step.
- **FR4.** On sync (ok or not), append a `kb_sync_history` row via the service-role
  writer (`appendKbSyncRowForWorkspace` / `append_kb_sync_row_for_user`, mig 100)
  with `trigger` = a new distinct value (e.g. `reconcile_backfill`) and the real
  ok/error_class from `syncWorkspace`.
- **FR5.** A failed immediate sync mirrors to Sentry via the existing
  `reportSilentFallback` path (per `cq-silent-fallback-must-mirror-to-sentry`) and
  does not abort the cron — other findings still process.

## Technical Requirements

- **TR1.** Widen the audit `trigger` TS union `"webhook_push" | "manual" | "session"`
  (`session-sync.ts:639`) to include the new value. Per
  `hr-type-widening-cross-consumer-grep`, grep all consumers; the field is currently
  **write-only** (nothing switches on it), so risk is low — verify before/after.
- **TR2.** No SQL migration (mig 017 has no CHECK on `trigger`; RPCs 053/100 accept
  `jsonb`).
- **TR3.** Stay within ADR-033 I1/I6. No `step.sendEvent`.
- **TR4.** Keep heavy git IO inside the per-workspace step so one slow repo cannot
  blow the cron's wall clock. If soak metrics show arm-1 step times creeping, the
  documented fallback is **A′** (defer the sync to arm-3 via a `needs_initial_sync`
  marker) — a separate follow-up, not this spec.

## Observability

- Reuse `cron-workspace-sync-health` Sentry feature for backfill-sync failures
  (existing `reportSilentFallback` mirror).
- The new `reconcile_backfill` trigger value makes backfill-initiated syncs queryable
  in `kb_sync_history`, separable from `webhook_push` (operator can confirm the lag
  closed without SSH, per `hr-no-dashboard-eyeball-pull-data-yourself`).
- Extend the arm-1 completion log (`reconciled`/`skipped`/`transient`) with a synced
  count.

## Acceptance Criteria

1. A `ready` + NULL-install solo workspace, after one cron fire, has BOTH a
   backfilled `github_installation_id` AND a fresh `kb_sync_history` row with
   `trigger: reconcile_backfill, ok: true`.
2. With a missing workspace dir, the row records the skip
   (`ERROR_CLASS_WORKSPACE_NOT_READY`) and the step does not throw.
3. A re-fire after a successful backfill does not re-sync (row no longer matches the
   scan predicate).
4. No Inngest event is emitted by arm-1 (I6 preserved).
5. `typecheck` passes after the union widening; no consumer reads break.

## Open Questions (resolve at plan/implementation)

- Final `trigger` literal (`reconcile_backfill` vs `backfill_resync`).
- Whether to capture an ADR / ADR-044 amendment for per-arm sync ownership.
