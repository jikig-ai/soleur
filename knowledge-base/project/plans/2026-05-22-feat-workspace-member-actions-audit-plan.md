---
feature: feat-workspace-member-actions-audit-4231
date: 2026-05-22
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
classification: schema-migration + auth-flow-edit
issue: 4231
parent_issue: 4229
branch: feat-workspace-member-actions-audit-4231
pr: 4287
spec: knowledge-base/project/specs/feat-workspace-member-actions-audit-4231/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md
---

# Plan: `workspace_member_actions` Audit Log (#4231)

## Overview

Implement an append-only audit log for workspace membership mutations as a trigger-driven write fed by re-issued `invite_workspace_member` and `remove_workspace_member` RPCs (mig 058), with owner-only read access via SECURITY DEFINER RPC, pure-reject WORM trigger + `session_replication_role='replica'` bypass for anonymise and cron-purge paths, 7-year retention, Article 30 PA-19 registration, and DSAR Art. 15 export + Art. 17 anonymise cascade wiring.

The migration ships as `062_workspace_member_actions.sql` (+ `.down.sql`) and blocks the `TEAM_WORKSPACE_INVITE_ENABLED` feature flag flip for any non-jikigai org. Brand-survival threshold `single-user incident` inherited from the parent brainstorm (#4229) — the audit table's own RLS posture is the load-bearing risk axis.

## User-Brand Impact

Carry-forward from `knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md` §`## User-Brand Impact`. Reproduced here for the plan-time enforcement gate (AGENTS.md `hr-weigh-every-decision-against-target-user-impact`):

**If this lands broken, the user experiences:** missing membership audit rows for the first non-jikigai workspace owner; the owner cannot demonstrate who added/removed which member during a regulator inquiry, member dispute, or incident-scoping investigation. Operationally invisible until evidence is requested.

**If this leaks, the user's workspace membership history is exposed via:** a mis-written RLS predicate or owner-check JOIN gating `list_workspace_member_actions` returns rows from a workspace the caller does not own — Vector 1 from the parent brainstorm (cross-workspace audit-row read).

**Brand-survival threshold:** `single-user incident` — one mis-written owner-check predicate that leaks one workspace's membership history to a peer-workspace member is unrecoverable for trust.

**Sign-off chain:** CPO sign-off required at plan time (handled by carry-forward from #4229's CPO assessment, see `## Domain Review`). `user-impact-reviewer` agent invoked at PR review per `single-user incident` threshold.

## Research Reconciliation — Spec vs. Codebase

Phase 1 research surfaced material spec drift from the brainstorm-authored spec.md. Drift was applied in-place to spec.md (commit pending in this PR) and is summarised here so the plan's phase ordering reflects the corrected truth.

| # | Spec claim (pre-fix) | Reality | Plan response |
|---|---|---|---|
| 1 | `accept_workspace_invite` RPC | Does not exist — invite is one-shot via `invite_workspace_member` (mig 058:167) | spec FR3 + AC1 rewritten; plan Phase 2 wires the GUC `SET LOCAL` into this RPC |
| 2 | `change_member_role` RPC | Does not exist; no v1 caller would produce `role_changed` events | spec drops the RPC reference, keeps the CHECK-constraint enum for forward-compat (NG); AC3 reframed as direct-SQL admin-path probe |
| 3 | `workspaces.org_id` join column | Real column is `workspaces.organization_id` (mig 053:242) | spec FR4 + plan §Phase 3 owner-check JOIN use `organization_id` |
| 4 | WORM via structural-diff (mig 058 pattern) | **Plan-review correction (2026-05-22):** mig 048 is `precheck_jwt_mint_sqlstate.sql` + `scope_grants.sql` — NEITHER ships pure-reject. The canonical pure-reject + `session_replication_role='replica'` bypass precedents are **mig 037** (`audit_byok_use_no_mutate`), **mig 051** (`action_sends_no_mutate`), **mig 052** (`audit_github_token_use_no_mutate` patches in mig 052's body), and **mig 053b** (`053_template_authorizations.sql`). Lift mig 037 as the simplest reference body. | spec FR5/FR6/FR7 + plan Phase 2 + Phase 4 switch to pure-reject lifted from **mig 037/051** |
| 5 | DSAR cascade is 2 files | DSAR cascade is THREE files: `dsar-export-allowlist.ts`, `dsar-export.ts` (per-table read block), `account-delete.ts` (anonymise call in step 5.8) | spec FR9 enumerates all three; plan Phase 5 covers each |
| 6 | "PA-X" placeholder in Article 30 register | PA-18 = template_authorizations (PR-I #4078). Next slot = **PA-19** | spec TR8 + plan Phase 6 use PA-19 |
| 7 | Migration number TBD | 062 is free across all 14 sibling worktrees (audited 2026-05-22) | spec TR1 + plan claim 062 |
| 8 | `pg_cron` does DELETE directly | Pure-reject WORM blocks direct DELETE silently — Art. 5(1)(e) breach per learning `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` | spec FR7 + plan Phase 4 route cron through `purge_workspace_member_actions()` SECURITY DEFINER wrapper |
| 9 | Backfill uses table-LOCK | No table-LOCK precedent in any migration; convention is `NOT EXISTS` discriminator inside the migration transaction. Backfill must also wrap in `SET LOCAL session_replication_role='replica'` to bypass the WORM trigger | spec FR8 + plan Phase 3 |
| 10 | `auth.uid()` fallback inside trigger is fine | Inside SECURITY DEFINER, `auth.uid()` returns the DEFINER (postgres), silently capturing the wrong actor | spec TR10a + plan Phase 2 trigger body comment + AC1c grep |

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO), Finance (CFO) — carried forward from parent brainstorm `2026-05-21-team-workspace-multi-user-brainstorm.md`.

**Brainstorm-recommended specialists:** none — the brainstorm did not name specialists by role (no ux-design-lead, copywriter, conversion-optimizer, retention-strategist, pricing-strategist). v1 has no UI surface.

### Engineering (CTO)

**Status:** carry-forward
**Assessment:** Additive migration on top of 053/058; trigger-on-table is the impossible-to-forget surface. Pure-reject WORM + replica bypass replaces the structural-diff pattern as the v2 cleaner approach (drift item 4). No new substrate.

### Legal (CLO)

**Status:** carry-forward
**Assessment:** Endorses 7y retention + Art. 17 anonymise as SOC2/SOX-defensible without conflicting with Art. 5(1)(e) data-minimisation. PA-19 in the Article 30 register is the load-bearing legal artifact. Anonymise cascade ordering (BEFORE `auth.admin.deleteUser`) is non-negotiable.

### Product (CPO)

**Status:** carry-forward (sign-off attested at plan time per `requires_cpo_signoff: true`)
**Assessment:** Owner-only audit view is a settings-page concern, deferred to a v2 follow-up. v1 ships the data primitive that blocks the flag-flip. No public surface, no positioning change. **Product/UX Gate tier: NONE** — no new user-facing pages, no multi-step flows; data primitive only.

### Finance (CFO)

**Status:** carry-forward
**Assessment:** Zero marginal COGS. Volume floor (tens of rows per workspace per year) is decimal-dust on Supabase Pro. No vendor seat triggers.

## Observability

Files-to-edit include code-class paths under `apps/web-platform/server/` AND `apps/web-platform/supabase/migrations/`, so the Phase 2.9 gate fires. Schema:

```yaml
liveness_signal:
  what: pg_cron job `workspace-member-actions-retention` last-run timestamp + `tenant_deploy_audit` row with `event_type='audit_retention_purge'` written by `purge_workspace_member_actions()`
  cadence: daily at 04:00 UTC; alert if no row in 26h
  alert_target: Better Stack uptime monitor on a Supabase logs query; routes to ops@jikigai.com
  configured_in: knowledge-base/engineering/runbooks/cron-retention-monitor.md (new — Phase 6) + Better Stack monitor (Phase 6, post-merge)
error_reporting:
  destination: Sentry (via Pino logger in server-side TS); structured log row `audit_orphan_actor` for NULL-actor-from-authenticated; `tenant_deploy_audit` row on retention-purge runs
  fail_loud: true — `audit_orphan_actor` log row + Sentry `captureMessage` at WARN level with structured tags `{tool: 'workspace_member_actions', kind: 'orphan_actor', workspace_id, target_user_id}`
failure_modes:
  - mode: pg_cron job stops firing (transaction abort, role grant rotted, supabase upgrade migration of cron extension)
    detection: Better Stack alert on missing `tenant_deploy_audit{event_type='audit_retention_purge'}` row in 26h window
    alert_route: ops@jikigai.com
  - mode: WORM trigger silently rejects pg_cron DELETE (wrapper RPC missing replica bypass)
    detection: same alert as above — no purge row in 26h
    alert_route: ops@jikigai.com
  - mode: NULL actor_user_id from authenticated role (future RPC author forgets SET LOCAL)
    detection: Sentry `audit_orphan_actor` rule; per-event page at >5/24h
    alert_route: ops@jikigai.com
  - mode: anonymise RPC missing from account-delete cascade (regression of FR9 wiring)
    detection: AC11 sentinel grep at CI time; dsar-cascade.test.ts coverage
    alert_route: PR review block (pre-merge)
logs:
  where: Supabase logs (pg_cron + RAISE LOG) feeding Vector → Better Stack; Pino → Sentry for server-side TS
  retention: 30d in Better Stack (current free-tier ceiling); 14d in Supabase logs (current)
discoverability_test:
  # Operator-runnable, no SSH, no shell expansion (Check 10-compatible).
  # Verifies Supabase REST is reachable from the operator's network. Returns
  # 401 (no apikey header — expected) when the API is up; anything else
  # (DNS fail, 5xx, 200 without apikey) signals an upstream issue. The
  # canonical post-merge AC14/AC15 probes route via the Supabase MCP server
  # — see knowledge-base/project/specs/feat-workspace-member-actions-audit-4231/migration-checklist.md
  # for the MCP queries that verify schema parity + cron scheduling.
  command: curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/health
  expected_output: "200"
```

## Implementation Phases

**Detail level:** MORE — moderate complexity (one migration + three TS callers + one pgTAP file + Article 30 edit), cascading effects across DSAR + cron, single-user incident threshold requires explicit phase ordering.

### Phase 0 — Preconditions and CPO Sign-off Attestation

- **0.1** — Verify branch + worktree: `git branch --show-current` returns `feat-workspace-member-actions-audit-4231`; `pwd` ends in `.worktrees/feat-workspace-member-actions-audit-4231`.
- **0.2** — Re-verify migration 062 is still free: `for wt in /home/jean/git-repositories/jikig-ai/soleur/.worktrees/*/; do ls "$wt/apps/web-platform/supabase/migrations/" 2>/dev/null | grep '^062_'; done | head -5` — expect empty. If non-empty, bump to next free number across the spec + plan + tasks.md in one commit.
- **0.3** — CPO sign-off attestation: this plan inherits CPO sign-off from #4229's parent brainstorm assessment (Decision 10 explicitly deferred this work with re-evaluation criteria). The narrowed v1 scope (membership-only) is strictly within Decision 10's bounded surface. No fresh CPO spawn required; note `cpo_signoff: carry-forward-from-4229` in plan body.
- **0.4** — Read mig 037's `audit_byok_use_no_mutate` trigger + the matching anonymise RPC (`apps/web-platform/supabase/migrations/037_audit_byok_use.sql`) as the canonical pure-reject + replica-bypass template. Cross-reference mig 051 §(c)+(h) (`051_action_class_widening_and_action_sends.sql`) for the `RESET session_replication_role` convention after each replica-bypass call. Read mig 053 + 058 backfill / RPC bodies as call-site templates.
- **0.5** — Probe canonical parsing pattern for any future `lane:` / frontmatter parsing in plan tooling: confirm `awk '/^lane:/ { gsub(/^lane:[[:space:]]*"?|"?$/, ""); print; exit }'` works against this plan file (defensive; tasks.md derivation may use this pattern).

### Phase 1 — Migration File Skeleton

- **1.1** — Create `apps/web-platform/supabase/migrations/062_workspace_member_actions.sql` with header block (LAWFUL_BASIS, RETENTION, WORM contract reference to **mig 037 + 051**, RoPA PA-19 cite, learning cites for `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`, `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`, `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`).
- **1.2** — Create `apps/web-platform/supabase/migrations/062_workspace_member_actions.down.sql` with reverse-dependency DROP order: cron job → wrapper RPCs (`purge_*`, `anonymise_workspace_member_actions`, `list_*`) → AFTER trigger on workspace_members → WORM trigger on workspace_member_actions → indexes → table. **NOT REVERTED:** the `set_config('workspace_audit.actor_user_id', ...)` calls prepended to `invite_workspace_member` + `remove_workspace_member` + `anonymise_workspace_members`; they become harmless no-ops once the trigger that reads the GUC is dropped (no need to pin and restore mig 058's RPC bodies, which would be fragile per plan-review P0-4). Confirmed safe because `set_config` always returns the prior value and has no side-effect outside the read by the trigger.
- **1.3** — Table DDL (section 1 of migration): `CREATE TABLE public.workspace_member_actions` with columns per spec FR1. **`created_at timestamptz NOT NULL DEFAULT now()`** explicit on the column. CHECK constraint allows `added | removed | role_changed`. FKs: `workspace_id REFERENCES public.workspaces(id) ON DELETE RESTRICT`; `actor_user_id REFERENCES public.users(id) ON DELETE RESTRICT` NULLable; `target_user_id REFERENCES public.users(id) ON DELETE RESTRICT` NULLable; `attestation_id REFERENCES public.workspace_member_attestations(id) ON DELETE RESTRICT` NULLable. **All user-ref FKs target `public.users(id)`, not `auth.users(id)`** — matches sibling mig 053:51,83 and mig 058:45,46 conventions; mixed-schema FKs would break the account-delete cascade ordering (plan-review P0-3).
- **1.4** — Indexes (TR6): `CREATE INDEX workspace_member_actions_workspace_created_idx ON workspace_member_actions (workspace_id, created_at DESC);` `CREATE INDEX workspace_member_actions_target_idx ON workspace_member_actions (target_user_id) WHERE target_user_id IS NOT NULL;` `CREATE INDEX workspace_member_actions_actor_idx ON workspace_member_actions (actor_user_id) WHERE actor_user_id IS NOT NULL;` (Phase 1 Sharp Edge: no `CONCURRENTLY`).
- **1.5** — RLS posture (TR4 + learning `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`): `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` then NO `CREATE POLICY` statements. Explicit `REVOKE INSERT, UPDATE, DELETE ON TABLE ... FROM PUBLIC, anon, authenticated, service_role;` (RPC-only writes). SELECT also REVOKED — reads route through `list_workspace_member_actions` SECURITY DEFINER RPC.

### Phase 2 — WORM Trigger (Pure-Reject) + AFTER Trigger on `workspace_members`

- **2.1** — `workspace_member_actions_no_mutate` BEFORE UPDATE OR DELETE trigger function. Lift mig 037's `audit_byok_use_no_mutate` body verbatim with renamed strings; explicit comment naming the `session_replication_role='replica'` bypass and citing learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` (the canonical post-2026-05-18 pattern). Raises `P0001` on origin-role mutations; returns NULL on replica. `SECURITY INVOKER` (default — function runs as the caller; trigger context handles role authority).
- **2.2** — `workspace_members_audit` AFTER INSERT OR UPDATE OR DELETE trigger function on `public.workspace_members`. **SECURITY DEFINER** (required so the function can write to `workspace_member_actions` even though `authenticated` has no INSERT grant; `SET search_path = public, pg_temp`). Body uses `session_user` (not `current_user`) to read the caller's role for TR13 (current_user under SECURITY DEFINER returns the definer). Bottom:
  ```sql
  CREATE OR REPLACE FUNCTION public.workspace_members_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, pg_temp
  AS $$
  DECLARE
    v_actor uuid;
    v_action text;
    v_target uuid;
    v_old_role text;
    v_new_role text;
    v_attestation uuid;
  BEGIN
    -- Parse actor GUC; tolerate empty / malformed.
    BEGIN
      v_actor := NULLIF(current_setting('workspace_audit.actor_user_id', true), '')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      v_actor := NULL;
    END;
    -- NEVER fall back to auth.uid() — under SECURITY DEFINER it returns the definer (postgres),
    -- not the calling user. NULL is the correct empty value (TR10a; brainstorm OQ1).

    IF TG_OP = 'INSERT' THEN
      v_action := 'added';
      v_target := NEW.user_id;
      v_new_role := NEW.role;
      v_attestation := NEW.attestation_id; -- Use the FK column directly (no lookup race)
    ELSIF TG_OP = 'DELETE' THEN
      v_action := 'removed';
      v_target := OLD.user_id;
      v_old_role := OLD.role;
    ELSIF TG_OP = 'UPDATE' THEN
      IF OLD.role IS NOT DISTINCT FROM NEW.role THEN
        RETURN NULL; -- no-op update
      END IF;
      v_action := 'role_changed';
      v_target := NEW.user_id;
      v_old_role := OLD.role;
      v_new_role := NEW.role;
    END IF;

    INSERT INTO public.workspace_member_actions
      (workspace_id, actor_user_id, target_user_id, action_type, old_role, new_role, attestation_id)
    VALUES
      (COALESCE(NEW.workspace_id, OLD.workspace_id), v_actor, v_target, v_action, v_old_role, v_new_role, v_attestation);

    -- TR13: orphan-actor signal when an authenticated-role caller forgot to set the GUC.
    IF v_actor IS NULL AND session_user = 'authenticated' THEN
      RAISE LOG 'audit_orphan_actor workspace_id=% action=%',
        COALESCE(NEW.workspace_id, OLD.workspace_id), TG_OP;
      -- PII-scrubbed: workspace_id only; target_user_id NOT included (GDPR T-06).
    END IF;

    RETURN NULL;
  END;
  $$;
  ```
  Grant matrix: `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated;` no GRANT (the function is invoked only by the trigger context).
- **2.3** — Attach both triggers: `CREATE TRIGGER ... BEFORE UPDATE OR DELETE ON workspace_member_actions FOR EACH ROW EXECUTE FUNCTION workspace_member_actions_no_mutate();` and `CREATE TRIGGER ... AFTER INSERT OR UPDATE OR DELETE ON workspace_members FOR EACH ROW EXECUTE FUNCTION workspace_members_audit();`
- **2.4** — Grant matrix per TR3: REVOKE all on both fn from PUBLIC, anon, authenticated. No GRANT on the WORM trigger fn (unreachable as caller). No GRANT on the AFTER trigger fn (invoked by trigger context).

### Phase 3 — RPC Bodies: Reader, Anonymise, Writer GUC Wiring

- **3.1** — `list_workspace_member_actions(p_workspace_id uuid, p_limit int DEFAULT 50, p_cursor timestamptz DEFAULT NULL) RETURNS SETOF public.workspace_member_actions`. SECURITY DEFINER, `SET search_path = public, pg_temp`. Body:
  ```
  IF auth.uid() IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM organizations o
    JOIN workspaces w ON w.organization_id = o.id
    WHERE w.id = p_workspace_id AND o.owner_user_id = auth.uid()
  ) THEN RETURN; END IF;
  RETURN QUERY
    SELECT * FROM public.workspace_member_actions
    WHERE workspace_id = p_workspace_id
      AND (p_cursor IS NULL OR created_at < p_cursor)
    ORDER BY created_at DESC, id DESC
    LIMIT p_limit;
  ```
  REVOKE all FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO authenticated (so the RPC is reachable; the body enforces owner-check).
- **3.2** — `anonymise_workspace_member_actions(p_user_id uuid) RETURNS int`. SECURITY DEFINER, `SET search_path = public, pg_temp`. Body:
  ```sql
  DECLARE v_rows int;
  BEGIN
    SET LOCAL session_replication_role = 'replica';
    UPDATE public.workspace_member_actions
       SET actor_user_id = NULL, target_user_id = NULL
     WHERE actor_user_id = p_user_id OR target_user_id = p_user_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET session_replication_role;  -- mig 051/053b convention
    RETURN v_rows;
  END;
  ```
  Idempotent (re-run's WHERE-clause matches zero already-NULLed rows). REVOKE all FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role.
- **3.3** — `purge_workspace_member_actions() RETURNS int`. SECURITY DEFINER, `SET search_path = public, pg_temp`. Body:
  ```sql
  DECLARE v_rows int;
  BEGIN
    SET LOCAL session_replication_role = 'replica';
    DELETE FROM public.workspace_member_actions
     WHERE created_at < now() - interval '7 years';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET session_replication_role;
    RAISE LOG 'audit_retention_purge table=workspace_member_actions deleted_count=%', v_rows;
    RETURN v_rows;
  END;
  ```
  Observability is via (a) pg_cron's built-in `cron.job_run_details` table — auto-populated on every scheduled run with start/end timestamps + return value — and (b) the `RAISE LOG 'audit_retention_purge ...'` row flowing through Supabase logs → Vector → Better Stack. **No write to `tenant_deploy_audit`** — that table's `event_type` CHECK constraint rejects new values and it has no `payload` column (plan-review P0-2 correction). REVOKE all FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO `postgres` (the role pg_cron runs as).
- **3.4** — `CREATE OR REPLACE FUNCTION public.invite_workspace_member(...)` — copy mig 058:167-247 body verbatim, insert `PERFORM set_config('workspace_audit.actor_user_id', COALESCE(auth.uid()::text, ''), true);` as the FIRST statement after the `BEGIN`. Uses `set_config(name, value, is_local=true)` instead of `SET LOCAL` because `SET LOCAL <key> = <expr>` only accepts literals, not runtime expressions like `COALESCE` (plan-review P0-5 correction). The trigger reads via `current_setting('workspace_audit.actor_user_id', true)` and parses with `NULLIF(..., '')::uuid` + EXCEPTION block (see Phase 2.2).
- **3.5** — `CREATE OR REPLACE FUNCTION public.remove_workspace_member(...)` — same `PERFORM set_config(...)` prepend pattern as 3.4 against mig 058:267-330.
- **3.6** — `CREATE OR REPLACE FUNCTION public.anonymise_workspace_members(p_user_id uuid)` (mig 058) — re-create to set `SET LOCAL session_replication_role = 'replica';` BEFORE its DELETE on `workspace_members`. This prevents the new AFTER trigger from firing during account-delete cascade, eliminating the orphan-PII window where step 3.91's DELETE would create a `removed` audit row with `target_user_id=<deleted user>` before step 3.93 anonymises it (plan-review P1-2 fix). After the DELETE, `RESET session_replication_role;` per convention.
- **3.7** — pgTAP grep guards (will land as ACs in §Test Plan): assert `prosrc` of `invite_workspace_member` + `remove_workspace_member` contains `set_config('workspace_audit.actor_user_id'` after migration applies. Assert `anonymise_workspace_members.prosrc` contains `SET LOCAL session_replication_role`.

### Phase 4 — pg_cron Schedule + Backfill

- **4.1** — Backfill block (order-critical, must come AFTER both triggers exist so the WORM trigger guards the table from day 0):
  ```sql
  DO $$
  BEGIN
    -- Plan-review P1-1: LOCK to prevent concurrent app-server INSERT into workspace_members
    -- from being double-audited (once via the new AFTER trigger, once via the backfill
    -- SELECT). SHARE MODE permits concurrent SELECTs but blocks INSERTs for the duration.
    LOCK TABLE public.workspace_members IN SHARE MODE;
    SET LOCAL session_replication_role = 'replica';
    INSERT INTO public.workspace_member_actions
      (workspace_id, actor_user_id, target_user_id, action_type, new_role, created_at)
    SELECT m.workspace_id, NULL, m.user_id, 'added', m.role, m.created_at
      FROM public.workspace_members m
     WHERE NOT EXISTS (
       SELECT 1 FROM public.workspace_member_actions a
        WHERE a.workspace_id = m.workspace_id
          AND a.target_user_id = m.user_id
          AND a.action_type = 'added'
     );
    RESET session_replication_role;
  END $$;
  ```
- **4.2** — `pg_cron` schedule: `SELECT cron.schedule('workspace-member-actions-retention', '0 4 * * *', $$SELECT public.purge_workspace_member_actions()$$);` Verify `cron.job_run_details` will record runs (this is automatic in modern pg_cron). Schedule registration matches mig 043's pattern.
- **4.3** — Sanity assertion in the migration body (as a `RAISE NOTICE`): backfill row count must equal `(SELECT count(*) FROM workspace_members)`.

### Phase 5 — TypeScript Server Edits (DSAR Cascade)

- **5.1** — `apps/web-platform/server/dsar-export-allowlist.ts`: append `workspace_member_actions` to the export table list (read the file first to see the exact structure — likely an array literal). Plan-time spec drift item 1 confirms this is the right surface.
- **5.2** — `apps/web-platform/server/dsar-export.ts`: add a per-table read block. Lift the shape from any sibling block (lines 603-630 per research). Predicate: `eq('actor_user_id', userId).or(eq('target_user_id', userId))` — supabase-js `.or()` syntax with `actor_user_id.eq.${userId},target_user_id.eq.${userId}`. Verify supabase-js syntax against `node_modules/@supabase/postgrest-js/dist/PostgrestFilterBuilder.d.ts` before committing.
- **5.3** — `apps/web-platform/server/account-delete.ts`: add inline step **`3.93`** AFTER step `3.92` (`anonymise_organization_membership`) and BEFORE step `4` (`auth.admin.deleteUser`). With the Phase 3.6 fix (re-CREATE `anonymise_workspace_members` to bypass the AFTER trigger via replica role), step `3.91`'s cascade DELETEs no longer create audit rows. Step `3.93` only anonymises rows from prior legitimate `invite_workspace_member` / `remove_workspace_member` calls.
  ```ts
  // 3.93 Anonymise workspace_member_actions audit rows (migration 062).
  //      Sets actor_user_id + target_user_id to NULL for every row referencing the
  //      departing user. Lineage columns (workspace_id, action_type, role, created_at,
  //      attestation_id) preserved. Idempotent. MUST run BEFORE auth.admin.deleteUser
  //      (public.users FK is RESTRICT). Cascade DELETEs at step 3.91 do NOT create new
  //      audit rows — anonymise_workspace_members re-CREATE'd in mig 062 sets
  //      session_replication_role='replica' so the AFTER trigger is bypassed during
  //      cascade (eliminates the orphan-PII window).
  const { data: anonAuditCount, error: anonAuditErr } = await service
    .rpc("anonymise_workspace_member_actions", { p_user_id: userId });
  if (anonAuditErr) {
    // Fail-loud pattern matching sibling cascade steps 3.91/3.92.
  }
  ```
- **5.4** — Update the JSDoc header at lines 57-75 to add `5.9 anonymise-workspace-member-actions — anonymise_workspace_member_actions RPC (migration 062). PII NULL-set on audit rows; lineage preserved.` after `5.8 anonymise-organization-membership` and before `6. auth`. (The inline `3.93` does not collide with any existing inline number; the header's `5.9` does not collide with any existing header number.)
- **5.5** — Add a test fixture wiring in `apps/web-platform/test/dsar-cascade.test.ts` (or sibling) asserting `anonymise_workspace_member_actions` is invoked between `anonymise_workspace_members` and `auth.admin.deleteUser`.

### Phase 6 — Article 30 Register + Observability Wiring (Pre-merge)

- **6.1** — Append `## Processing Activity 19 — Workspace membership audit log` to `knowledge-base/legal/article-30-register.md` after the existing PA-18 entry. Schema must match sibling PAs (PA-10, PA-11, PA-17, PA-18 are the closest templates). Required keys per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md` + GDPR-gate fold-ins:
  - **Controller / Processor:** Workspace owner = controller; Soleur = processor (per parent #4229 Decision 11).
  - **Categories of data subjects:** workspace members (controllers' employees / contractors / collaborators).
  - **Categories of personal data:** UUID identifiers (actor_user_id, target_user_id); role enum (text); workspace_id (controller-derived). No Art. 9 special category.
  - **Recipients:** workspace owner (via `list_workspace_member_actions` RPC); Sentry + Better Stack (operational alerts, pseudonymised — TR13 scrub); pg_cron purge writes to `tenant_deploy_audit` (internal).
  - **Retention:** **7 years** — rationale: SOX evidentiary horizon for accountability under Art. 5(2), enabling forensic reconstruction across the longest plausible enterprise records-retention period a customer might invoke. Defensible against Art. 5(1)(e) data-minimisation challenge.
  - **Security measures:** RLS-zero policies; SECURITY DEFINER reader RPC with owner-check; pure-reject WORM trigger; replica-bypass for anonymise + cron only; explicit REVOKE matrix; encrypted at rest (Supabase default).
  - **Lawful basis:** Art. 6(1)(c) legal obligation (Art. 5(2) accountability) + Art. 6(1)(f) legitimate interest (operational integrity). **LIA (legitimate interest assessment):** the balancing test favours processing because (a) data is internal-use-only, never used for product analytics / sales / ML training / feature decisions ("purpose limitation clause"); (b) 7y retention is bounded by SOX horizon; (c) data subjects retain Art. 15 / 17 / 20 rights via DSAR cascade; (d) the audit trail itself protects data subjects from controller misconduct.
  - **International transfers:** Supabase project region — to be confirmed at /work time (`hr-dev-prd-distinct-supabase-projects`). If EU-hosted: no transfer; if US-hosted: SCCs via Supabase DPA.
  - **Anonymise cascade:** `anonymise_workspace_member_actions(p_user_id)` callable from `account-delete.ts` (step 5.8) + `dsar-export.ts`. Idempotent.
  - **Erasure mechanism:** Art. 17 anonymise (NULL PII columns, preserve lineage). Art. 16 rectification: not supported — see Spec §Out of Scope.
  - **Purpose limitation:** data shall NOT be used for product analytics, sales, ML training, feature decisions, or operational research outside the named audit purpose.
  - Cite migration 062 + this PR.
- **6.2** — Add the runbook `knowledge-base/engineering/runbooks/cron-retention-monitor.md` documenting (a) the `cron.job_run_details` table contract (auto-populated by pg_cron with start/end timestamps + return value for `workspace-member-actions-retention`), (b) the Better Stack monitor to be created post-merge (queries `cron.job_run_details` via the Supabase logs API; alerts if no successful run in 26h), (c) the Supabase MCP server query pattern for an operator to manually verify: `mcp__plugin_supabase_supabase__execute_sql` with `SELECT * FROM cron.job_run_details WHERE jobname = 'workspace-member-actions-retention' ORDER BY start_time DESC LIMIT 7`, (d) the parallel `RAISE LOG 'audit_retention_purge ...'` stream visible in Supabase logs for ops drill-in.
- **6.3** — `audit_orphan_actor` log rows route via Supabase logs → Vector → Better Stack (per `apps/web-platform/vector.toml` per recent fix #4279). Pino-side mirror NOT required — the DB-side `RAISE LOG` is the canonical signal. Document in the runbook the Better Stack alert query: filter Supabase logs for `audit_orphan_actor`; page on >5 events/24h.

### Phase 7 — Tests (pgTAP + Vitest integration)

- **7.1** — `apps/web-platform/supabase/tests/workspace_member_actions.sql` — pgTAP file covering AC1–AC10 + AC1a, AC1b, AC1c, AC2a, AC4a, AC9a. Use `BEGIN; SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claim.sub = '<uuid>'; ...; ROLLBACK;` pattern for RLS/role probes. Per learnings `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md` and `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`: use schema-valid UUIDs for all probes, assert dual deny shape (`42501` permission OR empty-set), and re-read via service_role to confirm not-leaked.
- **7.2** — `apps/web-platform/e2e/team-membership.e2e.ts` extension: (a) Jean invites Harry → expect 1 audit row with correct actor/target; (b) Jean lists his workspace's audit → returns ≥1 row; (c) Harry lists Jean's workspace audit → returns empty (no error); (d) Jean removes Harry → expect 2nd audit row with action_type='removed'.
- **7.3** — `apps/web-platform/test/dsar-cascade.test.ts` (or sibling) extension: confirm `anonymise_workspace_member_actions` is in the cascade order between step 5.7 and `auth.admin.deleteUser`.
- **7.4** — Sentinel sweep CI script: `apps/web-platform/scripts/check-workspace-members-write-sites.sh` (or similar — verify path convention at /work) that `git grep`-enumerates all INSERT/UPDATE/DELETE on `public.workspace_members` in `apps/web-platform/{server,supabase/migrations}/` and asserts each matches one of three patterns: (a) a SECURITY DEFINER RPC that contains `SET LOCAL workspace_audit.actor_user_id`, (b) a documented admin-tool path, (c) a test-fixture path with documented NULL-actor expectation (the two sites at `test/helpers/workspace-members-fixtures.ts:127, 153`). Exits non-zero on a violation.
- **7.5** — Cascade-completeness sweep (per GDPR-gate TS-05 fold-in): enumerate every column in `apps/web-platform/supabase/migrations/053_*.sql` and `058_*.sql` that REFERENCES `auth.users(id)` or `public.users(id)`. For each such table, assert it appears in `account-delete.ts`'s cascade chain. Land as a pgTAP file `apps/web-platform/supabase/tests/dsar_cascade_completeness.sql` OR a shell script invoked from CI (verify convention at /work). Exits non-zero if a table holding workspace-member-related PII is missing from the cascade.

### Phase 8 — Pre-merge Validation Loop

- **8.1** — Run pgTAP locally against a fresh Supabase reset: `cd apps/web-platform && bunx supabase db reset && bunx supabase test db` (verify test runner via `package.json scripts.test` and `bunfig.toml`).
- **8.2** — Run Vitest extensions: `cd apps/web-platform && ./node_modules/.bin/vitest run e2e/team-membership.e2e.ts` (per sharp edge — never hardcode `bun test`).
- **8.3** — Run `tsc --noEmit` to catch TS exhaustiveness regressions on any reducer/union touched by the cascade edits.
- **8.4** — Sentinel sweep CI script runs locally: `bash apps/web-platform/scripts/check-workspace-members-write-sites.sh` exits 0.
- **8.5** — Self-`/soleur:preflight` (per AGENTS.md `hr-before-shipping-ship-phase-5-5-runs`) against the worktree before marking PR ready.

## GDPR Gate Outcome (Phase 2.7)

GDPR gate ran 2026-05-22 against this plan + spec + brainstorm. Three Critical Findings; two folded in (PA-19 enrichment + Sentry PII scrub); one deferred to flag-flip-prep PR (customer-facing privacy policy update — not load-bearing for this PR because the migration ships behind a flag OFF in prd outside jikigai; Jean + Harry are covered by parent #4229 Decision 11's Side Letter). Additional fold-ins:

- **AP-05 (Art. 16 rectification gap)** — append-only ledger has no rectification mechanism. Folded in as explicit Spec §Out of Scope with rationale (data minimisation: rectification would require either a `corrects_id` column or a parallel correction-row pattern; both are v2 designs and the v1 use case has no observed need).
- **T-01 (privacy policy update)** — deferred to a follow-up issue. Required before `TEAM_WORKSPACE_INVITE_ENABLED` flag flips ON for any non-jikigai org. File issue at this PR's merge time.
- **T-02 (invite-time data subject notice)** — deferred to flag-flip-prep follow-up. Already covered for jikigai (Jean + Harry) via parent #4229's Side Letter.
- **T-03 (DPD §2.3 update)** — covered by sibling worktree `feat-team-workspace-legal-scaffolding` per parent brainstorm Decision 11.5. Cross-link, do not duplicate.
- **T-06 (Sentry/Better Stack PII)** — folded in via TR13 amendment (drop `target_user_id` from log message body; emit `workspace_id` + `action_type` only).
- **TS-05 (cascade-completeness sweep)** — folded into Phase 7.4 sentinel script extension below.

## Files to Edit

- `apps/web-platform/supabase/migrations/062_workspace_member_actions.sql` *(create)* — table, triggers, RPCs, indexes, backfill, cron schedule, header block.
- `apps/web-platform/supabase/migrations/062_workspace_member_actions.down.sql` *(create)* — reverse-dependency DROP order including revert of 058 RPCs.
- `apps/web-platform/server/dsar-export-allowlist.ts` *(edit)* — append `workspace_member_actions` to the export table list.
- `apps/web-platform/server/dsar-export.ts` *(edit)* — add per-table read block (predicate over `actor_user_id` OR `target_user_id`).
- `apps/web-platform/server/account-delete.ts` *(edit)* — add inline step `3.93` invoking `anonymise_workspace_member_actions` AFTER `3.92` (`anonymise_organization_membership`) and BEFORE `4` (`auth.admin.deleteUser`); append `5.9` to the header JSDoc at lines 57-75.
- `apps/web-platform/supabase/tests/workspace_member_actions.sql` *(create)* — pgTAP file covering AC1–AC10 + extended ACs.
- `apps/web-platform/e2e/team-membership.e2e.ts` *(edit)* — add four scenarios (invite emits audit row, owner list returns rows, non-owner list empty, remove emits second audit row).
- `apps/web-platform/test/dsar-cascade.test.ts` *(edit; verify path exists or use closest sibling)* — extend cascade-order assertion.
- `apps/web-platform/scripts/check-workspace-members-write-sites.sh` *(create; verify scripts dir convention)* — CI sentinel sweep.
- `knowledge-base/legal/article-30-register.md` *(edit)* — append PA-19.
- `knowledge-base/engineering/runbooks/cron-retention-monitor.md` *(create)* — runbook for the retention purge observability + manual operator verification.

## Open Code-Review Overlap

Two open code-review issues touch `apps/web-platform/supabase/migrations` (the directory, not the new file): **#3220** "ci: postmerge verification of trigger-bearing migrations in prd" and **#3221** "ci: nightly cron for env-gated integration tests". Disposition for each:

- **#3220** — **Acknowledge.** This new migration ships a WORM trigger + AFTER trigger and is the highest-value test case for the planned post-merge verification CI. Plan ships migration; #3220 ships verification CI separately. The plan's AC14 (post-merge SQL probe via `mcp__plugin_supabase_supabase__execute_sql`) is the manual-bridge until #3220 lands. Add a note to #3220 referencing #4231 as a load-bearing test case once #4231 merges.
- **#3221** — **Acknowledge.** Nightly cron CI infrastructure is orthogonal to this migration. The new migration's `pg_cron` retention sweep needs its own observability (TR12) which is layered above whatever #3221 ships. No fold-in.

Neither overlap drives a fold-in; both are explicitly acknowledged with re-evaluation notes to be filed against the existing issues post-merge.

## Acceptance Criteria

Carry-forward verbatim from `spec.md` §`## Acceptance Criteria`, structured `Pre-merge (PR)` + `Post-merge (operator)`. The spec is the canonical AC source; this plan does not re-author them.

Key gates the plan adds on top of the spec ACs:

- **Pre-merge gate:** Sentinel sweep CI script (Phase 7.4) exits 0 on the diff before merge.
- **Pre-merge gate:** pgTAP suite + extended Vitest e2e covers AC1–AC12 fully; CI exit code 0.
- **Post-merge gate (automation-feasible via Supabase MCP):**
  - AC13 — migration applies via `web-platform-release.yml#migrate` (automated, no operator action).
  - AC14 — verification SQL via `mcp__plugin_supabase_supabase__execute_sql` against prd project (automatable; no SSH, no dashboard).
  - AC15 — PostgREST schema cache reload probe via `service_role` client call to `list_workspace_member_actions` with retry/backoff (automatable; see `/soleur:postmerge` skill).

All post-merge steps are MCP/CLI-automatable per the IaC routing + automation-feasibility gates; no `### Post-merge (operator)` step requires browser, SSH, or dashboard interaction.

## Risks

Carry-forward from `spec.md` §`## Risks & Mitigations` (R1–R9, with R6/R7/R8/R9 added during spec drift reconciliation). Highest-priority risks for review-time scrutiny:

- **R1** (silent audit gap from future writer forgetting GUC) — single-user incident threshold; TR9 sentinel + TR13 Sentry mirror are the load-bearing mitigations. user-impact-reviewer at PR review verifies.
- **R8** (pg_cron silently blocked by WORM) — historical pattern; FR7 + AC9a are the closes.

## Sharp Edges (added during planning + plan-review)

- The two triggers must be created in the right order. WORM trigger MUST exist before any backfill INSERT (so day-0 writes are gated). AFTER trigger on `workspace_members` MUST exist before the backfill block (so a concurrent `workspace_members` INSERT during migration apply audits correctly). Phase 1.5 + Phase 2 + Phase 4 ordering is load-bearing — do not re-order.
- **Use `set_config(name, value, true)` not `SET LOCAL <key> = expr`.** Postgres's `SET LOCAL` only accepts literal values; `SET LOCAL workspace_audit.actor_user_id = COALESCE(...)` is a syntax error. The function form `set_config(..., is_local=true)` accepts runtime expressions and is the canonical pattern for dynamic GUC writes. `set_config` returns the prior value; ignore via `PERFORM`. (Plan-review P0-5.)
- **Trigger reads GUC via `NULLIF(current_setting(...), '')::uuid` wrapped in `EXCEPTION WHEN invalid_text_representation`** — empty-string returns from unset GUC, and a malformed string (future writer sets a non-UUID) raises `22P02` without the exception block. NULL is the correct empty-value; never fall back to `auth.uid()` (which under SECURITY DEFINER returns the definer postgres). Phase 2.2 names this explicitly. (Plan-review P0-4 + TR10a.)
- **FK target for `actor_user_id`/`target_user_id` is `public.users(id)`, not `auth.users(id)`** — matches sibling mig 053/058 convention. Mixed-schema FKs break the cascade ordering documented in `account-delete.ts:359-441`. (Plan-review P0-3.)
- **Cron observability surface is `cron.job_run_details` + `RAISE LOG`**, NOT `tenant_deploy_audit`. The latter's `event_type` CHECK constraint rejects new values and the table has no `payload` column. (Plan-review P0-2.)
- **`anonymise_workspace_members` (mig 058) is re-CREATEd in mig 062** to set `SET LOCAL session_replication_role='replica'` before its DELETE, so the new AFTER trigger does NOT fire during account-delete cascade. Without this, step `3.91`'s cascade DELETE creates net-new `target_user_id=<userId>` audit rows for a user requesting Art. 17 erasure — orphan PII if step `3.93` then fails. (Plan-review P1-2.)
- **Backfill MUST `LOCK TABLE public.workspace_members IN SHARE MODE`** before the INSERT (Plan-review P1-1). Without it, concurrent app-server INSERTs during the migration window are double-audited (once via AFTER trigger, once via backfill SELECT).
- **`RESET session_replication_role`** after each `SET LOCAL session_replication_role='replica'` block (mig 051/053b convention). Inside a SECURITY DEFINER function called from a larger transaction, the replica role persists to subsequent statements without RESET — silently bypassing triggers on adjacent tables the caller writes next.
- **Use `NEW.attestation_id` directly in the trigger**, not a `SELECT ... ORDER BY accepted_at DESC LIMIT 1` lookup. The membership row already carries the FK; lookup is racy (re-invited members) and breaks post-anonymise. Phase 2.2 names this. (Plan-review P1-4.)
- A plan whose `## User-Brand Impact` section is empty or contains only `TBD`/`TODO` will fail `/soleur:deepen-plan` Phase 4.6 and `/soleur:preflight` Check 6. This plan's User-Brand Impact is populated (carry-forward from brainstorm); do not remove on edit.
- Per `hr-no-dashboard-eyeball-pull-data-yourself`: post-merge verification (AC13, AC14, AC15) uses Supabase MCP server (`mcp__plugin_supabase_supabase__execute_sql`), not Supabase Studio. Anyone amending this plan to add "operator checks Studio" violates the rule.
- Per `hr-observability-as-plan-quality-gate` + `hr-observability-layer-citation`: the `## Observability` section above cites layer for every signal. Do not collapse it to free-form prose.

## References

- Spec: `knowledge-base/project/specs/feat-workspace-member-actions-audit-4231/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md`
- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md`
- Pure-reject WORM precedent: `apps/web-platform/supabase/migrations/037_audit_byok_use.sql` (`audit_byok_use_no_mutate`) + `051_action_class_widening_and_action_sends.sql` (`action_sends_no_mutate` + `RESET session_replication_role` convention) + `053_template_authorizations.sql` (two-bypass-shape combo). (Plan v1 misattributed to mig 048; corrected at plan-review 2026-05-22.)
- Reader RPC + RLS-zero precedent: `apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql`
- Membership RPC precedent: `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql` (lines 167-330 — `invite_workspace_member`, `remove_workspace_member`)
- DSAR cascade insertion: `apps/web-platform/server/account-delete.ts:60-85`
- Issue: #4231; Parent: #4229 (CLOSED via #4225); Draft PR: #4287
