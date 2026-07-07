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
- [ ] 0.2 Read-only: row-count-by-age (total / older-than-7-days / oldest `created_at`) + pgss
      window age; confirm `flow_state` INSERT WAL ≪ `refresh_tokens` INSERT WAL. Record for PR evidence.
- [ ] 0.3 FK-child check: `SELECT count(*) FROM auth.saml_relay_states WHERE flow_state_id IS NOT NULL;`
      → confirm 0 (no SAML wiring). Also confirm live `mailer_otp_exp` (600s per configure-auth.sh:52).
- [ ] 0.4 `git ls-tree origin/main apps/web-platform/supabase/migrations/` — confirm `124_*` free;
      renumber if taken.

## Phase 1 — Migration
- [ ] 1.1 Write `apps/web-platform/supabase/migrations/124_prune_auth_flow_state.sql`:
      header comment (mirror 115/103 density: bloat-not-WAL framing + cite cadence-vs-prune learning,
      7-day window rationale + floor-invariant [window must exceed highest OTP/link expiry; live 600s],
      runs-as-postgres/no-SECURITY-DEFINER, atomicity/idempotency + NO top-level BEGIN/COMMIT).
- [ ] 1.2 Statement 1 — idempotent `cron.schedule('auth_flow_state_retention', '0 4 * * *', <DELETE created_at < now()-'7 days'>)`
      with `cron.unschedule` guard + `EXCEPTION WHEN duplicate_object`.
- [ ] 1.3 Statement 2 — one-time backlog purge `DELETE FROM auth.flow_state WHERE created_at < now() - interval '7 days'`.
- [ ] 1.4 Write `124_prune_auth_flow_state.down.sql`: `IF EXISTS`-guarded `cron.unschedule`; comment that one-time deletion is irreversible by design.

## Phase 1b — ADR (in-scope deliverable)
- [ ] 1b.1 Via `/soleur:architecture`, create the lightweight ADR (provisional **ADR-098**):
      "Soleur owns `auth.flow_state` retention via daily pg_cron DELETE as `postgres`"; context =
      GoTrue never prunes flow_state, revocable grant, 7-day floor-invariant; alternatives =
      SECURITY DEFINER (rejected), JWT-TTL (deferred NG1), do-nothing (rejected). Re-verify ordinal
      at ship (collision gate); sweep plan+tasks+ADR body together on renumber.

## Phase 2 — Verify
- [ ] 2.1 Apply migration on dev via CI (`web-platform-release.yml#migrate`); confirm green + idempotent re-apply (no-op).
- [ ] 2.2 (RED→GREEN, DEV only) predicate-safety test: synthetic in-window (now()) row survives, out-of-window (8d) row deleted.
- [ ] 2.3 Post-deploy prod (read-only MCP): discoverability query → `prunable (older than 7 days) = 0`, `rows <= 1600`, `sched = '0 4 * * *'`.

## Phase 3 — Record decision
- [ ] 3.1 PR body evidence block: post-soak finding (legitimate volume, no loop, no short-TTL churn) +
      before/after flow_state counts + JWT-TTL deferral rationale (NG1) + auth-schema WAL share
      unchanged-by-design statement. `Closes #5739`.
- [ ] 3.2 (ship) Render `decision-challenges.md` DC1 into PR body + file as `action-required` issue —
      do NOT auto-close/delete #5762 (operator fenced it off).

## Verification gates (from plan ACs)
- Predicate literal is `'7 days'` (matches siblings 103/115; ≥ 1-day unexchangeable floor); no SECURITY DEFINER; no top-level BEGIN/COMMIT.
- `.down.sql` unschedules guarded by `IF EXISTS`.
- Auth-schema WAL share documented as **unchanged by design** (bloat/disk play, not WAL lever) in PR body.
- Migration number + ADR-098 ordinal re-checked at ship (collision guards).
