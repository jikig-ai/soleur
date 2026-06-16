-- 104_outbound_email.sql
-- Agent-native outbound email (#5325, pilot slice).
--
-- Net-new schema is TWO tables: email_suppression (per-founder suppression set)
-- and outbound_sends (per-send WORM cold-send audit). Per ADR-060 (CTO decision),
-- outbound_sends is a DEDICATED table, NOT a reuse of public.action_sends: that
-- table's message_id is a NOT NULL FK to public.messages with UNIQUE(message_id),
-- built for the founder-clicks-Send-on-a-draft path, and the agent tool path has
-- no messages.id at tool-exec time. outbound_sends mirrors the action_sends WORM
-- posture (append-only trigger, owner-RLS, app.worm_bypass-gated anonymise) but
-- has no messages FK. There is NO bare approved_at — approval is body-hash-bound
-- (approved_body_sha256 recomputed at the chokepoint). (This supersedes the plan's
-- "reuse action_sends / no outbound_sends table" P0-1, whose premise the code
-- falsified; see ADR-060.)
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

-- Cross-file FK precondition (lint-migration-fk-preconditions; learning
-- 2026-05-22-schema-vs-ledger-drift-on-dev-supabase): both new tables FK
-- public.users, so assert it exists before this migration runs.
DO $$ BEGIN
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.users must exist before 104';
  END IF;
END $$;

-- ============================================================================
-- email_suppression — per-founder permanent suppression set
-- ============================================================================
-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA 2026-06-15-outbound-email-authority-lia.md; Art.30 PA-28)
-- RETENTION: permanent / monotonic — retention IS the opt-out guarantee (Art. 17 via anonymise_email_suppression; no un-suppress)
CREATE TABLE IF NOT EXISTS public.email_suppression (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULLABLE to admit Art-17 anonymisation. ON DELETE RESTRICT prevents
  -- accidental user-row deletion before anonymise_email_suppression runs.
  owner_id       uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT, -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))
  -- HMAC-SHA-256(pepper, normalize(email)) — deterministic keyed pseudonym (Art. 32); plaintext address never stored.
  recipient_hash text NOT NULL CHECK (length(recipient_hash) BETWEEN 1 AND 128), -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); pseudonymised recipient)
  -- Why the recipient is suppressed: opt-out reply, hard decline, bounce.
  reason         text NOT NULL CHECK (reason IN ('opt_out', 'decline', 'bounce', 'manual')), -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))
  added_at       timestamptz NOT NULL DEFAULT now() -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))
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
  -- SERVICE-ROLE ONLY (account-delete.ts). No self-service erasure path: the
  -- suppression set is CLO C5 compliance evidence (who opted out / declined),
  -- and a founder self-wiping it could lead to re-mailing opted-out recipients
  -- (CAN-SPAM/GDPR violation). The only legitimate Art-17 trigger is full
  -- account deletion, which runs as service_role BEFORE auth.admin.deleteUser
  -- (security review #5325; same posture as anonymise_outbound_sends).
  IF current_user NOT IN ('service_role', 'postgres') THEN
    RAISE EXCEPTION 'anonymise_email_suppression: service-role only (no self-service erasure)'
      USING ERRCODE = '42501';
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

-- service_role-only: NOT granted to authenticated (no self-service erasure).
REVOKE ALL ON FUNCTION public.anonymise_email_suppression(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_email_suppression(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_email_suppression(uuid) IS
  'Art. 17 erasure: tombstones email_suppression rows for the given founder '
  '(owner_id NULL, recipient_hash scrubbed). Called by account-delete.ts BEFORE '
  'auth.admin.deleteUser. Pattern source: mig 051 anonymise_action_sends. #5325.';

-- ============================================================================
-- outbound_sends — WORM audit of every cold-outbound send (#5325).
--
-- ADR-060 decision (CTO, overturning the plan's "no outbound_sends table"
-- rule whose premise — clean action_sends reuse — was falsified at /work):
-- action_sends.message_id is a NOT NULL FK to public.messages with
-- UNIQUE(message_id), built for the founder-clicks-Send-on-a-draft path; the
-- agent tool path has no messages.id at tool-exec time, so action_sends cannot
-- be reused for agent-initiated sends. outbound_sends is a dedicated WORM table
-- NOT FK'd to messages, mirroring the action_sends posture (mig 051):
--   * append-only (BEFORE UPDATE/DELETE pure-reject trigger)
--   * owner-select + owner-insert RLS, no FOR ALL USING
--   * writes ONLY via the SECURITY DEFINER record_outbound_send RPC
--   * Art-17 erasure via anonymise_outbound_sends (mirrors anonymise_action_sends)
-- GDPR Art. 5(2) accountability for cold outreach to non-consenting third
-- parties: a durable, tamper-evident, recipient-bound (HMAC), body-bound
-- (sha256) send record. approved_body_sha256 is the hash the human approved at
-- the gated-tier review; per_send_body_sha256 is recomputed by the chokepoint
-- at send time (outbound.ts rejects on mismatch — body-binding).
-- ============================================================================
-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA 2026-06-15-outbound-email-authority-lia.md; Art.30 PA-28)
-- RETENTION: append-only WORM; accountability period (Art. 5(2)) — Art. 17 via anonymise_outbound_sends (Art. 17(3)(b) override)
CREATE TABLE IF NOT EXISTS public.outbound_sends (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULLABLE to admit Art-17 anonymisation; ON DELETE RESTRICT prevents
  -- user-row deletion before anonymise_outbound_sends runs.
  owner_id              uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT, -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))
  -- HMAC-SHA-256(EMAIL_HASH_PEPPER, normalize(email)) — same keyed hash the
  -- suppression set uses, so an audit row is linkable to a suppression entry.
  recipient_hash        text NOT NULL CHECK (length(recipient_hash) BETWEEN 1 AND 128), -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); pseudonymised recipient)
  -- The body hash the human approved at the gated review (P0-1 body-binding).
  approved_body_sha256  text NOT NULL CHECK (length(approved_body_sha256) BETWEEN 1 AND 128), -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); body never stored, only its hash)
  -- The body hash recomputed by the chokepoint at send time. Equal to
  -- approved_body_sha256 on every legitimate row (the chokepoint throws on
  -- mismatch before Resend); persisted so a later audit can prove equality.
  per_send_body_sha256  text NOT NULL CHECK (length(per_send_body_sha256) BETWEEN 1 AND 128), -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))
  -- Resend message id (the un-rollback-able side effect's receipt). NULL only
  -- if recorded for a send that failed AFTER dispatch — not expected in v1.
  resend_id             text NULL, -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))
  -- Free-text classifier (NOT the typed ActionClass union — this table does not
  -- use action_sends/scope_grants). Enum-ABSENCE CHECK mirrors action_sends so
  -- a locked-domain class can never be recorded here.
  action_class          text NOT NULL DEFAULT 'marketing.outreach'
                          CHECK (action_class !~ '^(payment|legal|auth)\.'),
  sent_at               timestamptz NOT NULL DEFAULT now() -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))
);

COMMENT ON TABLE public.outbound_sends IS
  'Per-send WORM audit of agent cold-outbound email (#5325, ADR-060). Append-only '
  'GDPR Art. 5(2) accountability evidence: recipient_hash (HMAC), '
  'approved_body_sha256 (gated-review approval), per_send_body_sha256 (chokepoint '
  'recompute), resend_id. UPDATE/DELETE rejected by trigger; Art-17 erasure via '
  'anonymise_outbound_sends. NOT FK''d to messages (agent path has no message id).';

-- Pure-reject UPDATE/DELETE trigger (mirror action_sends_no_mutate, mig 051).
CREATE OR REPLACE FUNCTION public.outbound_sends_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- Art-17 erasure bypass: the PRIVILEGE-FREE custom GUC app.worm_bypass (set
  -- with SET LOCAL by anonymise_outbound_sends), NOT session_replication_role.
  -- session_replication_role is superuser-only (PGC_SUSET); on managed Supabase
  -- the postgres role is NOT superuser, so SET session_replication_role raises
  -- 42501 and would abort the account-delete saga at this step → NO account
  -- could be deleted (migration 087 / #4696 fixed exactly this class for the
  -- other WORM tables; 104 must follow it, not the pre-087 mig 051 shape).
  -- At STATEMENT level NEW/OLD are NULL and the return is ignored — the bypass
  -- works by NOT raising; the RETURN is harmless (mirrors action_sends_no_mutate
  -- post-087, which is also FOR EACH STATEMENT).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'outbound_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.outbound_sends_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS outbound_sends_no_update ON public.outbound_sends;
CREATE TRIGGER outbound_sends_no_update
  BEFORE UPDATE ON public.outbound_sends
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.outbound_sends_no_mutate();

DROP TRIGGER IF EXISTS outbound_sends_no_delete ON public.outbound_sends;
CREATE TRIGGER outbound_sends_no_delete
  BEFORE DELETE ON public.outbound_sends
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.outbound_sends_no_mutate();

-- RLS — owner-select + owner-insert; no FOR ALL USING (2026-04-18-rls-for-all-using).
ALTER TABLE public.outbound_sends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS outbound_sends_owner_select ON public.outbound_sends;
CREATE POLICY outbound_sends_owner_select ON public.outbound_sends
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid());

-- Direct writes from authenticated are revoked; the SECURITY DEFINER
-- record_outbound_send RPC is the only write path. (No INSERT policy.)
REVOKE INSERT, UPDATE, DELETE ON public.outbound_sends FROM authenticated;

CREATE INDEX IF NOT EXISTS outbound_sends_owner_sent_idx
  ON public.outbound_sends (owner_id, sent_at DESC);

-- Idempotency / duplicate-send guard (#5325 user-impact review): a UNIQUE on
-- (owner_id, recipient_hash, approved_body_sha256) makes a retry's record fail
-- (23505) — the race-closer behind the chokepoint's pre-send existence check
-- (outbound_send_exists below). For cold 1:1 outreach, re-sending the IDENTICAL
-- approved body to the SAME recipient is the "duplicate cold email" failure the
-- plan's User-Brand Impact section names; a genuine follow-up uses a different
-- body (different hash) and is unaffected. Post-anonymise rows (owner_id NULL)
-- are NULLs-distinct so the tombstone scrub never collides here.
CREATE UNIQUE INDEX IF NOT EXISTS outbound_sends_dedup_unique
  ON public.outbound_sends (owner_id, recipient_hash, approved_body_sha256);

-- ============================================================================
-- outbound_send_exists — pre-send duplicate check. auth.uid() owner-pin.
-- The chokepoint calls this immediately before Resend; if a row already exists
-- for (owner, recipient_hash, approved_body_sha256) it refuses (the human
-- already approved + sent this exact body to this recipient). The UNIQUE index
-- above closes the concurrent-race residual the SELECT cannot.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.outbound_send_exists(
  p_recipient_hash       text,
  p_approved_body_sha256 text
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
    SELECT 1 FROM public.outbound_sends
     WHERE owner_id = v_owner_id
       AND recipient_hash = p_recipient_hash
       AND approved_body_sha256 = p_approved_body_sha256
  );
END;
$$;

REVOKE ALL ON FUNCTION public.outbound_send_exists(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.outbound_send_exists(text, text)
  TO authenticated;

COMMENT ON FUNCTION public.outbound_send_exists(text, text) IS
  'Pre-send duplicate check for the calling founder (auth.uid()): true if an '
  'outbound_sends row already exists for (recipient_hash, approved_body_sha256). '
  'The chokepoint refuses to re-send when true (duplicate-cold-email guard). #5325.';

-- ============================================================================
-- record_outbound_send — the ONLY write path. auth.uid() owner-pin.
-- Called by the chokepoint (outbound.ts) AFTER a successful Resend dispatch.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.record_outbound_send(
  p_recipient_hash       text,
  p_approved_body_sha256 text,
  p_per_send_body_sha256 text,
  p_resend_id            text,
  p_action_class         text DEFAULT 'marketing.outreach'
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
  -- Defense-in-depth: the chokepoint already asserts equality before Resend.
  IF p_approved_body_sha256 IS DISTINCT FROM p_per_send_body_sha256 THEN
    RAISE EXCEPTION 'record_outbound_send: body-hash mismatch (approved <> per-send)'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.outbound_sends (
    owner_id, recipient_hash, approved_body_sha256, per_send_body_sha256,
    resend_id, action_class
  ) VALUES (
    v_owner_id, p_recipient_hash, p_approved_body_sha256, p_per_send_body_sha256,
    p_resend_id, p_action_class
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_outbound_send(text, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_outbound_send(text, text, text, text, text)
  TO authenticated;

COMMENT ON FUNCTION public.record_outbound_send(text, text, text, text, text) IS
  'Append a WORM outbound_sends row for the calling founder (auth.uid()). The '
  'ONLY write path into outbound_sends. Rejects a body-hash mismatch (23514). '
  'Called by the outbound chokepoint after a successful Resend dispatch. #5325.';

-- ============================================================================
-- anonymise_outbound_sends — Art-17 erasure. Mirrors anonymise_action_sends
-- POST-migration-087 — app.worm_bypass GUC (privilege-free) to bypass the
-- pure-reject WORM trigger, NOT the superuser-only session_replication_role.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.anonymise_outbound_sends(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
BEGIN
  -- SERVICE-ROLE ONLY. No self-service (auth.uid() = p_user_id) erasure path:
  -- outbound_sends is a THIRD-PARTY-facing WORM accountability audit (proof of
  -- what cold mail went to whom under what approval). A founder self-erasing it
  -- on demand is audit-trail tampering — it defeats Art. 5(2) accountability and
  -- a recipient's potential DSAR (security review #5325; distinct from the
  -- action_sends precedent, which is the founder's OWN action log). The only
  -- legitimate Art-17 trigger is full account deletion, which runs as
  -- service_role via server/account-delete.ts BEFORE auth.admin.deleteUser.
  IF current_user NOT IN ('service_role', 'postgres') THEN
    RAISE EXCEPTION 'anonymise_outbound_sends: service-role only (no self-service erasure)'
      USING ERRCODE = '42501';
  END IF;

  -- Bypass the pure-reject WORM trigger for this erasure UPDATE only, via the
  -- PRIVILEGE-FREE app.worm_bypass GUC (migration 087 pattern) — NOT
  -- session_replication_role, which is superuser-only and 42501-aborts on
  -- managed Supabase (postgres is not superuser), breaking the whole
  -- account-delete saga (#4696). SET LOCAL is transaction-scoped; re-arm
  -- immediately after the UPDATE.
  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.outbound_sends
     SET owner_id       = NULL,
         recipient_hash = '__anonymised__'
   WHERE owner_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';

  RETURN affected;
END;
$$;

-- service_role-only: NOT granted to authenticated (no self-service erasure).
REVOKE ALL ON FUNCTION public.anonymise_outbound_sends(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_outbound_sends(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_outbound_sends(uuid) IS
  'Art. 17 erasure: zeros owner_id + recipient_hash on outbound_sends rows for '
  'the given founder. Called by account-delete.ts BEFORE auth.admin.deleteUser. '
  'Pattern source: mig 051 anonymise_action_sends. #5325.';
