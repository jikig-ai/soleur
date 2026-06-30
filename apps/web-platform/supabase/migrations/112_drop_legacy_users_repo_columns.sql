-- 112_drop_legacy_users_repo_columns.sql
-- feat-adr-044 PR-2b (#5437) — FINAL, IRREVERSIBLE step of the ADR-044 arc.
-- Drops the three dead repo-connection columns + the dead partial-UNIQUE index
-- from public.users. ADR-044 relocated repo-connection state users.* ->
-- workspaces.*; PR-2a (mig 110 + #5466/#5481/#5482/#5491) relocated every
-- connect-time WRITE and the last users.* repo READ. These columns are now dead.
--
-- DROP SET (exactly three columns + one index, all on public.users):
--   * users.github_installation_id (bigint, mig 011)
--   * users.repo_url               (text,   mig 011)
--   * users.workspace_path         (text NOT NULL DEFAULT '', mig 001)
--   * index users_github_installation_id_unique_idx (partial-UNIQUE, mig 052)
-- DOES NOT touch public.workspaces (the cutover TARGET) or
-- users.{role,email,github_username,workspace_status,tc_accepted_at,health_snapshot}.
-- repo_status / repo_last_synced_at / repo_provider are NOT dropped (they live on
-- workspaces; the users versions are not in PR-2b's named set).
--
-- ⚠️ IRREVERSIBLE — column DATA is NOT recoverable. The companion .down.sql is a
--    SCHEMA-ONLY rollback: it re-creates the three columns + the index, but the
--    dropped values (installation grants, repo URLs, workspace paths) are gone.
--    This is data-safe because:
--      (1) PR-2a relocated all writes — users.* is already frozen/stale and the
--          canonical copy lives on workspaces.*.
--      (2) Pre-decommission DRIFT GATE verified COUNT=0 against PROD on 2026-06-18
--          (users JOIN workspaces ON w.id=u.id; repo_url + github_installation_id
--          IS DISTINCT FROM = 0) — nothing unique is destroyed.
--      (3) READER SWEEP (multi-line + dual-shape .eq) on origin/main = 0 live
--          users.* readers of the three columns (2026-06-18).
--
-- The dropped index's cross-tenant structural guarantee (one founder per
-- installation) is permanently REPLACED at runtime by the
-- resolveSoloFounderForInstallation `{found|none|ambiguous|db-error}` resolver
-- (>1 fail-closed, server/resolve-founder-for-installation.ts) + the
-- github_webhook_founder_ambiguous Sentry paging rule
-- (apps/web-platform/infra/sentry/issue-alerts.tf:576). ADR-044 Amendment
-- 2026-06-17b (R7/R8). The drop does NOT reintroduce the cross-tenant hazard.
--
-- LAWFUL_BASIS (GDPR Art. 5(1)(e) storage-limitation / data-minimisation):
--   dropping dead credential + path columns whose data is relocated and now
--   stale is data-minimisation-positive. No new processing. The Art-17 cascade
--   (mig 081) nulls the relocated workspaces.github_installation_id on erasure —
--   unaffected.
--
-- Supabase wraps each migration file in ONE transaction (run-migrations.sh
-- --single-transaction, with the _schema_migrations tracking row); no explicit
-- BEGIN/COMMIT and no CONCURRENTLY (mirror mig 110).

-- Re-define handle_new_user WITHOUT the users.workspace_path write (dropped below); the path is derived now (ADR-044 PR-2b). Body otherwise verbatim from mig 091.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  -- 1. Insert public.users row (original 001 behavior).
  INSERT INTO public.users (id, email)
  VALUES (
    NEW.id,
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;

  -- 2. Insert organization (default-named) for this user IF they don't
  -- already have the canary owner row. Idempotent via the same
  -- discriminator as the 053 backfill DO block.
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members m
    WHERE m.user_id = NEW.id AND m.workspace_id = NEW.id AND m.role = 'owner'
  ) THEN
    INSERT INTO public.organizations (id, name, domain, owner_user_id)
    VALUES (gen_random_uuid(), 'My Workspace', NULL, NEW.id)
    RETURNING id INTO v_org_id;

    INSERT INTO public.workspaces (id, organization_id, name)
    VALUES (NEW.id, v_org_id, 'My Workspace')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
    VALUES (NEW.id, NEW.id, 'owner', NULL)
    ON CONFLICT (workspace_id, user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- handle_new_user is a trigger function (fires AFTER INSERT on auth.users)
-- and is not invoked via direct CALL. The REVOKE is defensive (satisfies
-- migration-rpc-grants lint + closes the direct-EXECUTE surface). Triggers
-- fire under the owner's identity regardless of EXECUTE grant, so this
-- REVOKE does NOT break signup.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Auth signup hook. Creates public.users row + default-named organization '
  '+ workspace (id = users.id per ADR-038 N2) + workspace_members(role=owner). '
  'Idempotent via canary owner-row discriminator + per-table ON CONFLICT DO '
  'NOTHING. SECURITY DEFINER so RLS does not block during the auth.users '
  'INSERT trigger. Default name set per feat-one-shot-workspace-untitled-name '
  '(was NULL in mig 053).';

DROP INDEX IF EXISTS public.users_github_installation_id_unique_idx;

ALTER TABLE public.users
  DROP COLUMN IF EXISTS github_installation_id,
  DROP COLUMN IF EXISTS repo_url,
  DROP COLUMN IF EXISTS workspace_path;
