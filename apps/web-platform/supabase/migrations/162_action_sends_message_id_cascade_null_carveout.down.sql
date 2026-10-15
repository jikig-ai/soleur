-- 162_action_sends_message_id_cascade_null_carveout.down.sql
-- Reverse 162: restore the mig-087 WORM body (no Art-17 carve-out), the
-- 064 12-column statement trigger, the NOT NULL + NO ACTION FK, and the
-- pre-162 anonymise_action_sends body.
-- WARNING: reverting reinstates the defect — auth.admin.deleteUser 500s
-- again for any user with an action_sends row (issue #10254). Only run
-- this to roll back a broken 162 deploy.
-- PREREQUISITE: `ALTER COLUMN message_id SET NOT NULL` fails while any
-- NULL message_id rows exist — reconcile or accept data loss on those
-- rows before applying.

DROP TRIGGER IF EXISTS action_sends_message_id_guard ON public.action_sends;
DROP TRIGGER IF EXISTS action_sends_no_update ON public.action_sends;
CREATE TRIGGER action_sends_no_update
  BEFORE UPDATE OF
    id,
    user_id,
    message_id,
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

CREATE OR REPLACE FUNCTION public.action_sends_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Art-17 erasure bypass (anonymise_action_sends): privilege-free GUC.
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'action_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.action_sends_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.action_sends DROP CONSTRAINT action_sends_message_id_fkey;
ALTER TABLE public.action_sends
  ADD CONSTRAINT action_sends_message_id_fkey
  FOREIGN KEY (message_id) REFERENCES public.messages(id);
ALTER TABLE public.action_sends ALTER COLUMN message_id SET NOT NULL;

CREATE OR REPLACE FUNCTION public.anonymise_action_sends(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  affected integer;
BEGIN
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
         recipient_id_hash = '__anonymised__'
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';

  RETURN affected;
END;
$fn$;
