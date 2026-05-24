-- Migration 065: Art. 17 cascade deadlock repair (post-#4356 follow-up).
--
-- Ref     #4356 (residual tenant-integration failures the #4343 / #4357
--                deepen-pass sweeps missed: deleteUser cascade fails
--                across 6+ tenant-isolation test files; deleteAccount
--                returns success=false from dsar-export-workspace-tables
--                AC-GDPR-17-CALLER).
--
-- =============================================================
-- The deadlock
-- =============================================================
--
-- account-delete.ts (Art. 17 cascade) and any raw service.auth.admin.
-- deleteUser call against a user with the default solo-canary workspace
-- both fail at the public.users delete step. The chain:
--
--   1. auth.users delete → CASCADE to public.users (mig 001:7).
--   2. public.users delete is BLOCKED by RESTRICT FKs:
--      - organizations.owner_user_id RESTRICT (mig 053:330)
--      - audit_byok_use.founder_id RESTRICT (mig 037:34)
--   3. account-delete.ts step 3.92 tries to resolve organizations by
--      hard-deleting the orphan org (DELETE FROM workspaces; DELETE
--      FROM organizations). But that DELETE FROM workspaces is BLOCKED
--      in turn by RESTRICT FKs from {workspace_member_actions,
--      workspace_member_attestations, conversations, messages, ...}
--      added by migs 058/059/063.
--   4. The orphan-delete path is also blocked by the WORM BEFORE DELETE
--      triggers on workspace_member_actions / workspace_member_attestations,
--      so changing those FKs to CASCADE alone wouldn't help — the trigger
--      fires inside the FK cascade and RAISEs P0001.
--
-- Net effect: deleteUser fails in CI across 6+ tenant-isolation tests
-- (afterAll cleanup); deleteAccount returns success=false (dsar-export
-- AC-GDPR-17-CALLER); Art. 17 erasure is broken in dev and prd.
--
-- =============================================================
-- The repair
-- =============================================================
--
-- Break the cycle by downgrading the two user-FK RESTRICTs that block
-- public.users delete to SET NULL. Then:
--
--   1. auth.users delete → CASCADE to public.users (unchanged).
--   2. public.users delete:
--      - SET NULL on organizations.owner_user_id (FK no longer blocks)
--      - SET NULL on audit_byok_use.founder_id (audit row stays, PII
--        column NULLed)
--      - CASCADE to {conversations, messages, kb_share_links,
--        push_subscriptions, user_concurrency_slots, runtime_cost_state,
--        ...} via their existing user_id ON DELETE CASCADE FKs
--   3. The CASCADE deletes naturally remove rows whose workspace_id
--      RESTRICT FK was the secondary block.
--   4. The orphan workspace itself remains, owned by NULL. Its WORM
--      audit rows (workspace_member_actions, workspace_member_attestations)
--      have already been NULLed of PII by their respective anonymise_*
--      RPCs (account-delete.ts steps 3.90 + 3.93). The workspace is
--      inert — record-of-existence with no live PII. A future janitor
--      can purge null-owner orgs / orphan workspaces; that cleanup is
--      out of scope for #4356.
--
-- =============================================================
-- Part 1 — organizations.owner_user_id: RESTRICT → SET NULL
-- =============================================================
--
-- mig 053:329 declared `owner_user_id uuid NOT NULL REFERENCES public.users(id)
--                       ON DELETE RESTRICT`.
--
-- Drop the NOT NULL constraint AND the FK; re-add with SET NULL. After
-- mig 065, an organization with owner_user_id IS NULL represents an
-- Art-17-cleared org awaiting janitor purge. handle_new_user (mig 053:289)
-- still INSERTs owner_user_id = NEW.id explicitly, so live-user inserts
-- never produce NULL owners. RLS policies key on `auth.uid() = owner_user_id`
-- which is NULL-safe (NULL ≠ NULL); orphan orgs are inaccessible to all
-- live users.

ALTER TABLE public.organizations
  ALTER COLUMN owner_user_id DROP NOT NULL;

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_owner_user_id_fkey;

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_owner_user_id_fkey
  FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- =============================================================
-- Part 2 — audit_byok_use.founder_id: RESTRICT → SET NULL
-- =============================================================
--
-- mig 037:34 declared `founder_id uuid NOT NULL REFERENCES public.users(id)
--                      ON DELETE RESTRICT`.
--
-- After mig 065, an audit row with founder_id IS NULL represents an
-- Art-17-anonymised audit entry. workspace_id is preserved (workspace
-- scope is not user PII). token_count / unit_cost_cents / agent_role
-- / ts remain — useful for aggregate-cost analytics with the founder-
-- identifying column scrubbed.
--
-- The write_byok_audit RPC (mig 061) signature still requires a non-NULL
-- p_founder_id uuid parameter, so production INSERTs always supply a
-- value. NULL founder_id arises only via this SET NULL cascade.

ALTER TABLE public.audit_byok_use
  ALTER COLUMN founder_id DROP NOT NULL;

ALTER TABLE public.audit_byok_use
  DROP CONSTRAINT IF EXISTS audit_byok_use_founder_id_fkey;

ALTER TABLE public.audit_byok_use
  ADD CONSTRAINT audit_byok_use_founder_id_fkey
  FOREIGN KEY (founder_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- =============================================================
-- Part 3 — anonymise_organization_membership: drop orphan-delete path
-- =============================================================
--
-- Pre-065, the RPC's orphan path attempted DELETE FROM workspaces +
-- DELETE FROM organizations. With Part 1, organizations.owner_user_id
-- naturally transitions to NULL via the SET NULL cascade; the explicit
-- orphan-delete is no longer needed (and is the chain that produced
-- the cascade failure documented in the dsar-export AC-GDPR-17-CALLER
-- failure log: `ERROR: anonymise_organization_membership failed —
-- aborting deletion`).
--
-- The reassign-ownership path remains for live multi-tenant orgs: when
-- p_user_id is removed but other members exist, ownership is reassigned
-- to the oldest remaining member so the workspace stays accessible.
--
-- Return semantics: returns the number of orgs whose ownership was
-- reassigned. Orphan orgs return 0 (they're handled by the SET NULL
-- cascade, not by this RPC).
--
-- Idempotent: re-running on an already-anonymised user is a no-op
-- (no rows match WHERE owner_user_id = p_user_id after the first call).

CREATE OR REPLACE FUNCTION public.anonymise_organization_membership(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_orgs_reassigned int := 0;
BEGIN
  -- For each org where p_user_id is the owner AND other members exist,
  -- reassign ownership to the oldest remaining non-departing member.
  -- For orphan orgs (no other members), do nothing — the SET NULL
  -- cascade from public.users delete will clear owner_user_id when
  -- auth-delete fires later in account-delete.ts.
  UPDATE public.organizations o
     SET owner_user_id = (
       SELECT m.user_id
       FROM public.workspace_members m
       JOIN public.workspaces w ON w.id = m.workspace_id
       WHERE w.organization_id = o.id
         AND m.user_id != p_user_id
       ORDER BY m.created_at ASC
       LIMIT 1
     )
   WHERE o.owner_user_id = p_user_id
     AND EXISTS (
       SELECT 1
       FROM public.workspace_members m
       JOIN public.workspaces w ON w.id = m.workspace_id
       WHERE w.organization_id = o.id
         AND m.user_id != p_user_id
     );
  GET DIAGNOSTICS v_orgs_reassigned = ROW_COUNT;
  RETURN v_orgs_reassigned;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_organization_membership(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_organization_membership(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_organization_membership(uuid) IS
  'Art. 17 cascade RPC (post-mig 065). Reassigns org ownership for live '
  'multi-tenant orgs; orphan orgs rely on the SET NULL cascade triggered '
  'by public.users delete (mig 065 part 1). Returns count of reassigned '
  'orgs. Account-delete.ts step 3.92. #4356.';
