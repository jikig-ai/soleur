-- 185_legal_acceptance_ack.sql
-- #12011 PR-D (ADR-319): the acknowledgement behind the `row_without_event` reconciliation. After the web route has
-- emitted the `accepted` event AND the event flush reported success, it writes one row here naming the acceptance. The
-- read-only check endpoint later asks whether a given acceptance row has such an acknowledgement; a row that is older than
-- the grace period and has none is a decision the route did not report, and the endpoint raises `row_without_event`.
--
-- Properties:
--   * The ack table carries an acceptance id and a time ONLY: no founder id, no decision field, no foreign key. It is not
--     a second copy of the record, it is a marker that points at one.
--   * RPC-only: RLS on, no policy, every privilege revoked from every api role. Both functions are service_role only,
--     refuse any caller that carries a user identity, and validate the key and text hash with the migration 184 shape
--     predicates.
--   * Neither function opens the write door of legal_acceptance (the app.legal_acceptance_rpc setting) or writes that
--     table: the ack reads it, and writes only its own table.
--
-- Numbering: 184 is the latest on origin/main (legal acceptance); 185 is free there and on open PRs at authoring time.

-- =====================================================================
-- 0. Preconditions
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.legal_acceptance') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.legal_acceptance must exist before 185';
  END IF;
END $$;

-- =====================================================================
-- 1. legal_acceptance_ack
-- =====================================================================

-- LAWFUL_BASIS: legitimate_interests (Art. 6(1)(f)), same LIA and PA-40 as legal_acceptance.
-- RETENTION: kept with the acceptance row it points at, so the same proposed period (UNCONFIRMED by counsel, #12080).
-- No sweep is built; the deletion path at the end of the period is the open engineering follow-up for legal_acceptance.
-- DSAR: excluded from the self-serve export (DSAR_TABLE_EXCLUSIONS); the table holds no founder id and no free text, only
-- a random acceptance uuid and a timestamp, and service_role has no table privilege on it (RPC-only).
CREATE TABLE IF NOT EXISTS public.legal_acceptance_ack (
  acceptance_id uuid        PRIMARY KEY,
  acked_at      timestamptz NOT NULL DEFAULT now()
);

-- soleur:no-data-api: public.legal_acceptance_ack — service-role RPC-only acknowledgement marker, no api-role table privilege

COMMENT ON TABLE public.legal_acceptance_ack IS
  'Marker that the web route reported the accepted event for one legal_acceptance row (ADR-319, row_without_event). '
  'acceptance_id names the row (no foreign key, no founder id); acked_at is when the marker was written. '
  'Written only by ack_legal_acceptance, read only by legal_acceptance_ack_state; both are service_role only.';

ALTER TABLE public.legal_acceptance_ack ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.legal_acceptance_ack FROM PUBLIC, anon, authenticated, service_role;

-- =====================================================================
-- 2. ack_legal_acceptance (service_role)
-- =====================================================================
-- Answers {outcome: 'acked'} (also when the marker already existed: the write is idempotent and the first time is kept)
-- or {outcome: 'not_found'} when the founder has no decision row for that key and text hash.

CREATE OR REPLACE FUNCTION public.ack_legal_acceptance(p_founder_id uuid, p_key text, p_text_hash text)
  RETURNS jsonb
  LANGUAGE plpgsql
  VOLATILE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'legal acceptance: service role only' USING ERRCODE = '42501';
  END IF;
  IF p_founder_id IS NULL OR p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9-]{0,62}$'
     OR p_text_hash IS NULL OR p_text_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'legal acceptance: invalid input' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_id FROM ONLY public.legal_acceptance
   WHERE founder_id = p_founder_id AND key = p_key AND text_hash = p_text_hash;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('outcome', 'not_found');
  END IF;

  INSERT INTO public.legal_acceptance_ack (acceptance_id) VALUES (v_id) ON CONFLICT (acceptance_id) DO NOTHING;
  RETURN jsonb_build_object('outcome', 'acked');
END;
$$;

REVOKE ALL ON FUNCTION public.ack_legal_acceptance(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ack_legal_acceptance(uuid, text, text)
  TO service_role;

COMMENT ON FUNCTION public.ack_legal_acceptance(uuid, text, text) IS
  'Marks one decision row as reported (ADR-319, row_without_event). Idempotent; not_found when no such row. service_role only.';

-- =====================================================================
-- 3. legal_acceptance_ack_state (service_role; read-only)
-- =====================================================================
-- Answers {outcome: 'none'} when the founder has no decision row for that key and text hash, else
-- {outcome: 'row', acked: boolean, age_seconds: integer}: whether the marker exists, and how old the DECISION ROW is,
-- computed here from the database clock (never from an application clock, so there is no skew).

CREATE OR REPLACE FUNCTION public.legal_acceptance_ack_state(p_founder_id uuid, p_key text, p_text_hash text)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row   public.legal_acceptance%ROWTYPE;
  v_acked boolean;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'legal acceptance: service role only' USING ERRCODE = '42501';
  END IF;
  IF p_founder_id IS NULL OR p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9-]{0,62}$'
     OR p_text_hash IS NULL OR p_text_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'legal acceptance: invalid input' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_row FROM ONLY public.legal_acceptance
   WHERE founder_id = p_founder_id AND key = p_key AND text_hash = p_text_hash;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('outcome', 'none');
  END IF;

  v_acked := EXISTS (SELECT 1 FROM public.legal_acceptance_ack a WHERE a.acceptance_id = v_row.id);
  RETURN jsonb_build_object(
    'outcome', 'row',
    'acked', v_acked,
    'age_seconds', GREATEST(0, floor(extract(epoch FROM (now() - v_row.created_at))))::integer);
END;
$$;

REVOKE ALL ON FUNCTION public.legal_acceptance_ack_state(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.legal_acceptance_ack_state(uuid, text, text)
  TO service_role;

COMMENT ON FUNCTION public.legal_acceptance_ack_state(uuid, text, text) IS
  'Read-only: none, or whether the decision row was acknowledged and its age in seconds from the database clock (ADR-319). service_role only.';
