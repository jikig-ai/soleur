-- 104_outbound_email.sql
-- Agent-native outbound email (#5325, pilot slice).
--
-- Net-new schema is ONLY the email_suppression table. The send-audit +
-- approval binding reuses public.action_sends (migration 051): an outbound
-- email send records an action_sends row with action_class = 'marketing.outreach'
-- (admissible — action_sends.action_class has only an enum-ABSENCE CHECK
-- `!~ '^(payment|legal|auth)\.'`; no enum/migration change needed), bound to
-- per_send_body_sha256 + approval_signature_sha256 + grant_id. There is NO
-- outbound_sends table and NO bare approved_at.
--
-- email_suppression is a per-founder SET (not a log): one row per
-- (owner_id, recipient_hash), upserted ON CONFLICT DO NOTHING. Suppression is
-- MONOTONIC — added on opt-out/decline, never removed (no un-suppress RPC).
-- CLO condition C5 requires it honored permanently across campaigns, so the
-- send chokepoint refuses any send to a suppressed recipient.
--
-- recipient_hash is HMAC-SHA-256(EMAIL_HASH_PEPPER, normalize(email)) computed
-- in the application layer (see apps/web-platform/server/email-triage/outbound-compliance.ts).
-- It MUST be deterministic (fixed app-wide pepper, NOT a per-row/random salt) —
-- a random salt would break the cross-campaign suppression lookup, re-mailing a
-- suppressed contact (the exact CAN-SPAM/GDPR incident this table prevents).
--
-- Patterns mirror migration 051 (action_sends) verbatim:
--   * owner-select + owner-insert RLS, no FOR ALL USING
--     (learning 2026-04-18-rls-for-all-using-applies-to-writes.md)
--   * SECURITY DEFINER RPCs pin SET search_path = public, pg_temp and qualify
--     every relation (cq-pg-security-definer-search-path-pin-pg-temp)
--   * Art-17 erasure RPC mirrors anonymise_action_sends
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO CREATE INDEX
-- CONCURRENTLY. Per Kieran P1-4 (mig 051): NO outer BEGIN/COMMIT (runner wraps).

-- ============================================================================
-- email_suppression — per-founder permanent suppression set
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.email_suppression (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULLABLE to admit Art-17 anonymisation. ON DELETE RESTRICT prevents
  -- accidental user-row deletion before anonymise_email_suppression runs.
  owner_id       uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  -- HMAC-SHA-256(pepper, normalize(email)) — deterministic, app-computed.
  recipient_hash text NOT NULL CHECK (length(recipient_hash) BETWEEN 1 AND 128),
  -- Why the recipient is suppressed: opt-out reply, hard decline, bounce.
  reason         text NOT NULL CHECK (reason IN ('opt_out', 'decline', 'bounce', 'manual')),
  added_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.email_suppression IS
  'Per-founder permanent email suppression set (#5325). CLO C5 evidence: '
  'recipients who opted out / declined cold outreach, honored across all '
  'campaigns. Monotonic — rows are added, never removed (no un-suppress RPC). '
  'recipient_hash is HMAC-SHA-256(EMAIL_HASH_PEPPER, normalize(email)); '
  'Art-17 erasure via anonymise_email_suppression.';

-- One suppression row per (founder, recipient). Upsert target. NULL owner_id
-- (post-anonymisation) rows are treated as distinct by the UNIQUE index
-- (Postgres NULLs-distinct semantics) so Art-17 tombstones never collide.
CREATE UNIQUE INDEX IF NOT EXISTS email_suppression_owner_recipient_unique
  ON public.email_suppression (owner_id, recipient_hash);

-- RLS — owner-select + owner-insert only; writes go through the SECURITY
-- DEFINER upsert RPC. No FOR ALL USING (2026-04-18-rls-for-all-using).
ALTER TABLE public.email_suppression ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS email_suppression_owner_select ON public.email_suppression;
CREATE POLICY email_suppression_owner_select ON public.email_suppression
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid());

-- Direct INSERT/UPDATE/DELETE from authenticated is revoked; the upsert RPC is
-- the only write path. (No INSERT policy — the RPC is SECURITY DEFINER.)
REVOKE INSERT, UPDATE, DELETE ON public.email_suppression FROM authenticated;

-- ============================================================================
-- suppress_recipient — idempotent upsert (monotonic add). auth.uid() owner-pin.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.suppress_recipient(
  p_recipient_hash text,
  p_reason         text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_id uuid := auth.uid();
  v_id       uuid;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;
  IF p_reason NOT IN ('opt_out', 'decline', 'bounce', 'manual') THEN
    RAISE EXCEPTION 'invalid suppression reason: %', p_reason USING ERRCODE = '22P02';
  END IF;

  -- Monotonic: first suppression wins; re-suppression is a no-op that returns
  -- the existing row id. No un-suppress path exists.
  INSERT INTO public.email_suppression (owner_id, recipient_hash, reason)
       VALUES (v_owner_id, p_recipient_hash, p_reason)
  ON CONFLICT (owner_id, recipient_hash) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id
      FROM public.email_suppression
     WHERE owner_id = v_owner_id AND recipient_hash = p_recipient_hash;
  END IF;

  RETURN v_id;
END;
$$;

-- REVOKE from authenticated too (then re-GRANT below): Supabase's
-- ALTER DEFAULT PRIVILEGES grants EXECUTE to authenticated by default, so the
-- named-role REVOKE is load-bearing (2026-05-06-supabase-default-privileges-
-- defeat-revoke-from-public.md). Mirrors mig 051 grant_action_class.
REVOKE ALL ON FUNCTION public.suppress_recipient(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.suppress_recipient(text, text)
  TO authenticated;

COMMENT ON FUNCTION public.suppress_recipient(text, text) IS
  'Idempotent monotonic upsert into email_suppression for the calling founder '
  '(auth.uid()). ON CONFLICT DO NOTHING — re-suppression returns the existing '
  'row. No un-suppress RPC exists (suppression is permanent). #5325.';

-- ============================================================================
-- is_recipient_suppressed — send-time precondition check. auth.uid() owner-pin.
-- The chokepoint calls this immediately before recording the send (in-txn
-- recheck closes the check-then-send TOCTOU; suppression is monotonic so a
-- late add only ever flips false→true, never the reverse).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.is_recipient_suppressed(
  p_recipient_hash text
) RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_id uuid := auth.uid();
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.email_suppression
     WHERE owner_id = v_owner_id AND recipient_hash = p_recipient_hash
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_recipient_suppressed(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_recipient_suppressed(text)
  TO authenticated;

COMMENT ON FUNCTION public.is_recipient_suppressed(text) IS
  'Send-time precondition: true if the calling founder (auth.uid()) has '
  'suppressed recipient_hash. The outbound chokepoint refuses to send when '
  'true. #5325.';

-- ============================================================================
-- anonymise_email_suppression — Art-17 erasure. Mirrors anonymise_action_sends
-- (mig 051). Called by server/account-delete.ts BEFORE auth.admin.deleteUser.
-- Tombstones the founder's rows (owner_id NULL, recipient_hash scrubbed) rather
-- than deleting, keeping the table append-only-shaped.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.anonymise_email_suppression(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
BEGIN
  -- Authorisation: service-role callers (account-delete.ts; auth.uid() NULL,
  -- current_user service_role/postgres) OR self-DSAR (auth.uid() = p_user_id).
  IF auth.uid() IS NULL THEN
    IF current_user NOT IN ('service_role', 'postgres') THEN
      RAISE EXCEPTION 'anonymise_email_suppression: caller not authorised'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF auth.uid() <> p_user_id THEN
      RAISE EXCEPTION 'anonymise_email_suppression: self-call only for authenticated callers'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- recipient_hash scrubbed to a per-row-unique tombstone so the UNIQUE index
  -- never collides across a founder's multiple suppressions (NULL owner_id is
  -- already NULLs-distinct, but the scrub removes the residual HMAC identifier).
  UPDATE public.email_suppression
     SET owner_id       = NULL,
         recipient_hash = '__anonymised__:' || id::text
   WHERE owner_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;

  RETURN affected;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_email_suppression(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_email_suppression(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.anonymise_email_suppression(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.anonymise_email_suppression(uuid) IS
  'Art. 17 erasure: tombstones email_suppression rows for the given founder '
  '(owner_id NULL, recipient_hash scrubbed). Called by account-delete.ts BEFORE '
  'auth.admin.deleteUser. Pattern source: mig 051 anonymise_action_sends. #5325.';
