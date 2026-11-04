-- 184_legal_acceptance.sql
-- #12011 PR-B (ADR-318): a write-once record of a founder's decision on a legal text, made from their authenticated
-- web session, plus the single-use email-code challenge that backs a Yes. Nothing in the product reads this table
-- to enforce anything yet (PR-C adds the screens, PR-D the read-only check endpoint); the record is dark until then.
--
-- Properties (the Guard 3 contract in the plan):
--   * Once a decision row exists, no column of it can change and no row can be deleted (write-once trigger).
--   * A Yes row exists only with a verified, unexpired, matching reauth event for the same user, key, text hash and
--     session, consumed in the same transaction as the insert.
--   * row_hash is computed by the database from the row, not supplied by a caller. It detects a changed row; it is
--     not an external anchor (that is deferred, see ADR-318).
--   * The table carries no foreign key and is not touched by any erasure scrub: the founder id is a pseudonymous uuid
--     and the record outlives the account (Art. 17(3)(e), see the LIA).
--
-- Numbering: 183 is the latest on origin/main (egress audit window summary); 184 is free there, on open PRs and on
-- the shared DEV ledger at authoring time.

-- =====================================================================
-- 0. Preconditions
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.users') IS NULL
     OR to_regprocedure('public.is_jti_denied_from_jwt()') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.users and is_jti_denied_from_jwt() must exist before 184';
  END IF;
END $$;

-- =====================================================================
-- 1. legal_acceptance (the record)
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.legal_acceptance (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  founder_id     uuid        NOT NULL,
  key            text        NOT NULL CHECK (key ~ '^[a-z0-9][a-z0-9-]{0,62}$'),
  text_hash      text        NOT NULL CHECK (text_hash ~ '^[0-9a-f]{64}$'),
  version        text        NOT NULL CHECK (char_length(version) BETWEEN 1 AND 32),
  choice         text        NOT NULL CHECK (choice IN ('accept', 'decline', 'request_changes')),
  requested_edit text        CHECK (requested_edit IS NULL OR char_length(requested_edit) BETWEEN 1 AND 1000),
  method         text        NOT NULL DEFAULT 'web-session' CHECK (method = 'web-session'),
  reauth_method  text        CHECK (reauth_method IS NULL OR reauth_method = 'email-code'),
  reauth_at      timestamptz,
  session_id     text        CHECK (session_id IS NULL OR char_length(session_id) BETWEEN 1 AND 128),
  surface        text        NOT NULL DEFAULT 'web' CHECK (surface = 'web'),
  row_hash       text        NOT NULL DEFAULT '' CHECK (row_hash ~ '^[0-9a-f]{64}$'),
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (founder_id, key, text_hash),
  CONSTRAINT legal_acceptance_yes_has_reauth
    CHECK (choice <> 'accept' OR (reauth_method IS NOT NULL AND reauth_at IS NOT NULL AND session_id IS NOT NULL)),
  CONSTRAINT legal_acceptance_edit_only_with_request
    CHECK ((choice = 'request_changes') = (requested_edit IS NOT NULL))
);

COMMENT ON TABLE public.legal_acceptance IS
  'Write-once record of a founder decision on a legal text (ADR-318). founder_id is a pseudonymous uuid with no '
  'foreign key. Written only by record_legal_acceptance under the guard trigger; read by the founder (RLS) and by '
  'verify_legal_acceptance (service_role). Retained after account deletion under Art. 17(3)(e).';

-- =====================================================================
-- 2. legal_reauth_event (single-use email-code challenge)
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.legal_reauth_event (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL,
  key           text        NOT NULL CHECK (key ~ '^[a-z0-9][a-z0-9-]{0,62}$'),
  text_hash     text        NOT NULL CHECK (text_hash ~ '^[0-9a-f]{64}$'),
  session_id    text        NOT NULL CHECK (char_length(session_id) BETWEEN 1 AND 128),
  attempts      integer     NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  expires_at    timestamptz NOT NULL,
  verified_at   timestamptz,
  consumed_at   timestamptz,
  superseded_at timestamptz,
  -- clock_timestamp(), not now(): two challenges issued in one transaction must still order (newest wins).
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS legal_reauth_event_lookup_idx
  ON public.legal_reauth_event (user_id, key, created_at DESC);

COMMENT ON TABLE public.legal_reauth_event IS
  'One email-code challenge, bound to one user, key, text hash and web session (ADR-318). Short-lived; consumed '
  'atomically by record_legal_acceptance for a Yes. The code itself is verified by the auth service, never stored here.';

-- =====================================================================
-- 3. RLS and grants
-- =====================================================================
-- legal_acceptance: the founder reads their own rows. No INSERT/UPDATE/DELETE policy and no write grant for any api
-- role; service_role holds no table privilege either (it reaches the table through the RPCs only).
-- legal_reauth_event: RLS on, no policy, no privilege: RPC access only.

ALTER TABLE public.legal_acceptance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_reauth_event ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.legal_acceptance FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.legal_reauth_event FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.legal_acceptance TO authenticated;

DROP POLICY IF EXISTS legal_acceptance_founder_select ON public.legal_acceptance;
CREATE POLICY legal_acceptance_founder_select ON public.legal_acceptance
  FOR SELECT TO authenticated
  USING (founder_id = auth.uid());

-- RESTRICTIVE jti-deny (068/126 shape): a revoked-but-unexpired JWT is refused at the policy boundary.
DROP POLICY IF EXISTS legal_acceptance_jti_not_denied ON public.legal_acceptance;
CREATE POLICY legal_acceptance_jti_not_denied ON public.legal_acceptance
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

-- =====================================================================
-- 4. Row checksum (database-computed)
-- =====================================================================
-- sha256 over the columns in a fixed order, each as a 4-byte big-endian length followed by its UTF-8 bytes (a NULL
-- is length -1, so NULL and the empty string differ and no two rows can concatenate to the same bytes). The leading
-- literal is a domain separator and version tag. It makes a changed row detectable by anyone who recomputes it; it
-- does not stop a holder of database-owner access from rewriting a row AND its hash, which is why ADR-318 names an
-- external anchor as the next step.

CREATE OR REPLACE FUNCTION public.legal_acceptance_row_hash(r public.legal_acceptance)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN (
    SELECT encode(
             sha256(
               string_agg(
                 CASE WHEN t.v IS NULL THEN int4send(-1)
                      ELSE int4send(octet_length(convert_to(t.v, 'UTF8'))) || convert_to(t.v, 'UTF8')
                 END,
                 ''::bytea ORDER BY t.n)),
             'hex')
      FROM unnest(ARRAY[
        'legal-acceptance-v1',
        r.id::text,
        r.founder_id::text,
        r.key,
        r.text_hash,
        r.version,
        r.choice,
        r.requested_edit,
        r.method,
        r.reauth_method,
        to_char(r.reauth_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        r.session_id,
        r.surface,
        to_char(r.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ]) WITH ORDINALITY AS t(v, n)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.legal_acceptance_row_hash(public.legal_acceptance)
  FROM PUBLIC, anon, authenticated, service_role;

-- =====================================================================
-- 5. Write-once guard
-- =====================================================================
-- UPDATE, DELETE and TRUNCATE always refuse. INSERT is admitted only inside record_legal_acceptance (the
-- transaction-local GUC), and the guard overwrites row_hash so a caller cannot choose it.

CREATE OR REPLACE FUNCTION public.legal_acceptance_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' OR TG_OP = 'TRUNCATE' THEN
    RAISE EXCEPTION 'legal acceptance: records are write-once (% refused)', TG_OP USING ERRCODE = '42501';
  END IF;
  IF COALESCE(current_setting('app.legal_acceptance_rpc', true), '') <> 'on' THEN
    RAISE EXCEPTION 'legal acceptance: direct insert refused' USING ERRCODE = '42501';
  END IF;
  NEW.row_hash := public.legal_acceptance_row_hash(NEW);
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.legal_acceptance_guard()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS legal_acceptance_guard ON public.legal_acceptance;
CREATE TRIGGER legal_acceptance_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.legal_acceptance
  FOR EACH ROW EXECUTE FUNCTION public.legal_acceptance_guard();

DROP TRIGGER IF EXISTS legal_acceptance_no_truncate ON public.legal_acceptance;
CREATE TRIGGER legal_acceptance_no_truncate
  BEFORE TRUNCATE ON public.legal_acceptance
  FOR EACH STATEMENT EXECUTE FUNCTION public.legal_acceptance_guard();

-- =====================================================================
-- 6. issue_legal_reauth (service_role)
-- =====================================================================
-- Starts a challenge. Voids any earlier unconsumed challenge of the same user and key (a resend voids the old code).
-- Outcomes: issued | already_recorded (a decision for this text already exists) | rate_limited (more than 10
-- challenges for this user and key in the last hour).

CREATE OR REPLACE FUNCTION public.issue_legal_reauth(
  p_user_id    uuid,
  p_key        text,
  p_text_hash  text,
  p_session_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing public.legal_acceptance%ROWTYPE;
  v_event    public.legal_reauth_event%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'legal acceptance: service role only' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9-]{0,62}$'
     OR p_text_hash IS NULL OR p_text_hash !~ '^[0-9a-f]{64}$'
     OR p_session_id IS NULL OR char_length(p_session_id) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'legal acceptance: invalid input' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_existing FROM public.legal_acceptance
   WHERE founder_id = p_user_id AND key = p_key AND text_hash = p_text_hash;
  IF FOUND THEN
    RETURN jsonb_build_object('outcome', 'already_recorded', 'choice', v_existing.choice);
  END IF;

  IF (SELECT count(*) FROM public.legal_reauth_event
       WHERE user_id = p_user_id AND key = p_key AND created_at > now() - interval '1 hour') >= 10 THEN
    RETURN jsonb_build_object('outcome', 'rate_limited');
  END IF;

  UPDATE public.legal_reauth_event
     SET superseded_at = now()
   WHERE user_id = p_user_id AND key = p_key
     AND consumed_at IS NULL AND superseded_at IS NULL;

  INSERT INTO public.legal_reauth_event (user_id, key, text_hash, session_id, expires_at)
  VALUES (p_user_id, p_key, p_text_hash, p_session_id, now() + interval '5 minutes')
  RETURNING * INTO v_event;

  RETURN jsonb_build_object('outcome', 'issued', 'event_id', v_event.id, 'expires_at', v_event.expires_at);
END;
$$;

REVOKE ALL ON FUNCTION public.issue_legal_reauth(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.issue_legal_reauth(uuid, text, text, text)
  TO service_role;

-- =====================================================================
-- 7. claim_legal_reauth_attempt (service_role)
-- =====================================================================
-- Counts one code attempt BEFORE the auth service is asked to check the code, so a locked challenge never reaches
-- the auth service. Outcomes: allowed | locked (5 attempts used) | expired | replaced (voided or bound to another
-- text) | not_found.

CREATE OR REPLACE FUNCTION public.claim_legal_reauth_attempt(
  p_user_id    uuid,
  p_key        text,
  p_text_hash  text,
  p_session_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_event public.legal_reauth_event%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'legal acceptance: service role only' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_event FROM public.legal_reauth_event
   WHERE user_id = p_user_id AND key = p_key AND session_id = p_session_id
   ORDER BY created_at DESC LIMIT 1
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('outcome', 'not_found');
  END IF;
  IF v_event.text_hash <> p_text_hash OR v_event.superseded_at IS NOT NULL OR v_event.consumed_at IS NOT NULL THEN
    RETURN jsonb_build_object('outcome', 'replaced');
  END IF;
  IF v_event.expires_at <= now() THEN
    RETURN jsonb_build_object('outcome', 'expired');
  END IF;
  IF v_event.attempts >= 5 THEN
    RETURN jsonb_build_object('outcome', 'locked');
  END IF;
  UPDATE public.legal_reauth_event SET attempts = attempts + 1 WHERE id = v_event.id;
  RETURN jsonb_build_object('outcome', 'allowed', 'attempts', v_event.attempts + 1);
END;
$$;

REVOKE ALL ON FUNCTION public.claim_legal_reauth_attempt(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_legal_reauth_attempt(uuid, text, text, text)
  TO service_role;

-- =====================================================================
-- 8. mark_legal_reauth_verified (service_role)
-- =====================================================================
-- Called after the auth service accepted the code. Only a challenge that was claimed (attempts >= 1), is live and
-- matches user, key, text hash and session becomes verified. Outcomes: verified | not_claimed | expired | replaced |
-- not_found.

CREATE OR REPLACE FUNCTION public.mark_legal_reauth_verified(
  p_user_id    uuid,
  p_key        text,
  p_text_hash  text,
  p_session_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_event public.legal_reauth_event%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'legal acceptance: service role only' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_event FROM public.legal_reauth_event
   WHERE user_id = p_user_id AND key = p_key AND session_id = p_session_id
   ORDER BY created_at DESC LIMIT 1
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('outcome', 'not_found');
  END IF;
  IF v_event.text_hash <> p_text_hash OR v_event.superseded_at IS NOT NULL OR v_event.consumed_at IS NOT NULL THEN
    RETURN jsonb_build_object('outcome', 'replaced');
  END IF;
  IF v_event.expires_at <= now() THEN
    RETURN jsonb_build_object('outcome', 'expired');
  END IF;
  IF v_event.attempts < 1 THEN
    RETURN jsonb_build_object('outcome', 'not_claimed');
  END IF;
  UPDATE public.legal_reauth_event SET verified_at = COALESCE(verified_at, now()) WHERE id = v_event.id;
  RETURN jsonb_build_object('outcome', 'verified');
END;
$$;

REVOKE ALL ON FUNCTION public.mark_legal_reauth_verified(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_legal_reauth_verified(uuid, text, text, text)
  TO service_role;

-- =====================================================================
-- 9. record_legal_acceptance (authenticated; actor = auth.uid())
-- =====================================================================
-- The founder's decision. The actor is the verified session, never a parameter. The server passes the text hash of
-- its own registry entry; the browser never supplies text. A Yes consumes a verified, unexpired challenge bound to
-- this user, key, text hash and session, in the same transaction as the insert. Outcomes: recorded |
-- already_recorded (a decision for this text exists; nothing changes) | replaced (the challenge belongs to another
-- text or was voided; nothing is consumed) | expired (nothing is consumed).

CREATE OR REPLACE FUNCTION public.record_legal_acceptance(
  p_key            text,
  p_text_hash      text,
  p_version        text,
  p_choice         text,
  p_requested_edit text DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_session  text := NULLIF(auth.jwt() ->> 'session_id', '');
  v_existing public.legal_acceptance%ROWTYPE;
  v_event    public.legal_reauth_event%ROWTYPE;
  v_row      public.legal_acceptance%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'legal acceptance: authenticated callers only' USING ERRCODE = '42501';
  END IF;
  IF public.is_jti_denied_from_jwt() THEN
    RAISE EXCEPTION 'legal acceptance: token denied' USING ERRCODE = '42501';
  END IF;
  IF (auth.jwt() ->> 'aud') = 'soleur-runtime' THEN
    RAISE EXCEPTION 'legal acceptance: a runtime token cannot record a decision' USING ERRCODE = '42501';
  END IF;
  IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9-]{0,62}$'
     OR p_text_hash IS NULL OR p_text_hash !~ '^[0-9a-f]{64}$'
     OR p_version IS NULL OR char_length(p_version) NOT BETWEEN 1 AND 32
     OR p_choice IS NULL OR p_choice NOT IN ('accept', 'decline', 'request_changes')
     OR (p_choice = 'request_changes') <> (p_requested_edit IS NOT NULL AND btrim(p_requested_edit) <> '')
     OR (p_requested_edit IS NOT NULL AND char_length(p_requested_edit) > 1000) THEN
    RAISE EXCEPTION 'legal acceptance: invalid input' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_existing FROM public.legal_acceptance
   WHERE founder_id = auth.uid() AND key = p_key AND text_hash = p_text_hash;
  IF FOUND THEN
    RETURN jsonb_build_object('outcome', 'already_recorded', 'choice', v_existing.choice);
  END IF;

  IF p_choice = 'accept' THEN
    IF v_session IS NULL THEN
      RAISE EXCEPTION 'legal acceptance: email code required' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_event FROM public.legal_reauth_event e
     WHERE user_id = auth.uid() AND key = p_key AND session_id = v_session
     ORDER BY created_at DESC LIMIT 1
     FOR UPDATE;
    IF NOT FOUND OR v_event.verified_at IS NULL OR v_event.consumed_at IS NOT NULL THEN
      RAISE EXCEPTION 'legal acceptance: email code required' USING ERRCODE = '42501';
    END IF;
    IF v_event.text_hash <> p_text_hash OR v_event.superseded_at IS NOT NULL THEN
      RETURN jsonb_build_object('outcome', 'replaced');
    END IF;
    IF v_event.expires_at <= now() THEN
      RETURN jsonb_build_object('outcome', 'expired');
    END IF;
    UPDATE public.legal_reauth_event
       SET consumed_at = now()
     WHERE id = v_event.id AND consumed_at IS NULL AND verified_at IS NOT NULL AND superseded_at IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'legal acceptance: concurrent change, retry' USING ERRCODE = '40001';
    END IF;
  END IF;

  PERFORM set_config('app.legal_acceptance_rpc', 'on', true);
  INSERT INTO public.legal_acceptance
    (founder_id, key, text_hash, version, choice, requested_edit, reauth_method, reauth_at, session_id)
  VALUES
    (auth.uid(), p_key, p_text_hash, p_version, p_choice,
     CASE WHEN p_choice = 'request_changes' THEN btrim(p_requested_edit) END,
     CASE WHEN p_choice = 'accept' THEN 'email-code' END,
     CASE WHEN p_choice = 'accept' THEN v_event.verified_at END,
     v_session)
  RETURNING * INTO v_row;
  PERFORM set_config('app.legal_acceptance_rpc', 'off', true);

  RETURN jsonb_build_object(
    'outcome', 'recorded',
    'choice', v_row.choice,
    'text_hash', v_row.text_hash,
    'decided_at', v_row.created_at,
    'reauth_at', v_row.reauth_at);
END;
$$;

REVOKE ALL ON FUNCTION public.record_legal_acceptance(text, text, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_legal_acceptance(text, text, text, text, text)
  TO authenticated;

-- =====================================================================
-- 10. verify_legal_acceptance (service_role; read-only)
-- =====================================================================
-- What the check endpoint (PR-D) reads: the status of one founder's decision on one text and whether the stored
-- row still matches its checksum. Opens no write door.

CREATE OR REPLACE FUNCTION public.verify_legal_acceptance(
  p_founder_id uuid,
  p_key        text,
  p_text_hash  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.legal_acceptance%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'legal acceptance: service role only' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_row FROM public.legal_acceptance
   WHERE founder_id = p_founder_id AND key = p_key AND text_hash = p_text_hash;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'none', 'text_hash', p_text_hash, 'decided_at', NULL, 'row_ok', NULL);
  END IF;
  RETURN jsonb_build_object(
    'status', CASE v_row.choice
                WHEN 'accept' THEN 'accepted'
                WHEN 'decline' THEN 'declined'
                ELSE 'changes_requested'
              END,
    'text_hash', v_row.text_hash,
    'decided_at', v_row.created_at,
    'row_ok', v_row.row_hash = public.legal_acceptance_row_hash(v_row));
END;
$$;

REVOKE ALL ON FUNCTION public.verify_legal_acceptance(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_legal_acceptance(uuid, text, text)
  TO service_role;
