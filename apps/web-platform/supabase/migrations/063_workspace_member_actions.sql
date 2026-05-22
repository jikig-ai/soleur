-- 063_workspace_member_actions.sql
-- feat-workspace-member-actions-audit (#4231) — Append-only audit log for
-- workspace membership mutations. Blocks the TEAM_WORKSPACE_INVITE_ENABLED
-- flag-flip for any non-jikigai org.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(c) legal obligation (Art. 5(2)
-- accountability — controllers must demonstrate lawful processing) +
-- Art. 6(1)(f) legitimate interest (operational integrity, forensic
-- reconstruction during member-dispute / regulator-inquiry scenarios).
-- LIA balancing test: 7y retention bounded by SOX evidentiary horizon;
-- data is internal-use-only (never product analytics / sales / ML
-- training / feature decisions); subjects retain Art. 15/17/20 rights
-- via DSAR cascade; the audit trail itself protects subjects from
-- controller misconduct. Article 30 register entry: PA-20.
--
-- RETENTION: 7 years. pg_cron 'workspace-member-actions-retention'
-- runs daily 04:00 UTC and invokes purge_workspace_member_actions()
-- (SECURITY DEFINER wrapper with session_replication_role='replica'
-- bypass). Direct DELETE from cron would be silently blocked by the
-- WORM trigger — see learning
-- 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md.
--
-- WORM contract: BEFORE UPDATE/DELETE trigger PURE-REJECTs all
-- origin-role mutations with SQLSTATE P0001. Bypass via SET LOCAL
-- session_replication_role = 'replica' in the canonical wrapper RPCs
-- (purge, anonymise, backfill). Pattern source: mig 037
-- audit_byok_use_no_mutate + mig 051 action_sends_no_mutate; learning
-- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md.
--
-- Trigger-driven writer: AFTER INSERT/UPDATE/DELETE on
-- public.workspace_members captures actor via session GUC
-- 'workspace_audit.actor_user_id' set by the v1 writer RPCs
-- (invite_workspace_member, remove_workspace_member). NEVER falls back
-- to auth.uid() inside the trigger — under SECURITY DEFINER auth.uid()
-- returns the definer (postgres). NULL is the correct empty actor.
-- See plan §2.2 and learning
-- 2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER function pins SET search_path = public, pg_temp (public first).
--
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO CREATE
-- INDEX CONCURRENTLY (Supabase wraps each migration in a transaction).

-- =====================================================================
-- 1. workspace_member_actions table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.workspace_member_actions (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    uuid         NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  -- PII columns — NULL after Art. 17 anonymise. FKs target public.users(id)
  -- (NOT auth.users(id)) matching sibling mig 053:51,83 + mig 058:45,46
  -- convention; mixed-schema FKs would break the account-delete cascade.
  actor_user_id   uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  target_user_id  uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  action_type     text         NOT NULL CHECK (action_type IN ('added', 'removed', 'role_changed')),
  old_role        text         NULL,
  new_role        text         NULL,
  attestation_id  uuid         NULL REFERENCES public.workspace_member_attestations(id) ON DELETE RESTRICT,
  created_at      timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.workspace_member_actions IS
  'Append-only audit log for workspace membership mutations (add, remove, role_change). '
  'WORM (write-once-read-many). PA-20 of the Article 30 register. Reads route through '
  'list_workspace_member_actions SECURITY DEFINER RPC (owner-only). Writes are trigger-'
  'driven from public.workspace_members; admin-tool / backfill paths bypass the WORM '
  'trigger via SET LOCAL session_replication_role=''replica''. #4231.';

ALTER TABLE public.workspace_member_actions ENABLE ROW LEVEL SECURITY;
-- Zero policies — all reads route through list_workspace_member_actions
-- SECURITY DEFINER RPC. Trigger-driven writes from workspace_members
-- bypass RLS via the SECURITY DEFINER trigger function.

-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public:
-- Supabase default-privileges auto-grant new tables to anon/authenticated/
-- service_role. REVOKE FROM PUBLIC alone is insufficient — explicit
-- named-role REVOKE is required.
REVOKE INSERT, UPDATE, DELETE, SELECT ON TABLE public.workspace_member_actions
  FROM PUBLIC, anon, authenticated, service_role;

-- =====================================================================
-- 2. Indexes (no CONCURRENTLY — Supabase wraps each migration in TX)
-- =====================================================================

-- Owner-list query path: list_workspace_member_actions filters by
-- workspace_id and orders by created_at DESC.
CREATE INDEX IF NOT EXISTS workspace_member_actions_workspace_created_idx
  ON public.workspace_member_actions (workspace_id, created_at DESC);

-- Art. 17 anonymise sweep: anonymise_workspace_member_actions filters
-- by target_user_id (and actor_user_id). Partial index excludes already-
-- NULLed rows (idempotent re-runs match zero rows).
CREATE INDEX IF NOT EXISTS workspace_member_actions_target_idx
  ON public.workspace_member_actions (target_user_id)
  WHERE target_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS workspace_member_actions_actor_idx
  ON public.workspace_member_actions (actor_user_id)
  WHERE actor_user_id IS NOT NULL;

-- =====================================================================
-- 3. WORM trigger function (pure-reject)
-- =====================================================================
--
-- BEFORE UPDATE/DELETE — pure raise. Lifts mig 037
-- audit_byok_use_no_mutate body verbatim. Bypass is Postgres-canonical:
-- triggers default to ENABLE ORIGIN, so SET LOCAL session_replication_
-- role='replica' inside a SECURITY DEFINER wrapper (purge, anonymise,
-- backfill) skips the trigger entirely. The trigger body does NOT need
-- a role-check branch (which fails under PostgREST routing per learning
-- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-
-- routing.md).

CREATE OR REPLACE FUNCTION public.workspace_member_actions_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'workspace_member_actions is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.workspace_member_actions_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS workspace_member_actions_no_update ON public.workspace_member_actions;
CREATE TRIGGER workspace_member_actions_no_update
  BEFORE UPDATE ON public.workspace_member_actions
  FOR EACH ROW
  EXECUTE FUNCTION public.workspace_member_actions_no_mutate();

DROP TRIGGER IF EXISTS workspace_member_actions_no_delete ON public.workspace_member_actions;
CREATE TRIGGER workspace_member_actions_no_delete
  BEFORE DELETE ON public.workspace_member_actions
  FOR EACH ROW
  EXECUTE FUNCTION public.workspace_member_actions_no_mutate();

-- =====================================================================
-- 4. AFTER trigger on workspace_members — the impossible-to-forget writer
-- =====================================================================
--
-- SECURITY DEFINER so the function can INSERT into workspace_member_
-- actions despite authenticated having no INSERT grant. Reads actor
-- via 'workspace_audit.actor_user_id' GUC set by v1 writer RPCs
-- (invite_workspace_member, remove_workspace_member). NULL when the
-- mutation is admin-tool / migration-time backfill (intentional).
--
-- TR10a: trigger MUST NOT fall back to auth.uid() — under SECURITY
-- DEFINER context, auth.uid() returns the definer (postgres), not the
-- calling user. NULL is the correct empty value.
--
-- TR13: when v_actor IS NULL AND session_user = 'authenticated', emit a
-- structured RAISE LOG row (audit_orphan_actor) — production-NULL from
-- authenticated role signals a future RPC author forgot SET LOCAL.
-- PII-scrubbed: workspace_id + TG_OP only; never target_user_id.

CREATE OR REPLACE FUNCTION public.workspace_members_audit() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor       uuid;
  v_action      text;
  v_target      uuid;
  v_old_role    text;
  v_new_role    text;
  v_attestation uuid;
BEGIN
  -- Parse the actor GUC; tolerate unset (empty string) and malformed.
  -- NULLIF returns NULL for the unset/empty case; the EXCEPTION block
  -- catches 22P02 invalid_text_representation for a future writer that
  -- sets the GUC to a non-UUID. Never fall back to auth.uid() (TR10a).
  BEGIN
    v_actor := NULLIF(current_setting('workspace_audit.actor_user_id', true), '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_actor := NULL;
  END;

  IF TG_OP = 'INSERT' THEN
    v_action      := 'added';
    v_target      := NEW.user_id;
    v_new_role    := NEW.role;
    v_attestation := NEW.attestation_id;
  ELSIF TG_OP = 'DELETE' THEN
    v_action   := 'removed';
    v_target   := OLD.user_id;
    v_old_role := OLD.role;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.role IS NOT DISTINCT FROM NEW.role THEN
      RETURN NULL;  -- no-op UPDATE (same role); do not audit
    END IF;
    v_action      := 'role_changed';
    v_target      := NEW.user_id;
    v_old_role    := OLD.role;
    v_new_role    := NEW.role;
    v_attestation := NEW.attestation_id;  -- preserve consent attribution on role change
  END IF;

  INSERT INTO public.workspace_member_actions
    (workspace_id, actor_user_id, target_user_id, action_type, old_role, new_role, attestation_id)
  VALUES
    (COALESCE(NEW.workspace_id, OLD.workspace_id), v_actor, v_target, v_action, v_old_role, v_new_role, v_attestation);

  -- TR13: orphan-actor signal. session_user (not current_user) for the
  -- caller's role — under SECURITY DEFINER current_user is the definer.
  IF v_actor IS NULL AND session_user = 'authenticated' THEN
    RAISE LOG 'audit_orphan_actor workspace_id=% action=%',
      COALESCE(NEW.workspace_id, OLD.workspace_id), TG_OP;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.workspace_members_audit()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS workspace_members_audit_trigger ON public.workspace_members;
CREATE TRIGGER workspace_members_audit_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.workspace_members
  FOR EACH ROW
  EXECUTE FUNCTION public.workspace_members_audit();

-- =====================================================================
-- 5. Reader RPC — list_workspace_member_actions (owner-only)
-- =====================================================================
--
-- Cursor-paginated owner read. Empty return on non-owner / nonexistent
-- workspace (never reveal table existence). Owner-check joins
-- organizations.owner_user_id via workspaces.organization_id (mig 053).

CREATE OR REPLACE FUNCTION public.list_workspace_member_actions(
  p_workspace_id uuid,
  p_limit        int          DEFAULT 50,
  p_cursor       timestamptz  DEFAULT NULL,
  p_cursor_id    uuid         DEFAULT NULL
) RETURNS SETOF public.workspace_member_actions
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;  -- never error on unauthenticated; just empty
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organizations o
    JOIN public.workspaces w ON w.organization_id = o.id
    WHERE w.id = p_workspace_id
      AND o.owner_user_id = auth.uid()
  ) THEN
    RETURN;  -- non-owner / nonexistent workspace → empty (no leak)
  END IF;

  -- Keyset cursor on (created_at, id) — both required to disambiguate ties
  -- when multiple audit rows share microsecond-resolution created_at (a
  -- bulk-insert within one statement shares now()). The plain `created_at <
  -- p_cursor` predicate skips every tied row from the prior page, producing
  -- silent pagination drops. p_cursor_id NULL is accepted for back-compat
  -- with first-page callers (no tiebreak needed when p_cursor is also NULL).
  RETURN QUERY
    SELECT *
    FROM public.workspace_member_actions
    WHERE workspace_id = p_workspace_id
      AND (
        p_cursor IS NULL
        OR (p_cursor_id IS NULL AND created_at < p_cursor)
        OR (p_cursor_id IS NOT NULL AND (created_at, id) < (p_cursor, p_cursor_id))
      )
    ORDER BY created_at DESC, id DESC
    LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$$;

REVOKE ALL ON FUNCTION public.list_workspace_member_actions(uuid, int, timestamptz, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_workspace_member_actions(uuid, int, timestamptz, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.list_workspace_member_actions(uuid, int, timestamptz, uuid) IS
  'Owner-only audit reader. Empty return on non-owner / nonexistent workspace '
  '(no error, no table-existence leak). Keyset cursor on (created_at, id) — pass '
  'the oldest returned (created_at, id) of the previous page as (p_cursor, p_cursor_id) '
  'for the next page. ORDER BY created_at DESC, id DESC. #4231.';

-- =====================================================================
-- 6. Anonymise RPC — Art. 17 cascade
-- =====================================================================
--
-- NULL-sets PII columns (actor_user_id, target_user_id) for every row
-- referencing p_user_id. Audit lineage (id, workspace_id, action_type,
-- old_role, new_role, created_at, attestation_id) preserved. Idempotent:
-- re-runs match zero already-NULLed rows. SET LOCAL session_replication_
-- role='replica' bypasses the pure-reject WORM trigger; RESET after the
-- UPDATE (mig 051/053b convention — replica role persists to subsequent
-- statements without explicit RESET).

CREATE OR REPLACE FUNCTION public.anonymise_workspace_member_actions(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.workspace_member_actions
     SET actor_user_id  = NULL,
         target_user_id = NULL
   WHERE actor_user_id  = p_user_id
      OR target_user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RESET session_replication_role;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_member_actions(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_member_actions(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_workspace_member_actions(uuid) IS
  'Art. 17 erasure: NULL-sets actor_user_id + target_user_id on workspace_member_'
  'actions rows referencing p_user_id. Audit lineage preserved. Idempotent. '
  'Called from account-delete.ts step 3.93 BEFORE auth.admin.deleteUser. '
  'Pattern source: mig 051 anonymise_action_sends + session_replication_role '
  'replica-role bypass of the pure-reject WORM trigger. #4231.';

-- =====================================================================
-- 7. Retention purge wrapper — pg_cron callable
-- =====================================================================
--
-- pg_cron invokes this wrapper instead of a direct DELETE; the pure-
-- reject WORM trigger would silently block direct DELETE (learning
-- 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md).
-- Observability: pg_cron auto-populates cron.job_run_details with
-- start/end timestamps + return value on every run. The RAISE LOG row
-- flows through Supabase logs → Vector → Better Stack.

CREATE OR REPLACE FUNCTION public.purge_workspace_member_actions()
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL session_replication_role = 'replica';
  DELETE FROM public.workspace_member_actions
   WHERE created_at < now() - interval '7 years';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RESET session_replication_role;
  RAISE LOG 'audit_retention_purge table=workspace_member_actions deleted_count=%', v_rows;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_workspace_member_actions()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_workspace_member_actions()
  TO postgres;

COMMENT ON FUNCTION public.purge_workspace_member_actions() IS
  'pg_cron-invoked 7-year retention purge. SET LOCAL session_replication_role='
  '''replica'' bypasses the pure-reject WORM trigger (direct DELETE from cron '
  'would silently fail — learning 2026-05-15-worm-trigger-blocks-pg-cron-'
  'retention-sweep). Observability: cron.job_run_details (auto) + RAISE LOG. #4231.';

-- =====================================================================
-- 8. Re-CREATE mig 058 RPCs to set the actor GUC (and replica-bypass
--    for anonymise_workspace_members)
-- =====================================================================
--
-- 8a. invite_workspace_member — prepend set_config so the AFTER trigger
--     captures the calling owner as v_actor. NOTE: set_config(name,
--     value, is_local=true) — NOT SET LOCAL <key> = <expr> (which
--     accepts only literals). PERFORM discards the prior-value return.

CREATE OR REPLACE FUNCTION public.invite_workspace_member(
  p_workspace_id      uuid,
  p_invitee_user_id   uuid,
  p_attestation_text  text,
  p_ip_hash           text,
  p_user_agent        text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_inviter_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_attestation_id uuid;
BEGIN
  -- mig 063: capture actor for the workspace_members AFTER trigger.
  -- set_config(name, value, is_local=true) — SET LOCAL <key> = <expr>
  -- rejects non-literal expressions like COALESCE.
  PERFORM set_config('workspace_audit.actor_user_id', COALESCE(auth.uid()::text, ''), true);

  IF v_inviter_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_workspace_id IS NULL OR p_invitee_user_id IS NULL THEN
    RAISE EXCEPTION 'workspace_id and invitee_user_id are required'
      USING ERRCODE = '22004';
  END IF;

  IF p_attestation_text IS NULL OR length(p_attestation_text) < 16 THEN
    RAISE EXCEPTION 'attestation_text must be at least 16 chars'
      USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_inviter_user_id
      AND role         = 'owner'
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF v_inviter_user_id = p_invitee_user_id THEN
    RAISE EXCEPTION 'owner cannot invite themselves'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = p_invitee_user_id
  ) THEN
    RAISE EXCEPTION 'user is already a member of workspace %', p_workspace_id
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.workspace_member_attestations (
    workspace_id, inviter_user_id, invitee_user_id,
    attestation_text, ip_hash, user_agent
  ) VALUES (
    p_workspace_id, v_inviter_user_id, p_invitee_user_id,
    p_attestation_text, p_ip_hash, p_user_agent
  )
  RETURNING id INTO v_attestation_id;

  INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
       VALUES (p_workspace_id, p_invitee_user_id, 'member', v_attestation_id);

  RETURN v_attestation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.invite_workspace_member(uuid, uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invite_workspace_member(uuid, uuid, text, text, text)
  TO authenticated;

-- 8b. remove_workspace_member — same set_config prepend pattern.

CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_target_role    text;
  v_rows           int;
BEGIN
  -- mig 063: capture actor for the workspace_members AFTER trigger.
  PERFORM set_config('workspace_audit.actor_user_id', COALESCE(auth.uid()::text, ''), true);

  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_caller_user_id
      AND role         = 'owner'
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF v_caller_user_id = p_user_id THEN
    RAISE EXCEPTION 'owner cannot remove themselves; use account-delete to cascade-anonymise instead'
      USING ERRCODE = '22023';
  END IF;

  SELECT role INTO v_target_role
  FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RETURN 0;
  END IF;

  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'cannot remove another owner; only members can be removed'
      USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_workspace_member(uuid, uuid)
  TO authenticated;

-- 8c. anonymise_workspace_members — prepend SET LOCAL session_replication_
--     role='replica' so the new AFTER trigger does NOT fire during the
--     account-delete cascade DELETE. Without this, step 3.91's DELETE
--     creates net-new audit rows with target_user_id=<deleted user>,
--     producing orphan PII for a user requesting Art. 17 erasure.
--     Plan-review P1-2 fix.

CREATE OR REPLACE FUNCTION public.anonymise_workspace_members(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- mig 063: bypass the new workspace_members_audit_trigger so the
  -- cascade DELETE does not create orphan-PII audit rows (plan-review
  -- P1-2; see also account-delete.ts step 3.93).
  SET LOCAL session_replication_role = 'replica';
  DELETE FROM public.workspace_members
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RESET session_replication_role;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_members(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_members(uuid)
  TO service_role;

-- =====================================================================
-- 9. Backfill — synthetic 'added' rows for pre-existing memberships
-- =====================================================================
--
-- LOCK SHARE prevents concurrent app-server INSERTs into
-- workspace_members from being double-audited (once via the new AFTER
-- trigger, once via this backfill SELECT). SHARE permits concurrent
-- SELECTs but blocks INSERTs for the migration duration (plan-review
-- P1-1). SET LOCAL session_replication_role='replica' bypasses the
-- pure-reject WORM trigger on the direct INSERT into workspace_member_
-- actions. NOT EXISTS discriminator makes the backfill idempotent on
-- re-apply.

DO $$
DECLARE
  v_membership_count        int;
  v_backfilled_count        int;
  v_preexisting_added_count int;
BEGIN
  -- Bound the LOCK wait so a long-running concurrent INSERT cannot stall the
  -- migration indefinitely; bound statements similarly so the SELECT cannot.
  SET LOCAL lock_timeout = '30s';
  SET LOCAL statement_timeout = '5min';
  LOCK TABLE public.workspace_members IN SHARE MODE;
  SET LOCAL session_replication_role = 'replica';

  -- Capture pre-existing 'added' rows BEFORE the backfill INSERT so the
  -- post-insert ASSERT can tolerate re-apply (where some rows already exist).
  SELECT count(*) INTO v_preexisting_added_count
    FROM public.workspace_member_actions
   WHERE action_type = 'added';

  INSERT INTO public.workspace_member_actions
    (workspace_id, actor_user_id, target_user_id, action_type, new_role, created_at)
  SELECT m.workspace_id, NULL, m.user_id, 'added', m.role, m.created_at
    FROM public.workspace_members m
   WHERE NOT EXISTS (
     SELECT 1 FROM public.workspace_member_actions a
      WHERE a.workspace_id    = m.workspace_id
        AND a.target_user_id  = m.user_id
        AND a.action_type     = 'added'
   );
  GET DIAGNOSTICS v_backfilled_count = ROW_COUNT;
  RESET session_replication_role;

  SELECT count(*) INTO v_membership_count FROM public.workspace_members;

  -- AC8 invariant: every workspace_members row has at least one corresponding
  -- 'added' audit row after backfill. Equality (not >=) on a fresh apply;
  -- re-apply tolerates pre-existing rows via the discriminator above.
  IF v_backfilled_count + v_preexisting_added_count <> v_membership_count THEN
    RAISE EXCEPTION
      'workspace_member_actions backfill parity failed: backfilled=% + pre-existing=% != members=%',
      v_backfilled_count, v_preexisting_added_count, v_membership_count;
  END IF;

  RAISE NOTICE 'workspace_member_actions backfill: % rows inserted (+ % pre-existing) for % workspace_members',
    v_backfilled_count, v_preexisting_added_count, v_membership_count;
END $$;

-- =====================================================================
-- 10. pg_cron schedule — daily 7-year retention purge
-- =====================================================================

-- Wrap in DO/EXCEPTION to mirror mig 041 + mig 043 precedent. Modern pg_cron
-- upserts by name, but older revisions and self-hosted runners may raise
-- duplicate_object on re-apply; the EXCEPTION block keeps the migration
-- idempotent across pg_cron versions.
DO $$
BEGIN
  PERFORM cron.schedule(
    'workspace-member-actions-retention',
    '0 4 * * *',
    $cron$SELECT public.purge_workspace_member_actions()$cron$
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;  -- already scheduled; no-op on re-apply
END $$;
