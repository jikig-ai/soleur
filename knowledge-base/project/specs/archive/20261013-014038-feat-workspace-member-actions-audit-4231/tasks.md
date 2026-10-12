---
feature: feat-workspace-member-actions-audit-4231
date: 2026-05-22
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-05-22-feat-workspace-member-actions-audit-plan.md
spec: knowledge-base/project/specs/feat-workspace-member-actions-audit-4231/spec.md
issue: 4231
branch: feat-workspace-member-actions-audit-4231
pr: 4287
---

# Tasks: `workspace_member_actions` Audit Log (#4231)

Derived from `knowledge-base/project/plans/2026-05-22-feat-workspace-member-actions-audit-plan.md` (post-plan-review 2026-05-22). Phases are sequential; sub-tasks within a phase may parallelize except where noted (load-bearing ordering on triggers + backfill).

## Phase 0 — Preconditions (must complete before any code edit)

- 0.1 Verify branch + worktree: `git branch --show-current` returns `feat-workspace-member-actions-audit-4231`; `pwd` ends in `.worktrees/feat-workspace-member-actions-audit-4231`.
- 0.2 Re-verify migration number 062 is still free across all sibling worktrees: `for wt in /home/jean/git-repositories/jikig-ai/soleur/.worktrees/*/; do ls "$wt/apps/web-platform/supabase/migrations/" 2>/dev/null | grep '^062_'; done` — expect empty.
- 0.3 CPO sign-off attestation noted in plan body (carry-forward from #4229 Decision 10). No fresh CPO spawn.
- 0.4 Read mig 037 (`audit_byok_use_no_mutate` + matching anonymise RPC) as canonical pure-reject + replica-bypass template. Read mig 051 §(c)+(h) for `RESET session_replication_role` convention. Read mig 053:51,83 + mig 058:45-46 for `public.users(id)` FK convention. Read mig 058:167-247 + 267-330 for `invite_workspace_member` + `remove_workspace_member` bodies. Read mig 058:383-401 for `anonymise_workspace_members` body.
- 0.5 Verify file paths to be edited exist: `ls apps/web-platform/server/{dsar-export-allowlist,dsar-export,account-delete,workspace-membership}.ts`; `ls apps/web-platform/test/dsar-cascade.test.ts || find apps/web-platform/test -name "*dsar*"` (locate the closest sibling for Phase 5.5 extension); `find apps/web-platform/scripts -type d` (decide canonical scripts dir for Phase 7.4 sentinel).

## Phase 1 — Migration File Skeleton

- 1.1 Create `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql` with header block (LAWFUL_BASIS, RETENTION 7y, WORM contract → mig 037 + 051, RoPA PA-20 cite, learning cites for `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`, `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`, `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`).
- 1.2 Create `063_workspace_member_actions.down.sql` with DROP order: cron job → wrapper RPCs → AFTER trigger on workspace_members → WORM trigger → indexes → table. Do NOT revert mig 058 RPC prepends — the `set_config` calls become harmless no-ops once the trigger is gone.
- 1.3 Section 1 of migration: `CREATE TABLE public.workspace_member_actions` per spec FR1 (FKs target `public.users`, NOT `auth.users`; `created_at timestamptz NOT NULL DEFAULT now()` explicit).
- 1.4 Indexes (no `CONCURRENTLY`): `(workspace_id, created_at DESC)`, `(target_user_id) WHERE target_user_id IS NOT NULL`, `(actor_user_id) WHERE actor_user_id IS NOT NULL`.
- 1.5 RLS posture: `ENABLE ROW LEVEL SECURITY`; zero policies; `REVOKE INSERT, UPDATE, DELETE, SELECT FROM PUBLIC, anon, authenticated, service_role`.

## Phase 2 — Triggers (WORM + AFTER on workspace_members)

- 2.1 `workspace_member_actions_no_mutate()` BEFORE UPDATE/DELETE trigger function, lifted from mig 037's `audit_byok_use_no_mutate`. Pure-reject with `session_replication_role='replica'` bypass.
- 2.2 `workspace_members_audit()` AFTER INSERT/UPDATE/DELETE trigger function on `public.workspace_members`. SECURITY DEFINER, `SET search_path = public, pg_temp`. Body per plan §2.2 (NULLIF + EXCEPTION block for GUC parse; uses `NEW.attestation_id` directly; `session_user='authenticated'` check for TR13 orphan-actor log; PII-scrubbed `RAISE LOG`).
- 2.3 Attach both triggers; REVOKE both trigger functions from PUBLIC/anon/authenticated.

## Phase 3 — RPC Bodies (reader, anonymise, purge, +058 patches)

- 3.1 `list_workspace_member_actions(p_workspace_id, p_limit DEFAULT 50, p_cursor DEFAULT NULL) RETURNS SETOF public.workspace_member_actions` SECURITY DEFINER. Owner-check via `organizations.owner_user_id JOIN workspaces.organization_id`. Empty return on non-owner / nonexistent workspace.
- 3.2 `anonymise_workspace_member_actions(p_user_id) RETURNS int` SECURITY DEFINER. `SET LOCAL session_replication_role='replica'` → UPDATE NULL PII → `RESET session_replication_role` → RETURN row count.
- 3.3 `purge_workspace_member_actions() RETURNS int` SECURITY DEFINER. `SET LOCAL session_replication_role='replica'` → DELETE-by-7y → `RESET session_replication_role` → `RAISE LOG 'audit_retention_purge ...'` → RETURN count.
- 3.4 `CREATE OR REPLACE invite_workspace_member(...)` mig 058's body verbatim + `PERFORM set_config('workspace_audit.actor_user_id', COALESCE(auth.uid()::text, ''), true);` as first statement.
- 3.5 `CREATE OR REPLACE remove_workspace_member(...)` same prepend pattern.
- 3.6 `CREATE OR REPLACE anonymise_workspace_members(p_user_id)` mig 058's body verbatim + `SET LOCAL session_replication_role='replica'` before DELETE + `RESET session_replication_role` after. Prevents new AFTER trigger from firing during account-delete cascade.
- 3.7 Grant matrices per TR3 (REVOKE all from PUBLIC/anon/authenticated; explicit GRANT EXECUTE TO service_role for anonymise; TO authenticated for list; TO postgres for purge).

## Phase 4 — Backfill + cron schedule (after triggers exist)

- 4.1 Backfill block: `LOCK TABLE public.workspace_members IN SHARE MODE; SET LOCAL session_replication_role='replica'; INSERT INTO workspace_member_actions SELECT ... FROM workspace_members WHERE NOT EXISTS (...); RESET session_replication_role;`
- 4.2 `pg_cron` schedule: `SELECT cron.schedule('workspace-member-actions-retention', '0 4 * * *', $$SELECT public.purge_workspace_member_actions()$$);`
- 4.3 `RAISE NOTICE 'backfill row count = %', (SELECT count(*) FROM workspace_member_actions);` as sanity assertion against the source membership count.

## Phase 5 — TypeScript server edits (DSAR cascade)

- 5.1 `dsar-export-allowlist.ts`: append `workspace_member_actions` to the export-table list.
- 5.2 `dsar-export.ts`: add per-table read block. Predicate via `.or('actor_user_id.eq.{userId},target_user_id.eq.{userId}')`. Verify supabase-js syntax against installed `@supabase/postgrest-js` types BEFORE committing.
- 5.3 `account-delete.ts`: add inline step `3.93` calling `anonymise_workspace_member_actions(p_user_id)` AFTER step `3.92` and BEFORE step `4`. Match the fail-loud pattern from siblings `3.91`/`3.92`.
- 5.4 `account-delete.ts`: update JSDoc header at lines 57-75 to add `5.9 anonymise-workspace-member-actions ...` entry.
- 5.5 Extend `apps/web-platform/test/dsar-cascade.test.ts` (or closest sibling — see 0.5): assert `anonymise_workspace_member_actions` is invoked between `3.92` and `4`. Also assert the cascade re-CREATE of `anonymise_workspace_members` was applied (mock the trigger or use service-role to verify no audit row is written during cascade DELETE).

## Phase 6 — Article 30 register + observability

- 6.1 Append `## Processing Activity 20 — Workspace membership audit log` to `knowledge-base/legal/article-30-register.md` per plan §6.1 (all GDPR-gate fold-in keys: Controller, Categories of data subjects, Categories of personal data, Recipients, Retention with 7y rationale, Security measures, Lawful basis with LIA balancing test, International transfers, Anonymise cascade, Erasure mechanism, Purpose limitation clause).
- 6.2 Create `knowledge-base/engineering/runbooks/cron-retention-monitor.md` per plan §6.2 (4 sections: `cron.job_run_details` table contract, Better Stack monitor post-merge spec, MCP-accessible verification query, parallel `RAISE LOG` stream description).
- 6.3 Document the `audit_orphan_actor` Better Stack alert query in the runbook (filter Supabase logs, page on >5/24h).

## Phase 7 — Tests

- 7.1 `apps/web-platform/supabase/tests/workspace_member_actions.sql` — pgTAP file covering AC1–AC15 (pre-merge subset). Use `BEGIN; SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claim.sub = ...; ROLLBACK;` for RLS probes. Use schema-valid UUIDs everywhere. Assert dual deny shape (`42501` OR empty-set) on cross-tenant probes. Re-read via service_role for poison-check.
- 7.2 `apps/web-platform/e2e/team-membership.e2e.ts` — extend with 4 scenarios: (a) Jean invites Harry → 1 audit row with correct actor/target; (b) Jean lists his workspace audit → ≥1 row; (c) Harry lists Jean's workspace audit → 0 rows; (d) Jean removes Harry → 2nd audit row. Use vitest path: `./node_modules/.bin/vitest run e2e/team-membership.e2e.ts` (NOT `bun test`).
- 7.3 Cascade test extension (in 5.5) verified.
- 7.4 Sentinel sweep script at the path resolved in 0.5 (`apps/web-platform/scripts/check-workspace-members-write-sites.sh` or sibling). Enumerates INSERT/UPDATE/DELETE on `workspace_members` and asserts each routes through a GUC-setting RPC or is a documented admin-tool/fixture path.
- 7.5 Cascade-completeness sweep (Phase 7.5 retained per conservative scope): pgTAP file or shell script enumerating `auth.users(id)` / `public.users(id)` references in mig 053/058 tables and asserting each appears in `account-delete.ts` cascade.

## Phase 8 — Pre-merge validation

- 8.1 Local pgTAP: `cd apps/web-platform && bunx supabase db reset && bunx supabase test db` (verify runner per `package.json scripts.test`).
- 8.2 Vitest extension: `./node_modules/.bin/vitest run e2e/team-membership.e2e.ts`.
- 8.3 `tsc --noEmit` for TS exhaustiveness.
- 8.4 Sentinel sweep script exits 0 locally.
- 8.5 Run `/soleur:preflight` (Phase 5.5 ship-time gate) before marking PR ready.

## Phase 9 — Post-merge (CI / MCP automation; no operator action required)

- 9.1 Migration applies via `web-platform-release.yml#migrate` (automated on merge).
- 9.2 Post-merge verification via Supabase MCP: `mcp__plugin_supabase_supabase__execute_sql` with the AC14 verification query against prd. Backfill row count == workspace_members count; `cron.job` has 1 row for `workspace-member-actions-retention`.
- 9.3 PostgREST schema cache reload probe: service_role call to `list_workspace_member_actions` with retry/backoff (AC15).
- 9.4 File follow-up GitHub issues per plan §GDPR Gate Outcome (privacy policy update T-01 + invite-time notice T-02; both gated on `TEAM_WORKSPACE_INVITE_ENABLED` flag-flip prep).
- 9.5 Update existing code-review issues #3220 and #3221 with a comment referencing #4231 as a load-bearing post-merge verification test case.

## Dependencies / Ordering Notes

- Phases 1 → 2 → 3 → 4 are STRICTLY ordered (trigger before backfill is load-bearing).
- Phases 5 and 6 can interleave with Phase 7 (TS edits + Article 30 + runbook are independent of pgTAP authoring).
- Phase 8 gates Phase 9 — never push to `gh pr ready` without 8.1-8.5 green.
- Phase 9.4 follow-up issues should be filed at the same time as `gh pr ready` so the operator obligation is visible in the GitHub UI.
