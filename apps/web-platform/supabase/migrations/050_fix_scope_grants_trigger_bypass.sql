-- 050_fix_scope_grants_trigger_bypass.sql
-- PR-G (#3947) — Replace migration 048's scope_grants WORM trigger bypass
-- with structural shape detection.
--
-- Migration 048 originally shipped a GUC-gated bypass with a
-- `current_user = 'service_role'` role check, mirroring migrations 043
-- and 044. PR #3984 (the PR-G integration test) revealed that pattern
-- is silently always-false when an INVOKER trigger fires inside a
-- SECURITY DEFINER function — `current_user` resolves to the function
-- owner (`postgres`), not the PostgREST-set caller role. See
-- knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-
-- check-fails-under-postgrest-routing.md.
--
-- Migration 048's file was edited mid-PR but `run-migrations.sh` skips
-- already-applied filenames, so dev DB still has the broken version.
-- This follow-up migration uses `CREATE OR REPLACE FUNCTION` to replace
-- both `scope_grants_no_mutate()` and `anonymise_scope_grants(uuid)`
-- with the structural-shape variants that work under PostgREST routing.
--
-- On prd at merge time, 048 applies fresh with the corrected content;
-- 050 then runs as a no-op (CREATE OR REPLACE with identical bodies).
-- On dev, 048 was already applied with broken bodies — 050 replaces
-- them. Idempotent on re-runs.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SECURITY DEFINER
-- fn pins SET search_path = public, pg_temp.

CREATE OR REPLACE FUNCTION public.scope_grants_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- DELETE: always rejected. Use anonymise_scope_grants for Art. 17 cascade.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'scope_grants is append-only; use anonymise_scope_grants for Art. 17 cascade' USING ERRCODE = 'P0001';
  END IF;

  -- Shape 2: Art. 17 anonymise — founder_id non-NULL → NULL with every
  -- other column unchanged. Recognized by structural shape rather than
  -- a GUC + role gate. See learning
  -- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md.
  IF OLD.founder_id IS NOT NULL
     AND NEW.founder_id IS NULL
     AND NOT (OLD.action_class IS DISTINCT FROM NEW.action_class)
     AND NOT (OLD.tier IS DISTINCT FROM NEW.tier)
     AND NOT (OLD.granted_at IS DISTINCT FROM NEW.granted_at)
     AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
     AND NOT (OLD.revoked_at IS DISTINCT FROM NEW.revoked_at)
     AND NOT (OLD.revoked_reason IS DISTINCT FROM NEW.revoked_reason)
  THEN
    RETURN NEW;
  END IF;

  -- Shape 1: revoke flip — only revoked_at / revoked_reason transition
  -- from NULL to non-NULL is permitted; all other columns must be
  -- unchanged.
  IF OLD.founder_id IS DISTINCT FROM NEW.founder_id
     OR OLD.action_class IS DISTINCT FROM NEW.action_class
     OR OLD.tier IS DISTINCT FROM NEW.tier
     OR OLD.granted_at IS DISTINCT FROM NEW.granted_at
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
     OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at)
     OR (OLD.revoked_reason IS NOT NULL AND NEW.revoked_reason IS DISTINCT FROM OLD.revoked_reason)
  THEN
    RAISE EXCEPTION 'scope_grants is append-only; only NULL->value revocation is permitted' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.scope_grants_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- Single UPDATE: founder_id non-NULL → NULL. Every other column is
  -- unchanged, so the row matches the trigger's "Shape 2" structural
  -- check and bypass returns NEW without raising. No GUC required.
  UPDATE public.scope_grants
     SET founder_id = NULL
   WHERE founder_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_scope_grants(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_scope_grants(uuid)
  TO service_role;
