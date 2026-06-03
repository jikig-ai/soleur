---
title: "Tasks — cron-workspace-gc + KB reconcile isolation"
plan: knowledge-base/project/plans/2026-06-03-fix-cron-workspace-gc-and-kb-reconcile-isolation-plan.md
branch: feat-one-shot-cron-workspace-gc-kb-reconcile
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

## Phase 0 — Preconditions
- [ ] 0.1 Re-derive `grep -cE '^\s+\w+,$' app/api/inngest/route.ts` count (was 48; may have drifted)
- [ ] 0.2 Re-derive alpha placement: `cron-workspace-gc` sorts BEFORE `cron-workspace-sync-health` (g<s)
- [ ] 0.3 Confirm relative `./_cron-shared` import convention (substrate guard regex)
- [ ] 0.4 Read `cron-supabase-disk-io.test.ts` + `function-registry-count.test.ts` as templates

## Phase 1 — Isolate cron clones (infra, no SSH)
- [ ] 1.1 `ci-deploy.sh` site 1 (~L458): `CRON_WORKSPACE_ROOT=/workspaces` → `/workspaces/.cron`
- [ ] 1.2 `ci-deploy.sh` site 2 (~L624, rollback path): same change
- [ ] 1.3 `ci-deploy.sh`: add `mkdir -p /mnt/data/workspaces/.cron && chown 1001:1001 /mnt/data/workspaces/.cron` near the existing chown (~L434)
- [ ] 1.4 **MANDATORY**: update `ci-deploy.test.sh:1186-1235` `assert_cron_workspace_root` literal to `-e CRON_WORKSPACE_ROOT=/workspaces/.cron` (grep -qF is substring → false-passes otherwise; verified at deepen). Update FAIL strings + function comment too.

## Phase 2 — cron-workspace-gc.ts
- [ ] 2.1 Create `server/inngest/functions/cron-workspace-gc.ts` (model: cron-supabase-disk-io.ts)
- [ ] 2.2 Pure helpers: `freeMb` (bavail*bsize, floor), `isSweepable` (soleur- prefix + age>maxAge)
- [ ] 2.3 Handler: statfs before → sweep `soleur-*` mtime>1h (per-dir fail-soft rm) → statfs after → Sentry {freeMbBefore,freeMbAfter,freedMb,sweptCount,root} → heartbeat ok=sweep-ran
- [ ] 2.4 ENOENT root → no throw, heartbeat ok, no page (mirror session-metrics)
- [ ] 2.5 All IO inside step.run; no claude/BYOK/subprocess; cron literal OUT of JSDoc header
- [ ] 2.6 `createFunction` triggers: `{cron:"0 */6 * * *"}` + `{event:"cron/workspace-gc.manual-trigger"}`; concurrency caps + retries:1

## Phase 3 — Register (enables allowlist + scheduler)
- [ ] 3.1 `cron-manifest.ts`: add `"cron-workspace-gc"` to `EXPECTED_CRON_FUNCTIONS` (before workspace-sync-health) — auto-derives the allowlist event
- [ ] 3.2 `app/api/inngest/route.ts`: import + array entry; re-derive registry count
- [ ] 3.3 DO NOT edit `manual-trigger-allowlist.ts` (derived, not hardcoded)

## Phase 4 — Tests (RED first)
- [ ] 4.1 `test/server/inngest/cron-workspace-gc.test.ts`: isSweepable (aged soleur- true / fresh false / UUID-dir false), freeMb arithmetic
- [ ] 4.2 handler removes only aged soleur-*, leaves UUID + fresh dirs; emits before/after Sentry; heartbeat ok
- [ ] 4.3 ENOENT root tolerated; single rm EACCES does not abort loop
- [ ] 4.4 allowlist test: `isAllowlistedManualTrigger("cron/workspace-gc.manual-trigger")` true
- [ ] 4.5 full test-all.sh EXIT=0 (read EXIT= marker); tsc --noEmit clean

## Phase 5 — Side-effect sweep
- [ ] 5.1 `session-metrics.ts`: extend `readdirSync` filter to also drop `.cron` (keep active-workspace count honest)

## Post-merge (operator/automated, no SSH)
- [ ] P.1 Merge → web-platform-release.yml restarts container with new root + fn (merge IS apply)
- [ ] P.2 Fire GC via /soleur:trigger-cron; verify Sentry scheduled-workspace-gc heartbeat ok + freedMb>0
- [ ] P.3 Verify reconcile resumes: fresh kb_sync_history webhook_push ok:true row post-GC (NOT "#4846 appears")
- [ ] P.4 File deferred-volume tracking issue; PR body uses `Ref #4882` not Closes
