-- Migration 066: WORM-trigger carve-out for Art-17 SET NULL cascade.
--
-- Ref     #4356 (post-mig-065 cascade still red — audit_byok_use_no_update
--                trigger fires on the SET NULL UPDATE that mig 065 Part 2
--                introduced).
--
-- =============================================================
-- Diagnosis
-- =============================================================
--
-- Mig 065 Part 2 downgraded audit_byok_use.founder_id RESTRICT → SET NULL
-- so the Art. 17 auth.users delete cascade could clear the FK reference.
-- But mig 037's WORM trigger (`audit_byok_use_no_update`) fires for ANY
-- UPDATE — including the FK-cascade-induced UPDATE that sets founder_id
-- to NULL — and unconditionally RAISEs P0001. The cascade aborts mid-way
-- and the entire auth.admin.deleteUser call fails with the opaque
-- "Database error deleting user" message.
--
-- Verified via:
--   DELETE FROM auth.users WHERE id = '<test-user-id>';
--   ERROR: audit_byok_use is append-only (WORM)
--
-- =============================================================
-- Repair
-- =============================================================
--
-- Convert the statement-level WORM trigger to a row-level trigger with a
-- single carve-out: allow UPDATEs whose ONLY effect is setting
-- founder_id NOT NULL → NULL while leaving every other column unchanged.
-- This is the Art. 17 anonymization shape — semantically a one-shot
-- transition, never reversible (no UPDATE can transition NULL → non-NULL
-- because INSERT requires NOT NULL at the application layer, only the
-- column constraint allows NULL).
--
-- Production write_byok_audit (mig 061) is INSERT-only; mig 066 does not
-- affect it. Defense-in-depth: REVOKE ALL on the table for non-service-role
-- (mig 037) + WORM trigger together. The trigger no longer raises on the
-- specific anonymization UPDATE shape; all other UPDATE shapes still RAISE.
-- DELETE remains universally blocked.

CREATE OR REPLACE FUNCTION public.audit_byok_use_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- DELETE: universally blocked.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'audit_byok_use is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE: allow only the Art-17 anonymization transition (founder_id
  -- non-NULL → NULL with every other column unchanged). Mig 065 SET NULL
  -- cascade produces exactly this shape; any other UPDATE shape RAISEs.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.founder_id IS NOT NULL
       AND NEW.founder_id IS NULL
       AND NEW.id              IS NOT DISTINCT FROM OLD.id
       AND NEW.invocation_id   IS NOT DISTINCT FROM OLD.invocation_id
       AND NEW.workspace_id    IS NOT DISTINCT FROM OLD.workspace_id
       AND NEW.agent_role      IS NOT DISTINCT FROM OLD.agent_role
       AND NEW.ts              IS NOT DISTINCT FROM OLD.ts
       AND NEW.token_count     IS NOT DISTINCT FROM OLD.token_count
       AND NEW.unit_cost_cents IS NOT DISTINCT FROM OLD.unit_cost_cents
       AND NEW.created_at      IS NOT DISTINCT FROM OLD.created_at
    THEN
      RETURN NEW;  -- Art-17 anonymization carve-out
    END IF;
    RAISE EXCEPTION 'audit_byok_use is append-only (WORM); UPDATE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.audit_byok_use_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- Replace the STATEMENT triggers with FOR EACH ROW triggers so the
-- function has access to OLD/NEW for the carve-out check.
DROP TRIGGER IF EXISTS audit_byok_use_no_update ON public.audit_byok_use;
CREATE TRIGGER audit_byok_use_no_update
  BEFORE UPDATE ON public.audit_byok_use
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_byok_use_no_mutate();

DROP TRIGGER IF EXISTS audit_byok_use_no_delete ON public.audit_byok_use;
CREATE TRIGGER audit_byok_use_no_delete
  BEFORE DELETE ON public.audit_byok_use
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_byok_use_no_mutate();
