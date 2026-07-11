# Tasks — RLS tenant-boundary fixes (#6334, #6336)

Plan: `knowledge-base/project/plans/2026-07-11-fix-rls-tenant-boundary-with-check-and-authorize-template-plan.md`
Lane: cross-domain (spec.md absent — TR fail-closed default). Brand-survival threshold: single-user incident.

## Phase 0 — Reproduce + preconditions

- [ ] 0.1 Stand up the ADR-111 local disposable Supabase stack (`supabase start` + `[db.migrations] enabled = false`, apply via `run-migrations.sh` over `docker exec psql`) — or rely on the `rls-authz-fuzz` PR gate as authoritative verifier.
- [ ] 0.2 Run `cd apps/web-platform && bun run test:rls-fuzz` PRE-fix; confirm both `test.fails` contracts are green (exposures reproduce).
- [ ] 0.3 Record why `kb_files.workspace_id` UPDATE succeeds despite `077:76` REVOKE — `has_column_privilege('authenticated','public.kb_files','workspace_id','UPDATE')` + `information_schema.role_column_grants`. Note root cause for the downstream observation (candidate follow-up if systemic).
- [ ] 0.4 Re-verify `129`/`130` are next-free migration prefixes vs `origin/main`.

## Phase 1 — #6334 RLS write-side WITH CHECK (migration 129) — THREE policies

- [ ] 1.1 Create `129_*.sql`: DROP+CREATE with `WITH CHECK (user_id = auth.uid() AND public.is_workspace_member(workspace_id, auth.uid()))` for: `conversations_owner_update` (USING unchanged), **`conversations_owner_insert`** (deepen-added — INSERT-placement gap, `075:63-65`), and `kb_files_owner_update` (USING unchanged). `kb_files` INSERT already correct — untouched. No top-level BEGIN/COMMIT.
- [ ] 1.2 Create `129_…down.sql`: DROP+CREATE all THREE policies with WITH CHECK back to `user_id = auth.uid()` only.
- [ ] 1.3 Create `verify/129_*.sql` — FAIL-CLOSED (verify/116 `CASE WHEN count(*)=1` aggregate, one row per policy even when absent): for each of the three policies assert `with_check ILIKE '%is_workspace_member%'` AND `with_check ILIKE '%auth.uid()%'` (retain user_id clause per AC).

## Phase 2 — #6336 authorize_template ownership guard (migration 130)

- [ ] 2.1 Create `130_authorize_template_grant_ownership_guard.sql`: `CREATE OR REPLACE FUNCTION public.authorize_template(text,text,uuid)` restoring the mig-053 body verbatim + insert the guard after input validation / before the INSERT: `IF p_grant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.scope_grants WHERE id = p_grant_id AND founder_id = v_founder_id) THEN RAISE EXCEPTION 'authorize_template: grant not owned by caller' USING ERRCODE='42501'; END IF;`. KEEP `SET search_path = public, pg_temp`. Re-state REVOKE/GRANT/COMMENT.
- [ ] 2.2 Create `130_…down.sql`: `CREATE OR REPLACE` restoring the exact mig-053 `authorize_template` body (no guard), re-stating REVOKE/GRANT/COMMENT (089.down idiom — NOT a DROP).
- [ ] 2.3 Create `verify/130_*.sql` — FAIL-CLOSED, scoped to `proname='authorize_template'` + `(text,text,uuid)` signature (do NOT match sibling bodies `revoke_template_authorization`/`grant_action_class`/`revoke_action_class` which also contain `founder_id = v_founder_id`): `CASE WHEN count(*)=1` over `prosrc ILIKE '%scope_grants%founder_id = v_founder_id%'`.

## Phase 3 — Un-baseline + verify green

- [ ] 3.1 Edit `apps/web-platform/test/rls-fuzz/rls-row-hijack.integration.test.ts:80` — remove `"conversations"` and `"kb_files"` from `HIJACK_EXPOSURES`.
- [ ] 3.2 Edit `apps/web-platform/test/rls-fuzz/rls-rpc.integration.test.ts:161` — `test.fails(...)` → `test(...)`, retitle. Body assertion + positive control unchanged.
- [ ] 3.3 Do NOT edit `rpc-cases.ts` or `catalog.ts` (documented no-edit; AC6/AC8 stay satisfied).
- [ ] 3.4 Re-run `bun run test:rls-fuzz` — both contracts pass as plain assertions, all positive controls green.
- [ ] 3.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Acceptance verification (pre-merge)

- [ ] A1 verify/129 bad=0 (all THREE policies carry `is_workspace_member` + `user_id = auth.uid()`; sentinel is count-aggregate fail-closed).
- [ ] A1b conversations INSERT with a non-member `workspace_id` denies (42501); legit INSERT into own workspace succeeds.
- [ ] A2 authorize_template raises 42501 for non-owner grant; owner succeeds; search_path pin intact; verify/130 bad=0.
- [ ] A3 Both un-baseline tests pass; AC6/AC8 harness gates green.
- [ ] A4 `rls-authz-fuzz` PR gate GREEN (blocking check before ready).
- [ ] A5 Both `.down.sql` restore prior definitions.
- [ ] A6 `tsc --noEmit` clean.

## Post-merge (automated — no operator step)

- [ ] P1 `web-platform-release` migrate applies 129/130; `run-verify.sh` runs verify/129+130 (bad=0) against prod; failure halts the pipeline.
