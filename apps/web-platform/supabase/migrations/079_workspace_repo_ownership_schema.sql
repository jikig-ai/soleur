-- 079_workspace_repo_ownership_schema.sql
-- feat-workspace-repo-ownership (#4558, PR #4559) — relocate GitHub
-- repo-connection state from public.users to public.workspaces so a
-- joined-workspace member can sync THAT workspace's repo (#4543).
-- ADR-044 (amends ADR-038). Additive + reversible: no existing reader
-- changes behavior; the new current_workspace_id claim is injected but
-- unread until the 081 read-cutover.
--
-- LAWFUL_BASIS: Art. 6(1)(b) contract — repo connection is constitutive
-- of the workspace service; co-member access under Art. 6(1)(f) per
-- amended PA-17 (legal docs updated in the same PR).
--
-- DEPENDENCY: migration 053 (workspaces, workspace_members,
-- is_workspace_member — search_path-pinned at 053:120) + migration 060
-- (user_session_state, runtime_jwt_mint_hook, set_current_organization_id)
-- must have applied.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: all SECURITY
-- DEFINER fns pin SET search_path = public, pg_temp.
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public:
-- 4-role REVOKE (PUBLIC, anon, authenticated, service_role) on the new
-- RPCs (the 060 set_current_organization_id used a 3-role REVOKE; the
-- 4-role form closes the residual default EXECUTE grant).
-- cq-supabase-migration-no-concurrently: plain CREATE INDEX — Supabase
-- wraps each migration file in a transaction (SQLSTATE 25001).

-- =====================================================================
-- 1. Repo-connection columns on public.workspaces (mirror 011 exactly)
-- =====================================================================

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS repo_url text,
  ADD COLUMN IF NOT EXISTS repo_provider text DEFAULT 'github',
  ADD COLUMN IF NOT EXISTS github_installation_id bigint,
  ADD COLUMN IF NOT EXISTS repo_status text DEFAULT 'not_connected'
    CHECK (repo_status IN ('not_connected', 'cloning', 'ready', 'error')),
  ADD COLUMN IF NOT EXISTS repo_last_synced_at timestamptz;

-- Non-unique indexes supporting the webhook fan-out lookup. NO global
-- UNIQUE on repo_url: two users may legitimately connect the same public
-- repo/fork to their own personal workspaces; a UNIQUE would throw 23505
-- at the second connect. Webhook determinism comes from the fan-out
-- reconcile over (installation_id, normalized repo_url) — not from
-- uniqueness (see migration 081 cutover + ADR-044).
CREATE INDEX IF NOT EXISTS workspaces_installation_repo_idx
  ON public.workspaces (github_installation_id, repo_url);
CREATE INDEX IF NOT EXISTS workspaces_repo_url_idx
  ON public.workspaces (repo_url);

-- =====================================================================
-- 2. Column-level credential protection (highest-severity deepen finding)
-- =====================================================================
--
-- workspaces_select_for_members (053:169) is ROW-level; Postgres RLS has
-- no column scoping, so any member could SELECT github_installation_id
-- (a GitHub App token grant) of their workspace.
--
-- NOTE on the correct shape (corrects the plan's literal
-- `REVOKE SELECT (github_installation_id)`): Supabase grants TABLE-level
-- SELECT to `authenticated` by default, and a column-level REVOKE is a
-- no-op while a table-level grant exists. The only way to deny one
-- column is to REVOKE the table-level SELECT and re-GRANT SELECT on the
-- explicit non-credential column list. RLS (workspaces_select_for_members)
-- still gates which ROWS are visible; this gates which COLUMNS.
-- The credential is then readable only via
-- resolve_workspace_installation_id (SECURITY DEFINER, below).
-- service_role keeps its default grant (trusted server context); the
-- definer RPC runs as the function owner regardless of these grants.

REVOKE SELECT ON public.workspaces FROM authenticated;
GRANT SELECT (id, organization_id, name, created_at,
              repo_url, repo_provider, repo_status, repo_last_synced_at)
  ON public.workspaces TO authenticated;

-- =====================================================================
-- 3. resolve_workspace_installation_id RPC (the ONLY credential reader)
-- =====================================================================
--
-- Membership-checked read of github_installation_id. Deny → RETURN NULL
-- (never raise — a non-member resolving an arbitrary workspace must look
-- identical to "no installation connected", not leak existence). This is
-- the single path that reads the credential; it keeps the column off the
-- authenticated grant.

CREATE OR REPLACE FUNCTION public.resolve_workspace_installation_id(p_workspace_id uuid)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_install bigint;
BEGIN
  -- is_workspace_member(NULL, …) and (…, NULL) both return FALSE, so a
  -- null arg or unauthenticated caller falls through to RETURN NULL.
  IF NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN
    RETURN NULL;
  END IF;

  SELECT github_installation_id INTO v_install
  FROM public.workspaces
  WHERE id = p_workspace_id;

  RETURN v_install;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_workspace_installation_id(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_workspace_installation_id(uuid) TO authenticated;

COMMENT ON FUNCTION public.resolve_workspace_installation_id(uuid) IS
  'Membership-checked read of workspaces.github_installation_id (a '
  'GitHub App token grant). Returns NULL for non-members (no raise — '
  'deny is indistinguishable from "not connected"). The ONLY path that '
  'reads the credential column, which is revoked from the authenticated '
  'table grant. ADR-044.';

-- =====================================================================
-- 4. current_workspace_id on user_session_state (col ADD before hook)
-- =====================================================================
--
-- The ALTER MUST precede the runtime_jwt_mint_hook CREATE OR REPLACE
-- below (the hook reads this column). FK ON DELETE SET NULL: a deleted
-- workspace nulls the claim; the resolver defaults a NULL claim to the
-- caller's solo workspace (081), never an unscoped sibling.

ALTER TABLE public.user_session_state
  ADD COLUMN IF NOT EXISTS current_workspace_id uuid NULL
    REFERENCES public.workspaces(id) ON DELETE SET NULL;

-- Backfill from each user's solo workspace (= users.id per ADR-038 N2).
-- Idempotent: re-runs touch 0 rows (WHERE current_workspace_id IS NULL).
DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.user_session_state s
     SET current_workspace_id = s.user_id
   WHERE s.current_workspace_id IS NULL
     AND EXISTS (
       SELECT 1 FROM public.workspaces w WHERE w.id = s.user_id
     );
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[079-backfill current_workspace_id] % rows', v_rc;
END $$;

-- =====================================================================
-- 5. Hook extension: inject current_workspace_id into JWT claims
-- =====================================================================
--
-- CREATE OR REPLACE runtime_jwt_mint_hook (single Supabase Auth hook
-- slot, migration 060). Preserves the org-injection block (060:131-135)
-- and the OTP precheck block (060:139-148) verbatim; adds a parallel
-- current_workspace_id injection sourced from the same user_session_state
-- read (combined into one SELECT). Omits the workspace claim when NULL so
-- the consumer reads `undefined` rather than explicit null.
-- No EXCEPTION WHEN OTHERS — security-critical mint fails loud.

CREATE OR REPLACE FUNCTION public.runtime_jwt_mint_hook(event jsonb)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id           uuid;
  v_claims            jsonb;
  v_auth_method       text;
  v_precheck          record;
  v_org_id            uuid;
  v_workspace_id      uuid;
  v_app_metadata      jsonb;
  v_ttl_sec           int := 600;
BEGIN
  v_user_id     := (event->>'user_id')::uuid;
  v_claims      := event->'claims';
  v_auth_method := event->>'authentication_method';

  -- Single read of the per-user session state (org + workspace).
  SELECT current_organization_id, current_workspace_id
    INTO v_org_id, v_workspace_id
  FROM public.user_session_state
  WHERE user_id = v_user_id;

  -- Inject org_id into app_metadata if present (060:131-135 — preserved).
  IF v_org_id IS NOT NULL THEN
    v_app_metadata := COALESCE(v_claims->'app_metadata', '{}'::jsonb);
    v_app_metadata := jsonb_set(v_app_metadata, '{current_organization_id}', to_jsonb(v_org_id::text));
    v_claims := jsonb_set(v_claims, '{app_metadata}', v_app_metadata);
  END IF;

  -- Inject workspace_id into app_metadata if present (NEW — mirrors the
  -- org block; re-reads app_metadata so it composes additively with the
  -- org_id write above).
  IF v_workspace_id IS NOT NULL THEN
    v_app_metadata := COALESCE(v_claims->'app_metadata', '{}'::jsonb);
    v_app_metadata := jsonb_set(v_app_metadata, '{current_workspace_id}', to_jsonb(v_workspace_id::text));
    v_claims := jsonb_set(v_claims, '{app_metadata}', v_app_metadata);
  END IF;

  -- OTP path: runtime-mint precheck + claim injection (060:139-148 —
  -- preserved verbatim).
  IF v_auth_method = 'otp' THEN
    SELECT jti, exp_epoch, iat_epoch INTO v_precheck
    FROM public.precheck_jwt_mint(v_user_id, v_ttl_sec);

    v_claims := jsonb_set(v_claims, '{jti}',  to_jsonb(v_precheck.jti::text));
    v_claims := jsonb_set(v_claims, '{exp}',  to_jsonb(v_precheck.exp_epoch));
    v_claims := jsonb_set(v_claims, '{iat}',  to_jsonb(v_precheck.iat_epoch));
    v_claims := jsonb_set(v_claims, '{aud}',  '"soleur-runtime"');
    v_claims := jsonb_set(v_claims, '{role}', '"authenticated"');
  END IF;

  RETURN jsonb_build_object('claims', v_claims);
END;
$$;

REVOKE ALL ON FUNCTION public.runtime_jwt_mint_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.runtime_jwt_mint_hook(jsonb) TO supabase_auth_admin;

COMMENT ON FUNCTION public.runtime_jwt_mint_hook(jsonb) IS
  'Custom Access Token Hook. (1) Injects app_metadata.current_organization_id '
  'AND app_metadata.current_workspace_id from user_session_state for ALL '
  'auth paths. (2) For OTP path, additionally runs precheck_jwt_mint + '
  'jti/exp/iat/aud/role injection per migration 047. Single Supabase Auth '
  'hook slot dual-purposes both. ADR-038 + ADR-044.';

-- =====================================================================
-- 6. set_current_workspace_id RPC (membership-checked claim writer)
-- =====================================================================
--
-- Match the 060 set_current_organization_id precedent fully. Sets BOTH
-- current_workspace_id and current_organization_id (derived from the
-- workspace's organization_id) so the two claims never diverge. FK-race
-- guard: if the workspace was deleted between the membership-check and
-- the org lookup, raise rather than silently writing org_id = NULL.

CREATE OR REPLACE FUNCTION public.set_current_workspace_id(p_workspace_id uuid)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_org_id   uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'p_workspace_id is required'
      USING ERRCODE = '22004';
  END IF;

  IF NOT public.is_workspace_member(p_workspace_id, v_user_id) THEN
    RAISE EXCEPTION 'caller is not a member of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  -- FK-race guard: a concurrent workspace delete (ON DELETE RESTRICT on
  -- workspace_members would normally block, but the membership row could
  -- have been removed first) must not write a NULL org claim.
  SELECT organization_id INTO v_org_id
  FROM public.workspaces
  WHERE id = p_workspace_id;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'workspace % has no organization (deleted mid-call?)', p_workspace_id
      USING ERRCODE = '23503';
  END IF;

  INSERT INTO public.user_session_state (user_id, current_workspace_id, current_organization_id, updated_at)
       VALUES (v_user_id, p_workspace_id, v_org_id, now())
  ON CONFLICT (user_id) DO UPDATE
        SET current_workspace_id    = EXCLUDED.current_workspace_id,
            current_organization_id = EXCLUDED.current_organization_id,
            updated_at              = EXCLUDED.updated_at;
END;
$$;

REVOKE ALL ON FUNCTION public.set_current_workspace_id(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_current_workspace_id(uuid) TO authenticated;

COMMENT ON FUNCTION public.set_current_workspace_id(uuid) IS
  'Sets the calling user''s current_workspace_id (workspace-switcher UI), '
  'validating workspace membership and setting current_organization_id '
  'from the workspace''s organization in the same upsert. Caller '
  'refreshes their session to pick up the new JWT claims. ADR-044.';
