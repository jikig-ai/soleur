---
feature: feat-workspace-member-actions-audit-4231
status: draft
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 4231
parent_issue: 4229
branch: feat-workspace-member-actions-audit-4231
pr: 4287
brainstorm: knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md
---

# Spec: `workspace_member_actions` Audit Log

## Problem Statement

Shared workspaces (organizations introduced in #4229) have no audit trail for membership mutations. When a workspace owner adds, removes, or changes the role of a member, no row records who-did-what-to-whom-when. Under GDPR Art. 5(2) accountability, a regulator inquiry into "did the controller (workspace owner) manage member access lawfully?" cannot be answered. Under SOC2 / member-dispute scenarios ("Harry says he was never removed"), the same gap exists.

Parent brainstorm `#4229` explicitly deferred this audit log (Decision 10) for internal dogfood (Jean + Harry trust each other; `tenant_deploy_audit` (043) covers the deploy boundary). The deferral's re-evaluation criterion fires at the first external workspace — that workspace owner cannot operate without this evidence trail.

**Blocks:** `TEAM_WORKSPACE_INVITE_ENABLED` flag-flip in prd for any org outside `@jikigai.com`.

## Goals

- G1 — Capture every membership mutation (add, remove, role-change) on `public.workspace_members` as an append-only audit row with sufficient identity columns to answer "who acted, against whom, when, what changed."
- G2 — Make the audit surface impossible to forget: any future RPC or admin tool that mutates `workspace_members` automatically writes an audit row without call-site discipline.
- G3 — Restrict read access to the workspace owner only (closes parent's Vector 1 — cross-workspace audit-row read).
- G4 — Preserve audit lineage for 7 years while honouring GDPR Art. 17 erasure requests via a non-destructive anonymise cascade.
- G5 — Inherit the WORM + SECURITY DEFINER + named-role REVOKE patterns from `tenant_deploy_audit` (043) and `workspace_member_attestations` (058) — no novel substrate.

## Non-Goals

- NG1 — Log KB writes, agent runs, BYOK lifecycle, or `canUseTool` permission decisions (parent #4229 Decision 10; revisit if v2 evidence demands).
- NG2 — Member-facing audit view ("see who added/removed me"). Owner-only this round.
- NG3 — Cross-workspace activity aggregation for a single user (covered by Art. 15 DSAR path via anonymise RPC mirror).
- NG4 — Real-time notifications on membership changes (owner settings-page poll is enough for v1).
- NG5 — Tamper-evident hash chaining or Merkle roots (defer until Trust Center / external regulator asks).
- NG6 — Member-departure DSAR routing (parent Capability Gap #1 — separate follow-up).

## Functional Requirements

- **FR1 — Audit table.** A new `public.workspace_member_actions` table with columns: `id`, `workspace_id` FK→`public.workspaces(id)` ON DELETE RESTRICT, `actor_user_id` FK→`public.users(id)` ON DELETE RESTRICT NULLable (PII), `target_user_id` FK→`public.users(id)` ON DELETE RESTRICT NULLable (PII), `action_type text NOT NULL CHECK (action_type IN ('added','removed','role_changed'))`, `old_role`, `new_role`, `attestation_id` FK→`public.workspace_member_attestations(id)` ON DELETE RESTRICT NULLable, `created_at timestamptz NOT NULL DEFAULT now()`. [Updated 2026-05-22 — all user-ref FKs target `public.users(id)`, matching sibling 053/058 convention; plan-review P0-3 fix.]
- **FR2 — Trigger-driven writer.** An `AFTER INSERT/UPDATE/DELETE` trigger on `public.workspace_members` writes one `workspace_member_actions` row per mutation. UPDATE fires a `role_changed` row only when `OLD.role IS DISTINCT FROM NEW.role` (no rows on noop UPDATEs).
- **FR3 — Actor capture via session GUC.** v1 GUC-setting writers are `invite_workspace_member` and `remove_workspace_member` (both defined in mig 058). Migration 063 re-`CREATE OR REPLACE`s each to add `PERFORM set_config('workspace_audit.actor_user_id', COALESCE(auth.uid()::text, ''), true);` (NOT `SET LOCAL`, which requires a literal — plan-review P0-5) before the mutation. Trigger reads `NULLIF(current_setting('workspace_audit.actor_user_id', true), '')::uuid` wrapped in an EXCEPTION block (`WHEN invalid_text_representation THEN v_actor := NULL`). NULL when the mutation is admin-tool / migration-time backfill (intentional). [Updated 2026-05-22 — `accept_workspace_invite` and `change_member_role` do not exist; invite is one-shot via `invite_workspace_member`. The `role_changed` enum value remains in the CHECK constraint for forward-compat but no v1 caller produces those events.]
- **FR4 — Owner-only read RPC.** SECURITY DEFINER `list_workspace_member_actions(p_workspace_id uuid, p_limit int DEFAULT 50, p_cursor timestamptz DEFAULT NULL)` returns rows for `p_workspace_id` only when `auth.uid() = (SELECT owner_user_id FROM organizations o JOIN workspaces w ON w.organization_id = o.id WHERE w.id = p_workspace_id)`. Returns empty (not error) for non-owners — never reveal table existence.
- **FR4a — Cursor semantics.** `p_cursor` is exclusive: returns rows `WHERE created_at < p_cursor`. Tie-break on identical `created_at` is `ORDER BY created_at DESC, id DESC`. NULL `p_cursor` returns the most recent page. Caller paginates by passing the oldest returned `created_at` of the previous page.
- **FR4b — Return shape.** `RETURNS SETOF public.workspace_member_actions` (all columns; attestation join deferred to caller).
- **FR5 — Anonymise RPC.** SECURITY DEFINER `anonymise_workspace_member_actions(p_user_id uuid) RETURNS int` sets `actor_user_id = NULL` and `target_user_id = NULL` for every row referencing `p_user_id` (idempotent: re-run's WHERE clause does not match already-NULLed rows). Audit lineage columns (`id`, `workspace_id`, `action_type`, `old_role`, `new_role`, `created_at`, `attestation_id`) preserved. RPC body uses `SET LOCAL session_replication_role = 'replica'` to bypass the pure-reject WORM trigger, followed by `RESET session_replication_role` after the UPDATE (mig 051/053b convention; plan-review P2-1). Returns updated row count via `GET DIAGNOSTICS`.
- **FR6 — WORM enforcement trigger.** BEFORE UPDATE/DELETE trigger PURE-REJECTs all mutations with `P0001`. Bypass is `current_setting('session_replication_role') = 'replica'` → `RETURN NULL` (the canonical post-2026-05-18 pattern per migration **037** `audit_byok_use_no_mutate` + migration **051** `action_sends_no_mutate` + migration **053b** `template_authorizations_no_mutate`, and learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`). No structural-diff branch; no GUC+role check. [Updated 2026-05-22 — plan-review P0-1 corrected the precedent citation: original "mig 048" reference was wrong (048 ships `precheck_jwt_mint_sqlstate` + `scope_grants` which uses structural-diff). The real pure-reject precedents are 037/051/053b.]
- **FR7 — Retention job (via wrapper RPC).** SECURITY DEFINER wrapper `purge_workspace_member_actions() RETURNS int` does `SET LOCAL session_replication_role = 'replica'` then `DELETE FROM workspace_member_actions WHERE created_at < now() - interval '7 years'`, captures row count via `GET DIAGNOSTICS`, then `RESET session_replication_role` and `RAISE LOG 'audit_retention_purge table=workspace_member_actions deleted_count=%', v_rows`, finally returns the deleted row count. `pg_cron` job `workspace-member-actions-retention` runs daily 04:00 UTC and invokes the wrapper. Observability via (a) `cron.job_run_details` (auto-populated by pg_cron; canonical source of truth for run cadence + return value) and (b) the `RAISE LOG` stream flowing through Supabase logs → Vector → Better Stack. Direct `DELETE` from cron is not used — would silently fail against the WORM trigger (per learning `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep`). [Updated 2026-05-22 — dropped the `tenant_deploy_audit` mirror per plan-review P0-2: that table's `event_type` CHECK rejects `'audit_retention_purge'` and it has no `payload` column.]
- **FR8 — Backfill existing memberships.** Migration creates the table, the WORM trigger, AND the AFTER-trigger on `workspace_members` BEFORE running backfill. Backfill block wraps in `SET LOCAL session_replication_role = 'replica'` so it bypasses the WORM trigger on direct INSERTs into `workspace_member_actions`. One synthetic `action_type = 'added'` row per existing `workspace_members` row with `actor_user_id = NULL`, `target_user_id = workspace_members.user_id`, `new_role = workspace_members.role`, `created_at = workspace_members.created_at`. Idempotent: `WHERE NOT EXISTS (SELECT 1 FROM workspace_member_actions a WHERE a.workspace_id = m.workspace_id AND a.target_user_id = m.user_id AND a.action_type = 'added')`. Prevents day-one "empty audit" deception.
- **FR9 — DSAR cascade wiring (three files + one mig 058 RPC re-CREATE).** Add `workspace_member_actions` to: (a) `apps/web-platform/server/dsar-export-allowlist.ts` — Art. 15 export table list; (b) `apps/web-platform/server/dsar-export.ts` — add per-table read block with predicate `actor_user_id.eq.$1, target_user_id.eq.$1` (supabase-js `.or()` syntax); (c) `apps/web-platform/server/account-delete.ts` — invoke `anonymise_workspace_member_actions(p_user_id)` as inline step **`3.93`** AFTER step `3.92` (`anonymise_organization_membership`) and BEFORE step `4` (`auth.admin.deleteUser`); header JSDoc updated with `5.9` entry. (d) Migration 063 re-`CREATE OR REPLACE`s `anonymise_workspace_members` (mig 058) to set `SET LOCAL session_replication_role='replica'` before its DELETE — this prevents the new AFTER trigger from creating orphan `removed` audit rows with `target_user_id=<userId>` during the cascade (which, if step `3.93` then failed, would be net-new PII for a user requesting Art. 17 erasure — plan-review P1-2 fix). [Updated 2026-05-22 — step numbers corrected to match actual `account-delete.ts:359-441` inline numbering; ordering reflects orphan-PII fix.]

## Technical Requirements

- **TR1 — Migration number.** `063_workspace_member_actions.sql`. Audited 2026-05-22 across 14 sibling worktrees — none claim 062. If a sibling lands 062 before this PR, bump to next free.
- **TR2 — `cq-pg-security-definer-search-path-pin-pg-temp`.** Every SECURITY DEFINER fn pins `SET search_path = public, pg_temp` (public first).
- **TR3 — Default-privileges defeat REVOKE.** Per `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`: explicit `REVOKE FROM PUBLIC, anon, authenticated` AND explicit `GRANT EXECUTE TO service_role` on every RPC. REVOKE FROM PUBLIC alone is insufficient.
- **TR4 — RLS-zero-policies + service_role bypass.** Match `tenant_deploy_audit` (043) pattern. Enable RLS; create zero policies. All reads route through `list_workspace_member_actions` SECURITY DEFINER RPC.
- **TR5 — No `CREATE INDEX CONCURRENTLY`.** Per `cq-supabase-migration-no-concurrently` (Supabase wraps each migration in a transaction).
- **TR6 — Indexes.** `CREATE INDEX ON workspace_member_actions (workspace_id, created_at DESC)` for owner-list query path. `CREATE INDEX ON workspace_member_actions (target_user_id) WHERE target_user_id IS NOT NULL` for Art. 17 anonymise sweep.
- **TR7 — Down migration.** Provide `06X_workspace_member_actions.down.sql` that drops the cron job, RPCs, triggers, and table in reverse-dependency order.
- **TR8 — Article 30 register update.** Append `PA-20 — workspace membership audit log` to `knowledge-base/legal/article-30-register.md` (PA-18 = template_authorizations from PR-I #4078). Lawful basis: Art. 6(1)(c) legal obligation (Art. 5(2) accountability) + Art. 6(1)(f) legitimate interest (operational integrity). Retention: 7 years. Anonymise cascade: `anonymise_workspace_member_actions(p_user_id)` callable from `account-delete.ts` + `dsar-export.ts`.
- **TR9 — Sentinel coverage.** `hr-write-boundary-sentinel-sweep-all-write-sites` — grep every `workspace_members` INSERT/UPDATE/DELETE site under `apps/web-platform/` and confirm each is reachable from a SECURITY DEFINER RPC that sets the `workspace_audit.actor_user_id` GUC, OR is an explicit admin-tool / test-fixture path with documented NULL-actor expectation. Direct-SQL fixture sites at `apps/web-platform/test/helpers/workspace-members-fixtures.ts:127, 153` are accepted as NULL-actor paths.
- **TR10 — GUC-name uniqueness.** Confirm `workspace_audit.actor_user_id` does not collide with any existing GUC namespace (verified 2026-05-22 — no usage; codebase house style uses `app.<table>_anonymise_in_progress` for anonymise flags, but `workspace_audit.actor_user_id` is a different concern — trigger-time actor capture — and gets its own namespace).
- **TR10a — No `auth.uid()` fallback inside the trigger.** Trigger MUST NOT `COALESCE(current_setting(...), auth.uid())` — inside a SECURITY DEFINER context `auth.uid()` returns the DEFINER (postgres), not the calling user, which would silently capture `postgres` as the actor. Add a SQL comment on the trigger body explaining this.
- **TR11 — Re-create 058 RPCs to set GUC.** Migration 063 must `CREATE OR REPLACE` `invite_workspace_member`, `remove_workspace_member`, and `anonymise_workspace_members` against the mig 058 bodies. The first two prepend `PERFORM set_config('workspace_audit.actor_user_id', COALESCE(auth.uid()::text, ''), true);` (plan-review P0-5: not `SET LOCAL`). The third prepends `SET LOCAL session_replication_role = 'replica';` to bypass the new AFTER trigger during account-delete cascade (plan-review P1-2). Preserve all argument signatures and grant matrices.
- **TR12 — Cron observability.** `purge_workspace_member_actions()` MUST `RAISE LOG 'audit_retention_purge ...'` on every run. Observability lives in (a) `cron.job_run_details` (auto-populated by pg_cron — start_time, end_time, return_message), and (b) the `RAISE LOG` stream. A silently-skipped retention sweep = undetected Art. 5(1)(e) breach; the Better Stack alert queries `cron.job_run_details` via Supabase logs API for "missing successful run in 26h" (gates the load-bearing single-user-incident scope). [Updated 2026-05-22 — dropped `tenant_deploy_audit` mirror per plan-review P0-2.]
- **TR13 — Sentry mirror on NULL-actor from authenticated role.** When the trigger reads NULL for `workspace_audit.actor_user_id` AND the calling role is `authenticated` (not `postgres`/`service_role`), emit a structured log row (`audit_orphan_actor`) so Sentry / Better Stack catches a future RPC that mutates `workspace_members` without setting the GUC. Production-NULL from `authenticated` = silent-audit-gap regression signal.

## Acceptance Criteria

### Pre-merge (PR CI)

- **AC1** — Inserting a row into `workspace_members` via `invite_workspace_member` produces exactly one `workspace_member_actions` row with `action_type='added'`, `actor_user_id = caller.user_id`, `target_user_id = invitee.user_id`, `new_role = members.role`, `attestation_id` populated by trigger-time lookup against `workspace_member_attestations` (most recent matching `(workspace_id, invitee_user_id)`).
- **AC1a** — Migration 063's altered `invite_workspace_member`, `remove_workspace_member`, AND `anonymise_workspace_members` RPCs contain the expected GUC/replica-role calls: pgTAP grep on `pg_proc.prosrc` asserts the first two contain `set_config('workspace_audit.actor_user_id'`, and `anonymise_workspace_members` contains `SET LOCAL session_replication_role`.
- **AC1b** — Direct-SQL INSERT into `workspace_members` without the GUC set produces an audit row with `actor_user_id = NULL` AND a structured log row `audit_orphan_actor` is emitted (TR13).
- **AC1c** — Trigger body grep does NOT contain `auth.uid()` (TR10a).
- **AC2** — Deleting a `workspace_members` row via `remove_workspace_member` produces exactly one `workspace_member_actions` row with `action_type='removed'`, `actor_user_id = remover.user_id`, `target_user_id = removed.user_id`, `old_role = members.role`.
- **AC2a** — When `remove_workspace_member` raises (e.g., higher-level last-owner guard), the transaction rolls back and no audit row is produced.
- **AC3** — UPDATE-emission path: a direct-SQL `UPDATE workspace_members SET role='owner'` produces a `role_changed` audit row with `old_role` + `new_role` populated; no-op UPDATEs (same role) produce no audit row. (No v1 RPC produces this event; admin-tool path is the only writer.)
- **AC4** — Direct `UPDATE` or `DELETE` against `workspace_member_actions` from `authenticated` OR `service_role` (raw SQL via PostgREST RPC, NOT through the SECURITY DEFINER wrappers) is rejected with `P0001`.
- **AC4a** — Calling `anonymise_workspace_member_actions(p_user_id)` (SECURITY DEFINER) from `service_role` succeeds — proves the bypass path works via the wrapper RPC's `SET LOCAL session_replication_role='replica'`. Raw `SET LOCAL session_replication_role` from a `service_role` session would fail (requires superuser); the bypass is only reachable through the SECURITY DEFINER wrapper functions (plan-review P1-2 clarification).
- **AC5** — `anonymise_workspace_member_actions(p_user_id)` invocation NULLs both `actor_user_id` and `target_user_id` for matching rows while leaving lineage columns intact, and returns the row count. Re-running on already-anonymised data returns 0 and changes no rows (idempotent).
- **AC6** — A non-owner authenticated session calling `list_workspace_member_actions(p_workspace_id)` returns zero rows (no error, no leak); a non-existent `p_workspace_id` also returns zero rows.
- **AC7** — The owner of a workspace calling `list_workspace_member_actions(p_workspace_id)` sees all rows for that workspace ordered by `created_at DESC, id DESC`. Cursor pagination round-trips: passing the oldest returned `created_at` of page N as `p_cursor` for page N+1 retrieves the next page with no overlap, no skip.
- **AC8** — Backfill produces one synthetic `added` row per pre-existing `workspace_members` row at migration-apply time, with `created_at` matching the source membership's `created_at` (not `now()`). Idempotent on re-run via `NOT EXISTS` discriminator (zero new inserts).
- **AC9** — `pg_cron` job is scheduled with the canonical name `workspace-member-actions-retention` at `0 4 * * *`, invoking `purge_workspace_member_actions()` (not a direct DELETE).
- **AC9a** — `purge_workspace_member_actions()` invocation by `postgres` deletes rows older than 7 years, returns the count, AND emits a `RAISE LOG 'audit_retention_purge ...'` row visible in Supabase logs. `cron.job_run_details` row is auto-populated by pg_cron with start/end timestamps + the integer return value (TR12). [Updated 2026-05-22 — dropped `tenant_deploy_audit` mirror per plan-review P0-2.]
- **AC10** — Down migration removes the cron job, wrapper RPCs, AFTER trigger, WORM trigger, anonymise RPC, reader RPC, indexes, and table in reverse-dependency order with no orphan objects. The `invite_workspace_member` and `remove_workspace_member` RPCs revert to their mig-058 bodies (no `SET LOCAL workspace_audit.actor_user_id`).
- **AC11** — DSAR cascade three-file sentinel grep: `dsar-export-allowlist.ts`, `dsar-export.ts`, `account-delete.ts` all reference `workspace_member_actions`. `account-delete.ts` invokes `anonymise_workspace_member_actions` BEFORE `auth.admin.deleteUser`.
- **AC12** — Article 30 register `PA-20 — workspace membership audit log` exists with lawful basis (Art. 6(1)(c) + 6(1)(f)), retention (7y), and anonymise cascade reference.

### Post-merge (operator / CI on main)

- **AC13** — Migration applies cleanly to dev Supabase via the canonical `web-platform-release.yml#migrate` workflow (NOT applied from this worktree pre-merge per learning `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`).
- **AC14** — After migration apply, `SELECT count(*) FROM public.workspace_member_actions` returns the count of pre-existing `workspace_members` rows (backfill landed). `SELECT count(*) FROM cron.job WHERE jobname = 'workspace-member-actions-retention'` returns 1.
- **AC15** — PostgREST schema cache reload confirmed: `service_role` client can call `list_workspace_member_actions(<workspace_id>)` against the deployed instance without `PGRST205` (allow ≤5 min cache TTL).

## Test Plan

- **Unit (pgTAP)** — One file `apps/web-platform/supabase/tests/workspace_member_actions.sql` covering AC1–AC10.
- **Integration (Vitest)** — Extend `apps/web-platform/e2e/team-membership.e2e.ts` with two scenarios: (a) Jean adds Harry → expect 1 audit row; (b) Jean lists audit → returns 1 row; Harry lists same workspace's audit → returns 0 rows.
- **DSAR cascade** — Add to `apps/web-platform/test/dsar-cascade.test.ts` (or sibling) confirming anonymise sweeps `workspace_member_actions` when a user requests Art. 17 erasure.
- **WORM** — Direct-SQL UPDATE/DELETE attempts in pgTAP must fail with the documented WORM error code.

## Risks & Mitigations

- **R1 — Actor GUC missing on a future writer path** → trigger writes `actor_user_id = NULL`. Mitigation: TR9 sentinel sweep + TR13 Sentry mirror on `authenticated`-role NULL-actor; admin-tool / migration-time / fixture paths are intentionally NULL.
- **R2 — Anonymise RPC missing from DSAR cascade** → user-delete completes without anonymising audit rows, leaving PII orphaned (per learning `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`). Mitigation: FR9 makes the three-file wiring first-class; AC11 sentinel grep gates merge.
- **R3 — `workspace_audit.actor_user_id` GUC collision** → wrong user_id captured. Mitigation: TR10 grep ran clean 2026-05-22.
- **R4 — Backfill duplicate row on re-apply** → audit row count drifts from membership row count. Mitigation: `NOT EXISTS` discriminator on backfill INSERT (AC8); Supabase wraps each migration in a transaction so single-apply atomicity holds.
- **R5 — Flag-flip happens before this lands** → first external workspace operates without audit. Mitigation: PR description names this as flip-gate; spec-flow analyzer + user-impact-reviewer at PR review re-verify.
- **R6 — Partial anonymise: account-delete fails AFTER anonymise_workspace_member_actions but BEFORE auth.admin.deleteUser** → user remains authenticatable but their audit-row PII is NULL. Mitigation: anonymise RPC is idempotent (AC5); re-running account-delete is safe; cascade-rollback documented inline.
- **R7 — PostgREST schema cache lag** → `service_role` client gets `PGRST205` for ≤5 min after migration apply (per learning `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`). Mitigation: post-merge AC15 retries with backoff.
- **R8 — Cron job silently blocked by WORM trigger** → 7-year retention never fires, Art. 5(1)(e) breach undetected. Mitigation: FR7 routes cron through wrapper RPC with replica-bypass; TR12 mirrors run to `tenant_deploy_audit`; AC9a asserts both.
- **R9 — Dev Supabase drift if applied from this worktree** → `Tenant integration (dev-Supabase)` job on main breaks (per learning `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`). Mitigation: do NOT apply 062 to dev from this worktree; apply happens via `web-platform-release.yml#migrate` post-merge (AC13).

## Out of Scope (deferred follow-ups)

- Settings-page UI for the audit viewer — file a follow-up issue when an external workspace requests it.
- v2 broader-scope audit (KB writes, agent runs, BYOK, canUseTool) — parent #4229 Decision 10; revisit when external evidence demands.
- `tenant-audit-table` productize skill (see brainstorm Productize Candidate) — file follow-up only if post-merge audit-table count passes 4.
- Workspace-deletion cascade for `workspace_member_actions` (FK is `ON DELETE RESTRICT` — workspace cannot be deleted while audit rows exist; addressed when workspace-delete UX is built).
- `change_member_role` RPC — no v1 caller exists; the `role_changed` enum stays in the CHECK constraint for forward-compat. If/when role-change UX is built, a future PR adds the RPC with `SET LOCAL workspace_audit.actor_user_id`.
- **Art. 16 rectification** — append-only WORM ledger has no rectification mechanism. Rationale: rectification would require either a `corrects_id` column with append-of-correction-row semantics OR a parallel correction table; both are v2 designs that introduce design surface and operational complexity for a v1 use case with no observed need. PA-20's lawful basis (Art. 6(1)(c) + 6(1)(f) accountability) supports a derogation argument under Art. 23 for proportionate restriction of Art. 16 where rectification would defeat the audit's evidentiary purpose. Re-evaluate when the first regulator/customer requests rectification; documented for transparency in PA-20. (GDPR-gate AP-05 fold-in 2026-05-22.)
- **Customer-facing privacy policy update** for PA-20 — deferred to flag-flip-prep PR (T-01 fold-in). Required before `TEAM_WORKSPACE_INVITE_ENABLED` flips ON for any non-jikigai org. File follow-up issue at this PR's merge time. Internal jikigai use (Jean + Harry) is covered by parent #4229 Side Letter (Decision 11).
- **Invite-time data subject notice for workspace members** — deferred (T-02 fold-in). Covered for jikigai via Side Letter; external workspaces gated on the flag-flip-prep PR above.
- **DPD §2.3 update** — covered by sibling worktree `feat-team-workspace-legal-scaffolding` per parent Decision 11.5. Cross-link only; no duplicate edit in this PR.

## References

- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md` (Decision 10 deferral)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md`
- Migration patterns: `043_tenant_deploy_audit.sql`, `053_organizations_and_workspace_members.sql`, `058_workspace_member_attestations.sql`
- WORM-trigger pure-reject pattern (canonical post-2026-05-18): `apps/web-platform/supabase/migrations/037_audit_byok_use.sql` (`audit_byok_use_no_mutate`) + `051_action_class_widening_and_action_sends.sql` (`action_sends_no_mutate`) + `053_template_authorizations.sql` (`template_authorizations_no_mutate`) + learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`. (Spec v1 misattributed to mig 048; corrected at plan-review 2026-05-22.)
- Default privileges learning: `knowledge-base/project/learnings/2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`
- pg_cron + WORM trigger interaction: `knowledge-base/project/learnings/2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`
- Migration mandates + wired call sites: `knowledge-base/project/learnings/2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`
- PostgREST schema cache lag: `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`
- Dev-Supabase drift from feature-branch migrations: `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
- RLS-zero-policies anon DELETE semantics: `knowledge-base/project/learnings/2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`
- RLS deny tests need schema-correct payloads: `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
- WORM ledger RLS owner-insert is RPC bypass: `knowledge-base/project/learnings/2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`
- Issue: #4231 (this scope); #4229 (parent, CLOSED via #4225)
- Branch: `feat-workspace-member-actions-audit-4231`
- Draft PR: #4287
