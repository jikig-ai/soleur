---
feature: sync-health-immediate-resync
issue: 5689
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-29-feat-sync-health-immediate-resync-plan.md
---

# Tasks: Immediate re-sync after arm-1 backfill (#5689 item 2)

## Phase 1 — Type widening (contract first)
- [x] 1.1 Widen `kb_sync_history` `trigger` union at `session-sync.ts:639` → add `"reconcile_backfill"`. Re-confirm write-only via `git grep -n '"webhook_push"'` (apps + test).

## Phase 2 — Arm-1 in-arm re-sync (`cron-workspace-sync-health.ts`)
- [x] 2.1 Import the pino module logger (`import logger from "@/server/logger"`); add an inline `workspaceDirExists` (fs.stat().isDirectory()) helper.
- [x] 2.2 In the `decision.kind === "reconciled"` branch (`:289-295`), after the backfill commit, compute `workspacePathForWorkspaceId(f.workspaceId)`.
- [x] 2.3 Guard with `workspaceDirExists`; on missing dir write `{trigger:"reconcile_backfill", ok:false, error_class: ERROR_CLASS_WORKSPACE_NOT_READY}` via `appendKbSyncRowForWorkspace(service, f.workspaceId, …)`, do not throw.
- [x] 2.4 On dir present, `syncWorkspace(decision.installId, path, logger, {userId: f.workspaceId, op:"manual"})`.
- [x] 2.5 Append `kb_sync_history` row `{trigger:"reconcile_backfill", ok, error_class: result.errorClass?}` via `appendKbSyncRowForWorkspace`.
- [x] 2.6 On `ok:false`, `reportSilentFallback(feature: SENTRY_FEATURE, op:"reconcile-backfill-sync")`; continue the loop (do not abort cron).
- [x] 2.7 Extend the completion log (`:325-327`) with a `synced` count.

## Phase 3 — Tests (`test/server/inngest/cron-workspace-sync-health.test.ts`)
- [x] 3.1 Reconciled solo (dir present) → backfill + `{trigger:"reconcile_backfill", ok:true}`; assert no Inngest event (I6).
- [x] 3.2 Reconciled, missing dir → `ERROR_CLASS_WORKSPACE_NOT_READY`, no throw.
- [x] 3.3 Re-fire after backfill → no second sync.
- [x] 3.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green.

## Phase 4 — Docs
- [x] 4.1 Append one sentence to ADR-044's existing 2026-06-29 reconcile amendment (arm-1 in-arm sync, `reconcile_backfill` trigger, I6 preserved).

## Acceptance (Pre-merge)
- [x] AC1 backfill + ok:true audit row + no event (3.1)
- [x] AC2 missing-dir skip-without-throw (3.2)
- [x] AC3 no double-sync on re-fire (3.3)
- [x] AC4 failed sync mirrors to Sentry, cron continues
- [x] AC5 tsc green
