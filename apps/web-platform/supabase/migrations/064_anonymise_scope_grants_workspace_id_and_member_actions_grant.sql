-- Migration 064: tenant-integration cascade repair (post-#4343 follow-up).
--
-- Closes #4356 (4 sibling failure classes #4343's sweep missed).
-- Ref     #4249 (original lifecycle.test.ts WORM failure — Class H below
--                fully resolves the residual `anonymise_scope_grants
--                bypasses WORM trigger and zeros founder_id` assertion
--                that #4343 left red).
--
-- Two independent additive repairs in one migration; both are idempotent.
--
-- =============================================================
-- Class H — anonymise_scope_grants(p_user_id) contract-pair gap
-- =============================================================
--
-- Mig 059 (`059_workspace_keyed_rls_sweep.sql:358-360`) added the row-level
-- CHECK constraint `scope_grants_workspace_id_check`:
--
--   CHECK ((founder_id IS NULL  AND workspace_id IS NULL)
--      OR  (founder_id IS NOT NULL AND workspace_id IS NOT NULL))
--
-- The constraint comment ("Allow NULL when founder_id IS NULL") signals
-- design intent: an Art. 17-anonymised row SHOULD have BOTH NULL.
--
-- Mig 050's `anonymise_scope_grants` (`050:74-92`) only NULLs `founder_id`,
-- leaving `workspace_id` populated. Every call against a row with a non-NULL
-- workspace_id now fails CHECK with SQLSTATE 23514, aborting the Art. 17
-- erasure chain at step 3.82 (`account-delete.ts:300-313`) and leaving the
-- founder partially-deleted with `scope_grants` PII retained — Art. 33
-- notifiable in prd.
--
-- This is the same contract-pair pattern as PR #4343's Class A
-- (`grant_action_class` + NOT NULL workspace_id): the writer-side function
-- was added in mig 059 but the sibling anonymise writer was missed by the
-- deepen-pass sweep (the grep was scoped to `*.tenant-isolation.test.ts$`).
--
-- Fix shape: lift the function body verbatim from mig 050 and add a single
-- column to the UPDATE SET clause. NO trigger change required:
--
--   - `scope_grants_no_mutate` Shape 2 (mig 050:42-52) checks for the
--     founder_id transition + 6 named columns unchanged (action_class,
--     tier, granted_at, created_at, revoked_at, revoked_reason).
--     `workspace_id` is NOT in that list, so a workspace_id change to NULL
--     alongside the founder_id NULL is silently permitted under Shape 2.
--     The trigger returns NEW and the row-level CHECK is the canonical
--     guard.
--
--   - This implicit permission is documented here so a future maintainer
--     reading mig 050's Shape 2 alone doesn't misread it as blocking the
--     workspace_id NULL transition. The Shape 2 trigger comment at mig
--     050:38-41 says "with every other column unchanged" — but
--     `workspace_id` IS another column and the trigger silently allows it
--     to change. The CHECK at row level enforces the both-NULL invariant.
--
-- =============================================================
-- Class I — workspace_member_actions service_role SELECT GRANT
-- =============================================================
--
-- Mig 063_workspace_member_actions (`063:80-81`) explicitly REVOKEs
-- service_role's SELECT (alongside INSERT/UPDATE/DELETE) per the design
-- comment at 063:72-75 ("all reads route through
-- list_workspace_member_actions SECURITY DEFINER RPC"). The integration
-- test `workspace-member-actions.integration.test.ts:101-105`, however,
-- reads the table directly via service-role to verify AFTER-trigger row
-- emission shape — the RPC paginates and filters, masking trigger-emission
-- semantics behind RPC contract. The PR that added the table and its
-- integration test left this internal contradiction unresolved.
--
-- Sibling WORM tables (`audit_byok_use` mig 037, `audit_github_token_use`
-- mig 036) never REVOKE service_role SELECT in the first place — they are
-- SELECTable by default and verification + admin tooling uses that path.
-- `workspace_member_actions`'s explicit REVOKE was the design outlier.
--
-- Fix shape: single additive GRANT — SELECT only. INSERT/UPDATE/DELETE
-- remain blocked by both the explicit REVOKE in mig 063:80 AND by the WORM
-- triggers (`workspace_member_actions_no_update`, `_no_delete`,
-- mig 063:129+). Post-mig 064 the table's privilege shape matches
-- `audit_byok_use` exactly: read-only direct SELECT for verification + admin,
-- writes only through the AFTER-trigger that fires on `workspace_members`
-- changes.
--
-- =============================================================
-- Part 1 — Class H repair: anonymise_scope_grants
-- =============================================================

CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- Single UPDATE: founder_id non-NULL → NULL AND workspace_id non-NULL →
  -- NULL. Both transitions satisfy mig 059's CHECK constraint
  -- (scope_grants_workspace_id_check) which requires either both columns
  -- NULL or both NOT NULL. Every other column is unchanged, so the row
  -- matches the trigger's "Shape 2" structural check (founder_id NULL
  -- transition + 6 named columns unchanged) and the trigger returns NEW
  -- without raising. No GUC required.
  UPDATE public.scope_grants
     SET founder_id = NULL,
         workspace_id = NULL
   WHERE founder_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

-- REVOKE + GRANT are idempotent and identical to mig 050:94-97; restated
-- here so a reader sees the complete invocation contract without cross-
-- referencing the predecessor migration.
REVOKE ALL ON FUNCTION public.anonymise_scope_grants(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_scope_grants(uuid)
  TO service_role;

-- =============================================================
-- Part 2 — Class I repair: workspace_member_actions service_role SELECT
-- =============================================================

GRANT SELECT ON public.workspace_member_actions TO service_role;
