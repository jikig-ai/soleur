-- 186_legal_acceptance_hash_counts.sql
-- #12429 (ADR-319, amendment 2026-11-08): the credential-free pre-flag aggregate. Before the approval-queue flag is
-- flipped, the operator needs to know whether any decision row exists for a key under a text hash other than the registry
-- hash. Until now that question needed the database-owner credential (the runbook's owner-SQL step); this function lets the
-- verify bearer answer it through the web route GET /api/internal/legal-acceptance/[key]/counts.
--
-- Properties:
--   * Function-only: no table, no column, no change to public.legal_acceptance (migration 184) or its ack table (185).
--   * It reveals a key's TOTAL and the count PER TEXT HASH and nothing else. It selects no founder id, no choice, no
--     timestamp and no note (requested_edit); the select list is the key filter and the text hash only.
--   * service_role only: refuses any caller that carries a user identity (42501), and every api role including
--     service_role is revoked before EXECUTE is granted back to service_role alone (Supabase default privileges defeat
--     REVOKE FROM PUBLIC alone).
--   * The key is validated with the migration 184 shape predicate; the caller's text never reaches an exception message.
--   * by_hash is capped at 20 distinct hashes. More than that is refused (54000) rather than truncated, because a
--     truncated list would no longer sum to the total and the reader would draw a wrong conclusion from it.
--
-- Numbering: 185 is the latest on origin/main (legal acceptance ack); 186 is free there and on open PRs at authoring time.

-- =====================================================================
-- 0. Preconditions
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.legal_acceptance') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.legal_acceptance must exist before 186';
  END IF;
END $$;

-- =====================================================================
-- 1. legal_acceptance_hash_counts (service_role; read-only)
-- =====================================================================
-- Answers {total: <int>, by_hash: [{text_hash, count}, ...]} ordered by text_hash; {total: 0, by_hash: []} when the key
-- has no rows.

-- LAWFUL_BASIS: legitimate_interests (Art. 6(1)(f)), same LIA and PA-40 as legal_acceptance. Aggregate counts, no identifier per row.
CREATE OR REPLACE FUNCTION public.legal_acceptance_hash_counts(p_key text)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_total  bigint;
  v_groups bigint;
  v_by     jsonb;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'legal acceptance: service role only' USING ERRCODE = '42501';
  END IF;
  IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9-]{0,62}$' THEN
    RAISE EXCEPTION 'legal acceptance: invalid input' USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_total FROM ONLY public.legal_acceptance WHERE key = p_key;

  SELECT count(*),
         COALESCE(jsonb_agg(jsonb_build_object('text_hash', g.text_hash, 'count', g.n) ORDER BY g.text_hash), '[]'::jsonb)
    INTO v_groups, v_by
    FROM (
      SELECT text_hash, count(*) AS n
        FROM ONLY public.legal_acceptance
       WHERE key = p_key
       GROUP BY text_hash
       ORDER BY text_hash
       LIMIT 21
    ) AS g;

  IF v_groups > 20 THEN
    RAISE EXCEPTION 'legal acceptance: too many distinct hashes' USING ERRCODE = '54000';
  END IF;

  RETURN jsonb_build_object('total', v_total, 'by_hash', v_by);
END;
$$;

REVOKE ALL ON FUNCTION public.legal_acceptance_hash_counts(text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.legal_acceptance_hash_counts(text)
  TO service_role;

COMMENT ON FUNCTION public.legal_acceptance_hash_counts(text) IS
  'Read-only aggregate: the total and the per-text-hash counts of decision rows for one key (ADR-319, #12429). No founder id, choice, timestamp or note. LIA / PA-40 basis: Art. 6(1)(f). service_role only.';
