---
feature: auth-flow-state-retention-prune
issue: 5739
branch: feat-one-shot-5739-auth-wal-reduction-v2
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-07-perf-prune-auth-flow-state-bloat-plan.md
date: 2026-07-07
---

# Tasks — prune `auth.flow_state` GoTrue bloat (#5739)

## Phase 0 — Read-only prod re-verify (no writes)
- [ ] 0.1 Supabase MCP (read-only, `ifsccnjhymdmidffkzhl`): re-confirm `postgres` holds DELETE
      on `auth.flow_state` (`information_schema.role_table_grants`).
- [ ] 0.2 Read-only: row-count-by-age (total / older-than-3-days / oldest `created_at`) + pgss
      window age; confirm `flow_state` INSERT WAL ≪ `refresh_tokens` INSERT WAL. Record for PR evidence.
- [ ] 0.3 `git ls-tree origin/main apps/web-platform/supabase/migrations/` — confirm `124_*` free;
      renumber if taken.

## Phase 1 — Migration
- [ ] 1.1 Write `apps/web-platform/supabase/migrations/124_prune_auth_flow_state.sql`:
      header comment (mirror 115/103 density: bloat-not-WAL framing + cite cadence-vs-prune learning,
      3-day-floor derivation, runs-as-postgres/no-SECURITY-DEFINER, atomicity/idempotency + NO top-level BEGIN/COMMIT).
- [ ] 1.2 Statement 1 — idempotent `cron.schedule('auth_flow_state_retention', '0 4 * * *', <DELETE created_at < now()-'3 days'>)`
      with `cron.unschedule` guard + `EXCEPTION WHEN duplicate_object`.
- [ ] 1.3 Statement 2 — one-time backlog purge `DELETE FROM auth.flow_state WHERE created_at < now() - interval '3 days'`.
- [ ] 1.4 Write `124_prune_auth_flow_state.down.sql`: `IF EXISTS`-guarded `cron.unschedule`; comment that one-time deletion is irreversible by design.

## Phase 2 — Verify
- [ ] 2.1 Apply migration on dev via CI (`web-platform-release.yml#migrate`); confirm green + idempotent re-apply (no-op).
- [ ] 2.2 (RED→GREEN, DEV only) predicate-safety test: synthetic in-window row survives, out-of-window (4d) row deleted.
- [ ] 2.3 Post-deploy prod (read-only MCP): discoverability query → `rows < 600`, `prunable = 0`, `sched = '0 4 * * *'`.

## Phase 3 — Record decision
- [ ] 3.1 PR body evidence block: post-soak finding (legitimate volume, no loop, no short-TTL churn) +
      before/after flow_state counts + JWT-TTL deferral rationale (NG1). `Closes #5739`.
- [ ] 3.2 (ship/operator) Recommend closing superseded WIP draft #5762 (do NOT delete its branch/worktree).

## Verification gates (from plan ACs)
- Predicate literal is `'3 days'` (≥ 24h floor); no SECURITY DEFINER; no top-level BEGIN/COMMIT.
- `.down.sql` unschedules guarded by `IF EXISTS`.
- Auth-schema WAL share documented as **unchanged by design** (bloat/disk play, not WAL lever).
- Migration number re-checked at ship (collision guard).
