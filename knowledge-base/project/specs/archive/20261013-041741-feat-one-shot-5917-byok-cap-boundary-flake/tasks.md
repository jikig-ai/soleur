---
plan: knowledge-base/project/plans/2026-07-02-fix-byok-cap-boundary-for-update-double-trip-plan.md
issue: 5917
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — fix byok cap-boundary FOR UPDATE double-trip (#5917)

## Phase 0 — Live evidence (read-only, decisive)

- [ ] 0.1 Supabase MCP `execute_sql` (dev): `SELECT pg_get_functiondef('public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)'::regprocedure);` — record `FOR UPDATE` + trip-derivation presence.
- [ ] 0.2 Supabase MCP `list_migrations` (dev): confirm 061/064/093 recorded; correlate any dev apply near 2026-07-02 20:00 UTC.
- [ ] 0.3 `gh workflow run tenant-integration.yml --ref main` in a quiet window; capture green (transient) vs red (persistent).
- [ ] 0.4 Record H1 (drift) vs H2 (genuine) verdict; proceed regardless.

## Phase 1 — Authoritative trip-signal migration (RED→GREEN)

- [ ] 1.1 Write RED structural test asserting `v_tripped := FOUND` after the guarded UPDATE + `FOR UPDATE` retained (extend `test/supabase-migrations/046-runtime-cost-state.test.ts` or new `121-*.test.ts`).
- [ ] 1.2 Create `supabase/migrations/121_byok_cap_trip_from_found.sql` (verify 121 free) — `CREATE OR REPLACE` mig-061 body with `IF v_total > v_cap THEN … v_tripped := FOUND;`; retain FOR UPDATE, audit-INSERT-first, strict `>`, SECURITY DEFINER, `search_path = public, pg_temp`, mig-061 REVOKE/GRANT. Read migs 118-120 for DDL convention.
- [ ] 1.3 Create `121_byok_cap_trip_from_found.down.sql` restoring mig-061 body verbatim.
- [ ] 1.4 GREEN the structural test.

## Phase 2 — Reconcile dev + confirm required check green

- [ ] 2.1 Supabase MCP `apply_migration` (dev) — reconciles drift + installs hardened body.
- [ ] 2.2 Re-run `tenant-integration` on PR branch; confirm byok atomicity test + `tenant-integration-required` green (link run).

## Phase 3 — Dev-RPC-body drift guard (observability)

- [ ] 3.1 Extend `dev-migration-drift-probe` (composite action / `scheduled-dev-migration-drift.yml`) to assert byok RPC-body markers (`FOR UPDATE`, `v_tripped := FOUND`) for `record_byok_use_and_check_cap` + `check_and_record_byok_delegation_use`; `::error::` + `reportSilentFallback` naming function + missing marker on drift. Credential stays in ephemeral runner.
- [ ] 3.2 Structural test for the probe assertion (present-marker pass, missing-marker fail).

## Phase 4 — Self-diagnosing test failure (no invariant weakening)

- [ ] 4.1 In `byok-kill-switch.atomicity.tenant-isolation.test.ts`, embed live `pg_get_functiondef` in the Invariant C failure message on double-trip. Invariant C stays strict.

## Verification / exit

- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] Migration structural tests green via package runner (check vitest include globs).
- [ ] AC1-AC11 satisfied (see plan `## Acceptance Criteria`).
- [ ] Record H1/H2 verdict in `knowledge-base/project/learnings/` (directory + topic; no hardcoded date filename).
