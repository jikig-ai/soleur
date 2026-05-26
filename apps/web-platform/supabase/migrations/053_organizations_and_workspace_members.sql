-- 053_organizations_and_workspace_members.sql
-- feat-team-workspace-multi-user (#4229, PR #4225) — first-class
-- organizations + workspaces + workspace_members + is_workspace_member
-- helper + backfill.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(b) — contract performance with the data
-- subject (account-holder). organizations, workspaces, and
-- workspace_members are constitutive of the Soleur service contract for
-- the multi-user product surface. Backfilled solo rows exist to provide
-- service continuity for existing single-user accounts and carry the
-- same lawful basis.
--
-- RETENTION: indefinite while the user maintains an active account.
-- Art. 17 erasure cascades via anonymise_organization_membership +
-- anonymise_workspace_members + anonymise_workspace_member_attestations
-- (defined in migration 054). Soft-delete pattern: foreign keys are
-- ON DELETE RESTRICT to force explicit anonymisation rather than
-- accidental cascade-drop of audit lineage.
--
-- Helper shape locked: LANGUAGE plpgsql SECURITY DEFINER
-- SET search_path = public, pg_temp. NO STABLE keyword per Kieran C3 +
-- migration 045's is_message_owner precedent — planner-inlining sql
-- STABLE functions dissolves the SECURITY DEFINER boundary back into
-- the caller's tenant-JWT RLS context. plpgsql is NOT inlinable.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: pg_temp LAST.
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public:
-- explicit REVOKE from PUBLIC + anon + authenticated + service_role;
-- explicit GRANT to authenticated.
--
-- Backfill pattern per
-- 2026-03-20-gdpr-remediation-migration-discriminator-strategy:
-- IS DISTINCT FROM / WHERE NOT EXISTS discriminator,
-- DO $$ ... GET DIAGNOSTICS rc = ROW_COUNT; RAISE NOTICE $$ audit.
-- workspaces.id = users.id for backfilled solo workspaces (ADR-038
-- permanent invariant per Kieran N2).

-- =====================================================================
-- 1. organizations
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.organizations (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  -- name NULL by default for solo backfill. UI suppresses display when
  -- the user has only one organization and its name is NULL. New
  -- organizations created post-flag-flip MUST set name (enforced at
  -- application layer via the invite flow; no NOT NULL constraint here
  -- so the backfill stays single-statement).
  name            text         NULL,
  domain          text         NULL,
  owner_user_id   uuid         NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at      timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 2. workspaces
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.workspaces (
  -- NOTE: no DEFAULT gen_random_uuid(). Backfill explicitly sets
  -- workspaces.id = owner_user_id for solo workspaces (ADR-038 N2).
  -- New workspaces created post-flag-flip MUST supply id at INSERT
  -- (the invite flow + create-organization flow both call
  -- gen_random_uuid() in application code). This prevents accidental
  -- coupling between solo-backfill semantics and the post-flag-flip
  -- shape.
  id              uuid         PRIMARY KEY,
  organization_id uuid         NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  name            text         NULL,
  created_at      timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 3. workspace_members
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.workspace_members (
  workspace_id    uuid         NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  user_id         uuid         NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  role            text         NOT NULL CHECK (role IN ('owner', 'member')),
  -- attestation_id FK is added in migration 054 AFTER
  -- workspace_member_attestations exists. Left NULL here so the
  -- backfill (system-driven, no human-attested act) can populate
  -- without a referent.
  attestation_id  uuid         NULL,
  created_at      timestamptz  NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id, user_id)
);

ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

-- Index for membership-resolution lookups (is_workspace_member helper
-- + default-org-on-login resolver). The PK already covers
-- (workspace_id, user_id); this adds the inverse user→workspaces
-- index needed for the JWT-claim default resolution path.
CREATE INDEX IF NOT EXISTS workspace_members_user_id_idx
  ON public.workspace_members (user_id);

-- =====================================================================
-- 4. is_workspace_member helper
-- =====================================================================
--
-- SECURITY DEFINER plpgsql function — the substrate for every workspace-
-- keyed RLS predicate in migration 055 and downstream. Same shape as
-- is_message_owner (migration 045, verified on origin/main 2026-05-21).
-- PR-D #3883 (feat-pr-d-attachments-storage-tenant-rls) merged with the
-- same plpgsql + SET search_path = public, pg_temp shape; no
-- divergence from main → lock new helper to plpgsql per Phase 0.1
-- probe outcome.

DROP FUNCTION IF EXISTS public.is_workspace_member(uuid, uuid);
CREATE FUNCTION public.is_workspace_member(p_workspace_id uuid, p_user_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_exists boolean;
BEGIN
  -- LANGUAGE plpgsql + no STABLE/IMMUTABLE: Postgres's planner inlines
  -- sql STABLE functions, dissolving the SECURITY DEFINER boundary
  -- back into the caller's tenant-JWT RLS context. plpgsql is NOT
  -- inlinable; the inner SELECT runs at the function owner's
  -- superuser RLS context as intended.
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = p_user_id
  ) INTO v_exists;
  RETURN v_exists;
END;
$$;

REVOKE ALL ON FUNCTION public.is_workspace_member(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.is_workspace_member(uuid, uuid) IS
  'Returns TRUE if (p_user_id) is a member of (p_workspace_id). '
  'SECURITY DEFINER plpgsql so planner-inlining cannot dissolve the '
  'tenant-isolation boundary. Substrate for all workspace-keyed RLS '
  'predicates (migration 055 sweep). ADR-038.';

-- =====================================================================
-- 5. RLS policies referencing is_workspace_member
-- =====================================================================
--
-- Members can SELECT organizations they belong to, workspaces they
-- belong to, and rows of workspace_members for those workspaces (peer
-- visibility). INSERT / UPDATE / DELETE are routed through SECURITY
-- DEFINER RPCs in migration 054 (invite_workspace_member,
-- remove_workspace_member); no policy grants those verbs to
-- authenticated.

CREATE POLICY orgs_select_for_members ON public.organizations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.workspaces w
      WHERE w.organization_id = organizations.id
        AND public.is_workspace_member(w.id, auth.uid())
    )
  );

CREATE POLICY workspaces_select_for_members ON public.workspaces
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspaces.id, auth.uid()));

CREATE POLICY members_select_peers ON public.workspace_members
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_members.workspace_id, auth.uid()));

-- =====================================================================
-- 6. Backfill (idempotent, audited)
-- =====================================================================
--
-- One organization (name=NULL) per existing user.
-- One workspace per organization, with workspaces.id = users.id
-- (ADR-038 permanent invariant per Kieran N2).
-- One workspace_members row (role='owner', attestation_id=NULL) per
-- workspace.
--
-- Idempotency: WHERE NOT EXISTS discriminator on
-- organizations.owner_user_id (one org per user, backfilled-solo),
-- workspaces.id (=users.id), and (workspace_id, user_id) PK.
-- Re-running this migration on a populated DB logs `0 rows` for each
-- INSERT block.
--
-- For the trigger-vs-fallback parity concern
-- (2026-03-20-supabase-trigger-fallback-parity.md): handle_new_user
-- trigger is defined in 001_initial_schema.sql. It currently inserts a
-- public.users row from auth.users; it does NOT touch organizations /
-- workspaces / workspace_members. The TS fallback path for new-user
-- creation (in apps/web-platform/server/auth/* — verified at /work
-- time for migration 053) must be extended in Phase 5 to upsert
-- (organization, workspace, workspace_members) with
-- onConflict + ignoreDuplicates:true. The 053 backfill covers
-- EXISTING users; new users are covered by the trigger + TS fallback
-- ON ACCOUNT CREATION.

-- Discriminator strategy:
--
-- The canary for "this user is already backfilled" is the self-
-- referential row workspace_members(workspace_id = u.id, user_id =
-- u.id, role = 'owner'). It is permanent (created at backfill;
-- workspace_members owner rows are NOT deleted by member-rename or
-- org-rename flows), so it survives any post-backfill mutation of the
-- organization (e.g., Jean renaming his backfilled "Solo" org to
-- "jikigai" after inviting Harry — the workspace_id=Jean.id and
-- user_id=Jean.id and role='owner' row persists). Re-running 053 on
-- such a populated DB logs 0/0/0 for all three INSERTs.
--
-- 6b filters on organizations.name IS NULL only as belt-and-braces
-- (skip workspace creation for any non-backfill org that may already
-- exist post-flag-flip); 6c filters by PK NOT EXISTS only.

DO $$
DECLARE
  v_org_rc int;
  v_ws_rc  int;
  v_mem_rc int;
BEGIN
  -- 6a. organizations: one per user lacking the canary owner row.
  INSERT INTO public.organizations (id, name, domain, owner_user_id)
  SELECT gen_random_uuid(), NULL, NULL, u.id
  FROM public.users u
  WHERE NOT EXISTS (
    SELECT 1 FROM public.workspace_members m
    WHERE m.user_id      = u.id
      AND m.workspace_id = u.id
      AND m.role         = 'owner'
  );
  GET DIAGNOSTICS v_org_rc = ROW_COUNT;
  RAISE NOTICE '[053-backfill] organizations inserted: %', v_org_rc;

  -- 6b. workspaces: workspaces.id = owner_user_id for each backfill org
  -- that doesn't yet have its workspace row (PK guard).
  INSERT INTO public.workspaces (id, organization_id, name)
  SELECT o.owner_user_id, o.id, NULL
  FROM public.organizations o
  WHERE o.name IS NULL  -- only backfill-shaped orgs (defensive vs post-flag-flip non-NULL orgs)
    AND NOT EXISTS (
      SELECT 1 FROM public.workspaces w WHERE w.id = o.owner_user_id
    );
  GET DIAGNOSTICS v_ws_rc = ROW_COUNT;
  RAISE NOTICE '[053-backfill] workspaces inserted: %', v_ws_rc;

  -- 6c. workspace_members: one owner row per backfilled workspace.
  INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
  SELECT w.id, w.id, 'owner', NULL
  FROM public.workspaces w
  WHERE NOT EXISTS (
    SELECT 1 FROM public.workspace_members m
    WHERE m.workspace_id = w.id AND m.user_id = w.id
  );
  GET DIAGNOSTICS v_mem_rc = ROW_COUNT;
  RAISE NOTICE '[053-backfill] workspace_members inserted: %', v_mem_rc;
END $$;

-- =====================================================================
-- 7. handle_new_user trigger parity: extend for new-user signups
-- =====================================================================
--
-- The existing handle_new_user trigger (migration 001) creates a
-- public.users row from auth.users INSERT. Post-053, new users ALSO
-- need: one organization (name=NULL backfill-shaped), one workspace
-- (id = users.id per ADR-038 N2), one workspace_members(role='owner').
-- Without this, new signups post-053 would have a public.users row
-- but no workspace context — every workspace-keyed query (post-055
-- sweep) would return zero rows for them and the agent runtime would
-- fail to find their workspace.
--
-- Per 2026-03-20-supabase-trigger-fallback-parity.md: the TS fallback
-- path in apps/web-platform/server/auth/* (post-signup hook) MUST
-- mirror this logic with upsert(onConflict, ignoreDuplicates:true)
-- semantics. The mirror lands in Phase 5 (server-side); for the
-- migration window between 053 apply and Phase 5 ship, the trigger
-- alone is sufficient because the trigger fires synchronously inside
-- the auth.users INSERT transaction — the TS fallback exists only as
-- a defense-in-depth path against trigger failure.
--
-- Per 2026-03-20-supabase-trigger-boolean-cast-safety.md: this trigger
-- does NOT touch raw_user_meta_data; no ::boolean cast hazard.

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
  INSERT INTO public.users (id, email, workspace_path)
  VALUES (
    NEW.id,
    NEW.email,
    '/workspaces/' || NEW.id::text
  )
  ON CONFLICT (id) DO NOTHING;

  -- 2. Insert organization (backfill-shaped) for this user IF they
  -- don't already have the canary owner row. Idempotent via the same
  -- discriminator as the backfill DO block above.
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members m
    WHERE m.user_id = NEW.id AND m.workspace_id = NEW.id AND m.role = 'owner'
  ) THEN
    INSERT INTO public.organizations (id, name, domain, owner_user_id)
    VALUES (gen_random_uuid(), NULL, NULL, NEW.id)
    RETURNING id INTO v_org_id;

    INSERT INTO public.workspaces (id, organization_id, name)
    VALUES (NEW.id, v_org_id, NULL)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
    VALUES (NEW.id, NEW.id, 'owner', NULL)
    ON CONFLICT (workspace_id, user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- Re-create the trigger if it exists (CREATE OR REPLACE on the
-- function above is sufficient because the trigger references the
-- function by name).

-- handle_new_user is a trigger function (fires AFTER INSERT on
-- auth.users) and is not invoked via direct CALL. The REVOKE is
-- defensive (satisfies migration-rpc-grants lint + closes the
-- "direct EXECUTE via SQL injection" surface). Triggers fire under
-- the owner's identity regardless of EXECUTE grant on the function,
-- so this REVOKE does NOT break the signup flow.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Auth signup hook. Creates public.users row + backfill-shaped '
  'organization + workspace (id = users.id per ADR-038 N2) + '
  'workspace_members(role=owner). Idempotent via canary owner-row '
  'discriminator + per-table ON CONFLICT DO NOTHING. SECURITY DEFINER '
  'so RLS does not block during the auth.users INSERT trigger. '
  'TS fallback parity required per '
  '2026-03-20-supabase-trigger-fallback-parity.md.';

COMMENT ON TABLE public.organizations IS
  'Billing-grain entity. One per Soleur account-holder at first, '
  'multi-member post-invite-flow. Backfilled solo orgs have name=NULL '
  '(UI sentinel for hide-org-name-in-header). ADR-038.';

COMMENT ON TABLE public.workspaces IS
  'Isolation-grain entity. One per organization initially; multi-'
  'workspace-per-organization is future scope. workspaces.id = '
  'owner_user_id for backfilled solo workspaces (ADR-038 N2 permanent '
  'invariant); gen_random_uuid() for post-flag-flip workspaces.';

COMMENT ON TABLE public.workspace_members IS
  'Membership join table. role in (''owner'',''member''). '
  'attestation_id FK added in migration 054 once '
  'workspace_member_attestations exists. attestation_id IS NULL for '
  'backfilled-owner rows (system-driven, no human-attested act).';
