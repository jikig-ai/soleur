-- 161_audit_github_token_use_cascade_null_carveout.sql
--
-- #10229 / Art-17 erasure defect (latent): auth.admin.deleteUser fails
-- for every user holding an audit_github_token_use row once such rows
-- exist (the record_github_token_use INSERT path lands post-#10095).
--
-- Root cause: audit_github_token_use.founder_id is `ON DELETE SET NULL`
-- by design (mig 052 — the audit row survives erasure with founder_id=NULL
-- for Art. 5(2) accountability). But the WORM gate
-- audit_github_token_use_no_mutate() (087 body) raises P0001 on EVERY
-- UPDATE/DELETE outside app.worm_bypass — including the FK cascade's
-- internal `UPDATE ... SET founder_id = NULL`, which GoTrue's delete
-- transaction cannot set the GUC for. The erasure saga aborts: 23503
-- under a drifted RESTRICT shape, P0001 under the correct SET NULL shape.
--
-- The explicit anonymise path (anonymise_audit_github_token_use, GUC
-- bypass) masks this only when it SUCCEEDS — tearDownTenantUser classes
-- it `set-null` (warn-and-continue), so an RPC failure followed by a
-- deleteUser still hits the wedge. The carve-out closes the gap: the
-- cascade's own transition is admitted directly.
--
-- Fix shape: the Art-17 anonymization carve-out proven by
-- dsar_export_audit_pii_no_mutate (mig 160) — allow an UPDATE whose only
-- change is `founder_id: NOT NULL -> NULL` (the exact transition the SET
-- NULL cascade performs); every other column must be structurally
-- unchanged, so the carve-out cannot be used to mutate the audit trail.
-- DELETE stays universally blocked; app.worm_bypass stays the privileged
-- bypass for the anonymise RPC (which also nulls repo_full_name — the
-- bypass branch, not the carve-out, admits that two-column change).
--
-- Initiator check (160's strengthening of the 066 precedent): the
-- carve-out also requires that OLD.founder_id no longer resolve to a
-- live auth.users row. RI actions fire after the parent row is removed,
-- so the cascade passes — while a direct `UPDATE ... SET founder_id =
-- NULL` from a privileged role (service_role bypasses the table's
-- zero-policy RLS) against a LIVE user's audit row is rejected. Without
-- it the gate would let any caller holding UPDATE permanently de-link
-- Art. 5(2) attribution. A dangling non-NULL founder_id (only reachable
-- via an RI-bypassed delete) can also be nulled — acceptable:
-- attribution was already destroyed out-of-band and the gate can never
-- re-attribute (NEW.founder_id IS NULL required).
--
-- SECURITY DEFINER change vs the 087 INVOKER body: the initiator check
-- must read auth.users identically under every firing context (the
-- cascade runs under whichever role deleted the parent); mirroring 160's
-- DEFINER keeps the check deterministic. search_path pin is unchanged.

CREATE OR REPLACE FUNCTION public.audit_github_token_use_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Privileged bypass (anonymise_audit_github_token_use sets this GUC).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- DELETE: universally blocked — the audit trail is append-only.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'audit_github_token_use is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE: allow only the Art-17 erasure transition the founder_id
  -- ON DELETE SET NULL FK performs. Drift-proof check — every column
  -- except founder_id must be unchanged, so this gate cannot be used to
  -- edit audit content. The NOT EXISTS conjunct binds the transition to
  -- an actually-deleted parent: the cascade fires it after the auth.users
  -- row is gone; a direct UPDATE on a live user's row cannot satisfy it.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.founder_id IS NOT NULL
       AND NEW.founder_id IS NULL
       AND (to_jsonb(NEW) - 'founder_id') = (to_jsonb(OLD) - 'founder_id')
       AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = OLD.founder_id)
    THEN
      RETURN NEW;  -- Art-17 anonymization carve-out (mirrors mig 160).
    END IF;
    RAISE EXCEPTION 'audit_github_token_use is append-only (WORM); UPDATE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.audit_github_token_use_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.audit_github_token_use_no_mutate() IS
  'WORM gate for audit_github_token_use. Allows UPDATE only via the '
  'app.worm_bypass bypass (the anonymise RPC) or the Art-17 SET NULL '
  'cascade transition (founder_id NOT NULL -> NULL, all other columns '
  'structurally unchanged, parent auth.users row already gone). DELETE '
  'is universally blocked.';

COMMENT ON COLUMN public.audit_github_token_use.founder_id IS
  'NULL after Art-17 erasure: the auth-delete cascade nulls this FK '
  '(ON DELETE SET NULL, mig 052 — the audit row survives anonymised for '
  'Art. 5(2) accountability). Analytics joins must treat NULL as the '
  'anonymised state, not a data gap.';
