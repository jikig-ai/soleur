---
feature: feat-one-shot-durable-rls-inngest-prd
plan: knowledge-base/project/plans/2026-06-30-security-durable-rls-inngest-event-trigger-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — durable RLS self-heal on soleur-inngest-prd (ddl_command_end event trigger)

Spec lacks valid `lane:` (no spec.md) — set `cross-domain` explicitly from change shape (not a fail-closed default).

## Phase 0 — Pre-implementation re-confirmation (blocking, read-only)

- [ ] 0.1 Live-capture state: `get_advisors(security)` → 0 `rls_disabled_in_public`; `pg_class.relrowsecurity` → `tables_rls_off=0`; `pg_event_trigger` has no `inngest_rls_self_heal_trg`. Archive as PR "before" evidence.
- [ ] 0.2 Re-run the self-cleaning rolled-back `CREATE EVENT TRIGGER` feasibility probe as `postgres` via the Management API. Expect `CREATE_EVENT_TRIGGER_OK`. On FAIL → HALT, fall back to cron-cadence alternative.
- [ ] 0.3 Re-confirm consumer effective role = `postgres` (owner) via the parent evidence (`scheduled-inngest-health.yml:225`).

## Phase 1 — Author the idempotent event-trigger SQL

- [ ] 1.1 Create `apps/web-platform/infra/inngest-rls/0002_rls_self_heal_event_trigger.sql` (full text in plan §Setup SQL): fail-closed Inngest-sentinel preflight; `CREATE OR REPLACE FUNCTION public.inngest_rls_self_heal()` (`RETURNS event_trigger`, `SECURITY DEFINER`, `SET search_path = public, pg_temp`, exception-safe inner+outer, scoped `CREATE TABLE`+`object_type='table'`+`schema_name='public'`, `ENABLE RLS` + defensive `REVOKE`); `REVOKE ALL ON FUNCTION … FROM PUBLIC, anon, authenticated`; idempotent `DROP EVENT TRIGGER IF EXISTS` + `CREATE EVENT TRIGGER … WHEN TAG IN ('CREATE TABLE')`; break-glass comment.

## Phase 2 — Wire into the existing apply workflow

- [ ] 2.1 Edit `.github/workflows/apply-inngest-rls.yml`: apply `apps/web-platform/infra/inngest-rls/0*.sql` in sorted order (0001 then 0002), keeping `55P03` retry/backoff + all anti-exfil parity.
- [ ] 2.2 Extend the authoritative gate (every run incl. daily schedule) with `trg_present=1 AND fn_ok=1` (event trigger enabled + function `SECURITY DEFINER` + search_path pinned). Wire `selfheal_trigger_missing` / `selfheal_fn_misconfigured` failure modes.
- [ ] 2.3 Add the live trigger self-test (push + `workflow_dispatch` only, NOT daily): create `public._rls_selfheal_probe`, assert `relrowsecurity=true` + `anon SELECT=false`, drop it. Wire `selfheal_trigger_inert`.

## Phase 3 — Test harness

- [ ] 3.1 Extend `apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` with comment-stripped static guards for 0002: `SECURITY DEFINER`; `SET search_path = public, pg_temp`; `EXCEPTION WHEN OTHERS` + `RAISE WARNING`; `WHEN TAG IN ('CREATE TABLE')` + `schema_name = 'public'`; `ENABLE ROW LEVEL SECURITY`; `DROP EVENT TRIGGER IF EXISTS` + `CREATE EVENT TRIGGER`; no `FORCE`, no `CREATE POLICY`, no revoke of `postgres`/`service_role`.
- [ ] 3.2 `bash apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` exits 0; `actionlint .github/workflows/apply-inngest-rls.yml` passes.

## Phase 4 — ADR-030 amendment + C4

- [ ] 4.1 Extend invariant I8 / add I9 (RLS self-heal at DDL time) in `ADR-030-inngest-as-durable-trigger-layer.md` + dated `## Updates / amendment log` entry.
- [ ] 4.2 "No C4 structural change" — cite the external-actor/system/relationship enumeration. If the optional `inngestPostgres` description is touched, run `c4-code-syntax.test.ts` + `c4-render.test.ts` AND `bash scripts/regenerate-c4-model.sh` (commit `model.likec4.json` same commit).
- [ ] 4.3 Add a one-line `inngest.tf` comment cross-referencing `0002`.

## Phase 5 — Tracking issue + post-merge verification

- [ ] 5.1 Tracking issue open (labels `domain/engineering` + `priority/p2-medium`); PR body uses `Ref #<issue>` (not `Closes`).
- [ ] 5.2 Post-merge (automated): extended gate green (`violations=0 AND trg_present=1 AND fn_ok=1`); live self-test green; advisor still 0 `rls_disabled_in_public`; `scheduled-inngest-health.yml` green; first daily run a clean no-op.
- [ ] 5.3 `gh issue close <tracking-issue>` after gate + self-test green.

## Pre-merge AC gate (plan §Acceptance Criteria — Pre-merge)

- [ ] 0002 SQL shape complete (per AC1); workflow edits complete (per AC2); actionlint green; ADR-030 I8/I9 + amendment-log; PR body has live before-evidence + feasibility-probe result + `Ref #<issue>`.
