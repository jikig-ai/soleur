-- =====================================================================
-- 109_backfill_residual_personal_workspace_membership.sql
--
-- ADR-044 PR-1 (FR5). Residual backfill of the personal-workspace owner
-- membership canary for any pre-existing user who lacks it. Mirrors the
-- handle_new_user trigger body (mig 091:157-172) EXACTLY (name 'My Workspace',
-- gen_random_uuid() org keyed by owner_user_id, workspace.id = user.id) and the
-- mig 053:221-262 backfill DO block — re-runs the same idempotent shape for
-- existing rows the trigger never covered (it only fires on NEW signups).
--
-- WHY THIS IS NEEDED (and is a HARD PREREQUISITE for the PR-1 owner-gate):
--   `is_workspace_owner(p_workspace_id, p_user_id)` (mig 098) returns TRUE only
--   when a `workspace_members` row with role='owner' exists. The PR-1 owner-gate
--   on /api/repo/setup + /api/repo/disconnect calls
--   `is_workspace_owner(user.id, user.id)`, so a user MISSING this canary row
--   would be 403'd from connecting/disconnecting their OWN solo repo. The gate
--   is "a no-op for solo by construction" ONLY once this canary holds for every
--   user — that is what this backfill guarantees. The release pipeline runs
--   migrations BEFORE code cutover (web-platform-release.yml), so this applies
--   before the gate code goes live.
--
-- COUNT AT AUTHORING (read-only `users LEFT JOIN workspace_members`):
--   prd = 0 missing (15 users)   → 0-row no-op on prd.
--   dev = 18,287 missing (62,746 users; synthetic seed/load-test accounts)
--                                → healed here so dev QA connect flows don't 403.
--
-- IDEMPOTENT: the owner-membership-canary discriminator (mig 053/091's) makes a
-- re-run insert nothing. The AFTER INSERT audit trigger on workspace_members
-- emits one benign actor_user_id=NULL WORM row per backfilled member (tolerated —
-- the exact path mig 053's own backfill exercised).
--
-- ORPHAN-ORG NOTE (dev-only, benign, precedented): a user who already has a
-- `workspaces` row (id=user.id) but lacks the owner canary still enters the loop
-- and gets a fresh org; the `workspaces` insert then ON CONFLICT-skips, so the
-- new org has no child workspace. This is invisible (orgs RLS exposes only
-- member-reachable orgs), carries no PII, and is the identical asymmetry mig
-- 053's 6a/6b split produces. On dev this affects ~13,667 of the 18,287; prd is
-- 0-missing so no orphan orgs accrue there.
--
-- Transaction wrapping: NO top-level BEGIN/COMMIT. The canonical migration
-- runner (apps/web-platform/scripts/run-migrations.sh) pipes this body + the
-- trailing _schema_migrations INSERT to psql --single-transaction (mig 098/068
-- header rationale).
-- =====================================================================

DO $$
DECLARE
  v_user   RECORD;
  v_org_id uuid;
  v_count  int := 0;
BEGIN
  FOR v_user IN
    SELECT u.id
    FROM public.users u
    WHERE NOT EXISTS (
      SELECT 1 FROM public.workspace_members m
      WHERE m.user_id      = u.id
        AND m.workspace_id = u.id
        AND m.role         = 'owner'
    )
  LOOP
    -- Mirror handle_new_user (mig 091): one default-named org per user, a
    -- solo workspace keyed on the user id, and the owner membership canary.
    INSERT INTO public.organizations (id, name, domain, owner_user_id)
    VALUES (gen_random_uuid(), 'My Workspace', NULL, v_user.id)
    RETURNING id INTO v_org_id;

    INSERT INTO public.workspaces (id, organization_id, name)
    VALUES (v_user.id, v_org_id, 'My Workspace')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
    VALUES (v_user.id, v_user.id, 'owner', NULL)
    ON CONFLICT (workspace_id, user_id) DO NOTHING;

    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE '[109-backfill] residual personal-workspace memberships backfilled: %', v_count;
END $$;
