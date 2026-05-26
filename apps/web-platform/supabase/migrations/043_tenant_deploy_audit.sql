-- 043_tenant_deploy_audit.sql
-- feat-soleur-managed-deploy-substrate-3723 Phase 1 (plan rev-2).
-- ADR: knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md
-- LIA: knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md
-- RoPA: knowledge-base/legal/article-30-register.md (Processing Activity 10)
--
-- Tables:
--   public.tenant_deploy_audit — admin-only WORM meta-audit log for the
--                                multi-tenant deploy substrate's
--                                orchestration plane. Records "Soleur
--                                agent triggered deploy for founder X
--                                on tenant repo Y at time T" events.
--
-- RPCs (all SECURITY DEFINER, search_path = public, pg_temp,
-- public.-qualified relations, named-role REVOKE):
--   public.write_tenant_deploy_audit(...)
--   public.anonymise_tenant_deploy_audit(p_founder_id uuid)
--
-- Schedules (pg_cron):
--   tenant-deploy-audit-retention — daily 04:00 UTC, 12-mo DELETE
--                                   per legal-compliance SHOULD #2.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp (public FIRST).
-- Precedent: 041_dsar_export_jobs.sql:184,239,280,320 (compliant).
--
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT to
-- service_role on each RPC. (Supabase's ALTER DEFAULT PRIVILEGES grants
-- EXECUTE to anon/authenticated/service_role on every new fn; REVOKE
-- FROM PUBLIC alone does NOT undo the explicit role grants.)
--
-- Per cq-supabase-migration-no-concurrently: no CREATE INDEX CONCURRENTLY
-- (Supabase wraps each migration in a transaction).
--
-- Per spec-flow P0 #1: no `provisioning_step_*` enum values without
-- writer code. Three v1 event_type values only.
--
-- Per Kieran P1-4: oidc_jti is text (RFC 7519 §4.1.7 — case-sensitive
-- string), not uuid. GitHub's OIDC currently uses UUID-shape jti but
-- the spec does not guarantee it.
--
-- Per spec-flow P0 #8 + plan §"ON DELETE RESTRICT": founder_id FK uses
-- ON DELETE RESTRICT. The Art. 17 cascade in tenant-offboarding runbook
-- calls anonymise_tenant_deploy_audit(p_founder_id) BEFORE
-- auth.admin.deleteUser(); SET NULL would nullify before the anonymise
-- RPC can run, breaking the audit row's discriminator semantics.

-- ============================================================================
-- tenant_deploy_audit — admin-only WORM meta-audit log.
--
-- Stores per-event attribution of orchestration-plane dispatch events.
-- RLS with zero policies (service_role-only via the writer RPC).
-- WORM gated by GUC + service_role bypass for the Art. 17 anonymise flow.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tenant_deploy_audit (
  id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  founder_id        uuid         REFERENCES auth.users(id) ON DELETE RESTRICT,
  event_type        text         NOT NULL
    CHECK (event_type IN ('workflow_dispatch_triggered','workflow_run_completed','workflow_run_failed')),
  -- target_repo: GitHub `owner/repo` shape. Owner: 1-39 chars, must
  -- start AND end with alnum (rejects leading/trailing `-` and any `.`).
  -- Repo: 1-100 chars, must start with alnum or `_` (rejects `..`, `.`,
  -- and leading `-`). Combined: ≤140 chars, exactly one `/`. Rejects
  -- path-traversal shapes (`..`, `./.`, `-rf`) and any value lacking the
  -- slash separator. Defense-in-depth against log-injection via
  -- downstream path-aware viewers; tightens from the original
  -- `[A-Za-z0-9_./-]{1,255}` permissive charset.
  target_repo       text         NOT NULL
    CHECK (target_repo ~ '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$'),
  -- target_workflow: must start with alnum or `_`, alnum/`._-` charset,
  -- end in `.yml` or `.yaml`. Matches GitHub Actions workflow naming.
  target_workflow   text         NOT NULL
    CHECK (target_workflow ~ '^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}\.ya?ml$'),
  gh_run_id         bigint,
  oidc_jti          text
    CHECK (oidc_jti IS NULL OR length(oidc_jti) BETWEEN 1 AND 255),
  trigger_outcome   text         NOT NULL
    CHECK (trigger_outcome IN ('queued','succeeded','failed','timeout')),
  event_at          timestamptz  NOT NULL DEFAULT now(),
  -- RETENTION: 12 months via tenant-deploy-audit-retention pg_cron (Art. 5(1)(e))
  retention_until   timestamptz  NOT NULL DEFAULT (now() + interval '12 months')
);

ALTER TABLE public.tenant_deploy_audit ENABLE ROW LEVEL SECURITY;
-- Zero policies: service-role-only via write_tenant_deploy_audit RPC.

CREATE INDEX tenant_deploy_audit_founder_event_idx
  ON public.tenant_deploy_audit (founder_id, event_at DESC);

COMMENT ON TABLE public.tenant_deploy_audit IS
  'Orchestration-plane meta-audit log for the multi-tenant deploy '
  'substrate (ADR-030). One row per workflow_dispatch event triggered '
  'on a tenant repo by a Soleur agent. service-role-only via WORM '
  'writer RPC. RLS zero-policies. Art. 17 cascade anonymises '
  'founder_id (UPDATE, not DELETE) before auth.users deletion. '
  '12-mo retention via tenant-deploy-audit-retention pg_cron. '
  'feat-soleur-managed-deploy-substrate-3723.';

-- ============================================================================
-- WORM trigger: tenant_deploy_audit is append-only EXCEPT during the
-- Art. 17 anonymisation flow.
--
-- Two bypasses defined; UPDATE attempts NEVER bypass.
--
-- Bypass 1 (Art. 17 anonymise) requires ALL of:
--   (a) GUC `app.tenant_deploy_anonymise_in_progress` is set (any
--       non-empty value)
--   (b) `current_user = 'service_role'`
--   (c) The SET-site for the GUC appears EXACTLY ONCE in the codebase,
--       in the body of anonymise_tenant_deploy_audit. (Same enforcement
--       pattern as ADR-028's dsar-worm-guc-sites.test.ts; equivalent
--       file-parse test for this GUC can land alongside the writer
--       module at N=2 when the orchestration TS module is extracted —
--       deferred per plan revision-2 scope cut.)
--
-- Bypass 2 (Art. 5(1)(e) retention sweep) requires ALL of:
--   (a) TG_OP = 'DELETE' (UPDATEs never bypass)
--   (b) OLD.retention_until IS NOT NULL AND OLD.retention_until < now()
-- This bypass is role-independent because pg_cron's scheduling role is
-- `postgres` (not `service_role`) and the retention-sweep DELETE must
-- still succeed. The row-state predicate is the authorization basis,
-- which matches Art. 5(1)(e) (the regulation makes retention the legal
-- basis for deletion, not access role).
--
-- Trigger function is INVOKER (not DEFINER) per ADR-028's data-integrity
-- learning: a SECURITY DEFINER trigger evaluates `current_user` to the
-- function OWNER (typically `postgres` in Supabase migrations), not the
-- role that initiated the triggering UPDATE. With DEFINER, the
-- `current_user = 'service_role'` gate would ALWAYS fail and the
-- legitimate Art. 17 anonymise RPC would be rejected — Art. 17
-- violation. Triggers execute inside the calling transaction with the
-- calling session's role context, which is exactly what we want here.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.tenant_deploy_audit_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_anonymise_flag text;
BEGIN
  -- current_setting(name, missing_ok=true) returns '' (not NULL) when unset.
  v_anonymise_flag := current_setting('app.tenant_deploy_anonymise_in_progress', true);

  IF v_anonymise_flag <> '' AND current_user = 'service_role' THEN
    -- Bypass 1: Art. 17 anonymisation flow. The single SET site is in
    -- anonymise_tenant_deploy_audit's body below.
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Bypass 2: Retention sweep. The pg_cron daily DELETE (scheduled below)
  -- runs as the migration owner role (typically `postgres`), NOT as
  -- `service_role`, so it cannot use Bypass 1's role gate. Instead the
  -- bypass condition is mechanically tight on the row's own state: only
  -- DELETE, only rows whose retention_until is past now(). UPDATE attempts
  -- remain rejected unconditionally (the WORM property is preserved for
  -- record integrity), and DELETEs of non-expired rows remain rejected
  -- (the retention window is enforced). The clause is independent of the
  -- caller's role, so any operator with DML access (service_role,
  -- superuser, or pg_cron's scheduling role) can reap expired rows — by
  -- design, since Art. 5(1)(e) makes retention the authorization basis,
  -- not role.
  IF TG_OP = 'DELETE'
     AND OLD.retention_until IS NOT NULL
     AND OLD.retention_until < now() THEN
    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'tenant_deploy_audit is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.tenant_deploy_audit_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER tenant_deploy_audit_no_update
  BEFORE UPDATE ON public.tenant_deploy_audit
  FOR EACH ROW
  EXECUTE FUNCTION public.tenant_deploy_audit_no_mutate();

CREATE TRIGGER tenant_deploy_audit_no_delete
  BEFORE DELETE ON public.tenant_deploy_audit
  FOR EACH ROW
  EXECUTE FUNCTION public.tenant_deploy_audit_no_mutate();

COMMENT ON FUNCTION public.tenant_deploy_audit_no_mutate() IS
  'WORM gate for tenant_deploy_audit. Two bypasses: (1) Art. 17 '
  'anonymisation (GUC + service_role) — the SET site is in '
  'anonymise_tenant_deploy_audit''s body. (2) Retention sweep '
  '(DELETE-only, retention_until < now()) — gates by row state not '
  'caller role so pg_cron''s scheduling-role DELETE is permitted while '
  'WORM integrity is preserved for non-expired rows and all UPDATEs.';

-- ============================================================================
-- write_tenant_deploy_audit — append-only audit row writer.
--
-- service_role-only. Called by the orchestration-plane code path that
-- dispatches workflow runs on tenant repos (deferred to N=2 per plan
-- revision-2 scope cut; v1 calls this RPC manually from a psql session
-- as part of the Phase 2 runbook smoke-test).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.write_tenant_deploy_audit(
  p_founder_id       uuid,
  p_event_type       text,
  p_target_repo      text,
  p_target_workflow  text,
  p_gh_run_id        bigint,
  p_oidc_jti         text,
  p_trigger_outcome  text
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  INSERT INTO public.tenant_deploy_audit(
    founder_id, event_type, target_repo, target_workflow,
    gh_run_id, oidc_jti, trigger_outcome
  )
  VALUES (
    p_founder_id, p_event_type, p_target_repo, p_target_workflow,
    p_gh_run_id, p_oidc_jti, p_trigger_outcome
  );
$$;

REVOKE ALL ON FUNCTION public.write_tenant_deploy_audit(uuid, text, text, text, bigint, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_tenant_deploy_audit(uuid, text, text, text, bigint, text, text)
  TO service_role;

COMMENT ON FUNCTION public.write_tenant_deploy_audit(uuid, text, text, text, bigint, text, text) IS
  'Append-only writer for tenant_deploy_audit. service_role only. Input '
  'validation via the table''s CHECK constraints (target_repo + '
  'target_workflow charset/length; event_type + trigger_outcome enums; '
  'oidc_jti length). feat-soleur-managed-deploy-substrate-3723.';

-- ============================================================================
-- anonymise_tenant_deploy_audit — Art. 17 cascade hook.
--
-- Called from the tenant-offboarding runbook BEFORE auth.admin.deleteUser()
-- per plan §"ON DELETE RESTRICT" ordering. Idempotent: re-running on
-- already-anonymised rows is a no-op (founder_id is simply re-set to NULL).
--
-- Per legal-compliance BLOCKING #3: this RPC UPDATEs founder_id = NULL
-- (preserving row count and audit-trail integrity) — does NOT DELETE.
-- Plan AC verifies SELECT count(*) before and after returns the same
-- value, with founder_id NULL for the anonymised rows.
--
-- THE SINGLE SET-SITE for app.tenant_deploy_anonymise_in_progress lives
-- here. Equivalent file-parse lint pattern as ADR-028's
-- dsar-worm-guc-sites.test.ts can land alongside the orchestration TS
-- module at N=2 (deferred per plan revision-2 scope cut). The runtime
-- gate (role + GUC) is the cryptographic component.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.anonymise_tenant_deploy_audit(p_founder_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- WORM-bypass: SET LOCAL scopes to the current transaction; reverts
  -- at COMMIT/ROLLBACK. THE SINGLE SET-SITE for this GUC.
  SET LOCAL app.tenant_deploy_anonymise_in_progress = 'on';

  UPDATE public.tenant_deploy_audit
     SET founder_id = NULL
   WHERE founder_id = p_founder_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_tenant_deploy_audit(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_tenant_deploy_audit(uuid) TO service_role;

COMMENT ON FUNCTION public.anonymise_tenant_deploy_audit(uuid) IS
  'Art. 17 cascade hook: anonymises founder_id on tenant_deploy_audit '
  'rows for the given founder. Idempotent. Called from the '
  'tenant-offboarding runbook BEFORE auth.admin.deleteUser() per '
  'ON DELETE RESTRICT FK ordering. UPDATEs founder_id = NULL (does NOT '
  'DELETE) to preserve audit-trail row count. Holds the ONLY SET-site '
  'for app.tenant_deploy_anonymise_in_progress.';

-- ============================================================================
-- Retention sweep: daily 04:00 UTC DELETE of tenant_deploy_audit rows
-- whose retention_until has passed (Art. 5(1)(e) storage limitation).
-- 12-month retention envelope per legal-compliance SHOULD #2.
-- ============================================================================

DO $$
BEGIN
  PERFORM cron.schedule(
    'tenant-deploy-audit-retention',
    '0 4 * * *',
    $cron$
      DELETE FROM public.tenant_deploy_audit
       WHERE retention_until < now();
    $cron$
  );
EXCEPTION WHEN duplicate_object THEN
  -- Schedule already exists from a prior apply; safe to ignore.
  NULL;
END $$;
