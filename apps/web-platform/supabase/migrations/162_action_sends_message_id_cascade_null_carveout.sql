-- 162_action_sends_message_id_cascade_null_carveout.sql
--
-- #10254 / Art-17 erasure blocker: auth.admin.deleteUser 500s for every
-- user holding an action_sends row.
--
-- Root cause: action_sends.message_id is
-- `NOT NULL REFERENCES public.messages(id)` — a bare REFERENCES, i.e.
-- NO ACTION (mig 051:103). Deleting a user cascades through
-- `messages.user_id -> users` ON DELETE CASCADE (mig 001 + 046), the
-- message delete hits action_sends_message_id_fkey, and the erasure saga
-- aborts inside GoTrue's transaction — where no app.worm_bypass GUC can
-- be set, so the anonymise RPC's privilege path cannot reach it.
-- Verified live on dev: `ERROR: violates foreign key constraint
-- "action_sends_message_id_fkey"` (tenant-integration run 38469450080).
--
-- Ruled fix (CTO ruling on #10254, 2026-10-15 — option (b), mirrors the
-- 066 -> 160 -> 161 precedent family):
--
--   1. FK reshape — message_id nullable + ON DELETE SET NULL. message_id
--      is pure linkage: the row snapshots everything it reads
--      (per_send_body_sha256, template_hash, action_class, tier_at_send,
--      grant_id), so NULL is a complete de-link, not data loss.
--   2. Trigger reshape — action_sends_no_update keeps the 064
--      statement-level BEFORE UPDATE OF form minus message_id (11
--      columns); a NEW row-level BEFORE UPDATE OF message_id trigger
--      fires through action_sends_no_mutate. action_sends_no_delete is
--      untouched — DELETE stays universally blocked.
--   3. Carve-out in action_sends_no_mutate (161 shape): admit exactly
--      `OLD.message_id IS NOT NULL AND NEW.message_id IS NULL AND
--      (to_jsonb(NEW) - 'message_id') = (to_jsonb(OLD) - 'message_id')
--      AND NOT EXISTS (SELECT 1 FROM public.messages WHERE id =
--      OLD.message_id)` — the RI action fires after the parent messages
--      row is removed, so the cascade passes while a direct
--      `UPDATE ... SET message_id = NULL` against a row whose message
--      still exists is rejected (a privileged role holding UPDATE cannot
--      forge an erasure on a live anchor). The to_jsonb-minus compare is
--      drift-proof: a future ADD COLUMN cannot silently widen the gate.
--   4. Hardening (one line) — anonymise_action_sends also sets
--      message_id = NULL inside its existing app.worm_bypass window:
--      eager de-link as recommended hardening, not the mechanism.
--
-- TG_LEVEL gate is load-bearing: action_sends_no_mutate serves BOTH the
-- statement-level triggers and the new row-level trigger. Under a
-- statement firing OLD/NEW are unassigned records, so the carve-out
-- branch MUST be guarded by `TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW'` or
-- it raises `record "old" is not assigned yet` instead of clean P0001.
--
-- Cross-path semantics (ruled): ANY messages deletion — user cascade,
-- conversation cascade, or direct — fires the SET NULL and is admitted
-- because the parent is already gone. When the message is gone, the
-- linkage releases.
--
-- Lock form: NOT VALID + VALIDATE CONSTRAINT. DROP NOT NULL and DROP
-- CONSTRAINT already hold ACCESS EXCLUSIVE on action_sends inside this
-- migration transaction, so the child's lock footprint is identical
-- either way — the win is on the PARENT messages, where a validating
-- ADD CONSTRAINT would hold SHARE ROW EXCLUSIVE (write-blocking) for
-- the whole child scan while NOT VALID takes it momentarily and
-- VALIDATE CONSTRAINT runs under ROW SHARE. Canonical zero-downtime
-- default — do not "simplify" back to a validating ADD CONSTRAINT.

-- Precondition per lint-migration-fk-preconditions.sh (cross-file
-- REFERENCES target must exist).
DO $$
BEGIN
  IF to_regclass('public.action_sends') IS NULL
     OR to_regclass('public.messages') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 162 precondition failed: public.action_sends/public.messages missing',
      DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md';
  END IF;
END $$;

-- message_id is nullable from here on: the sole write boundary
-- (server/action-sends/write-action-send.ts) always supplies message.id;
-- NULL means de-linked post-erasure only. action_sends_message_unique
-- treats NULLs as distinct, so post-erasure rows coexist.
ALTER TABLE public.action_sends ALTER COLUMN message_id DROP NOT NULL;
ALTER TABLE public.action_sends DROP CONSTRAINT action_sends_message_id_fkey;
ALTER TABLE public.action_sends
  ADD CONSTRAINT action_sends_message_id_fkey
  FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL
  NOT VALID;
ALTER TABLE public.action_sends
  VALIDATE CONSTRAINT action_sends_message_id_fkey;

DROP TRIGGER IF EXISTS action_sends_no_update ON public.action_sends;
CREATE TRIGGER action_sends_no_update
  BEFORE UPDATE OF
    id,
    user_id,
    action_class,
    tier_at_send,
    template_hash,
    per_send_body_sha256,
    recipient_id_hash,
    clicked_at,
    confirmed_typed,
    approval_signature_sha256,
    grant_id
  ON public.action_sends
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.action_sends_no_mutate();

DROP TRIGGER IF EXISTS action_sends_message_id_guard ON public.action_sends;
CREATE TRIGGER action_sends_message_id_guard
  BEFORE UPDATE OF message_id ON public.action_sends
  FOR EACH ROW
  EXECUTE FUNCTION public.action_sends_no_mutate();

CREATE OR REPLACE FUNCTION public.action_sends_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Privileged bypass (anonymise_action_sends sets this GUC).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- DELETE: universally blocked — the send ledger is append-only.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'action_sends is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE (row-level only): allow only the Art-17 de-link transition the
  -- message_id ON DELETE SET NULL FK performs. TG_LEVEL='ROW' is required
  -- — this function also serves the statement-level triggers, where
  -- OLD/NEW are unassigned records; the to_jsonb-minus compare is
  -- drift-proof (a future ADD COLUMN cannot silently widen the gate) and
  -- the NOT EXISTS conjunct binds the transition to an actually-deleted
  -- parent: the cascade fires it after the messages row is gone; a
  -- direct UPDATE on a live message's send row cannot satisfy it. A
  -- dangling non-NULL message_id (only reachable via an RI-bypassed
  -- delete) can also be nulled — acceptable: linkage was already
  -- destroyed out-of-band and the gate can never re-link (NEW.message_id
  -- IS NULL required).
  IF TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW' THEN
    IF OLD.message_id IS NOT NULL
       AND NEW.message_id IS NULL
       AND (to_jsonb(NEW) - 'message_id') = (to_jsonb(OLD) - 'message_id')
       AND NOT EXISTS (SELECT 1 FROM public.messages WHERE id = OLD.message_id)
    THEN
      RETURN NEW;  -- Art-17 SET NULL cascade carve-out (mirrors mig 161).
    END IF;
    RAISE EXCEPTION 'action_sends is append-only (WORM); UPDATE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  RAISE EXCEPTION 'action_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.action_sends_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.action_sends_no_mutate() IS
  'WORM gate for action_sends. Allows UPDATE only via the app.worm_bypass '
  'bypass (anonymise_action_sends) or the Art-17 SET NULL cascade '
  'transition (message_id NOT NULL -> NULL, all other columns '
  'structurally unchanged, parent messages row already gone — NOT EXISTS '
  'initiator check, mig 161 shape). DELETE is universally blocked.';

COMMENT ON COLUMN public.action_sends.message_id IS
  'NULL after erasure or any parent-messages deletion: ON DELETE SET '
  'NULL de-links the WORM ledger row (mig 162). NULL = de-linked state, '
  'not a data gap; consumers must tolerate it (all .eq filters simply '
  'never match).';

-- Hardening: anonymise_action_sends also clears message_id inside the
-- existing app.worm_bypass window — eager de-link, not the mechanism.
-- Body is the 087 body plus one column in the UPDATE's SET list; auth
-- checks and the GUC re-arm are unchanged.
CREATE OR REPLACE FUNCTION public.anonymise_action_sends(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  affected integer;
BEGIN
  -- Authorisation:
  --   * Service-role callers (account-delete.ts) — auth.uid() is NULL,
  --     current_user = 'service_role' (or 'postgres' in local dev).
  --   * Self-DSAR callers (founder-initiated path) — auth.uid() = p_user_id.
  IF auth.uid() IS NULL THEN
    IF current_user NOT IN ('service_role', 'postgres') THEN
      RAISE EXCEPTION 'anonymise_action_sends: caller not authorised'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF auth.uid() <> p_user_id THEN
      RAISE EXCEPTION 'anonymise_action_sends: self-call only for authenticated callers'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.action_sends
     SET user_id           = NULL,
         recipient_id_hash = '__anonymised__',
         message_id        = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';

  RETURN affected;
END;
$fn$;
