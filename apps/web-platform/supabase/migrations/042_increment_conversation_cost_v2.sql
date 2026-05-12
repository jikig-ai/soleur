-- increment_conversation_cost v2 — widen the atomic-increment RPC to
-- accept cache_read_delta + cache_creation_delta so the cc-soleur-go
-- and legacy paths can persist the full 4-axis usage shape from the
-- Anthropic SDK result message.
--
-- The v1 signature `(UUID, NUMERIC, INT, INT)` is callable from any
-- of `agent-runner.ts:1880` and (soon) `cost-writer.ts`. Postgres
-- rejects `CREATE OR REPLACE` across overload signature changes with
-- "function is not unique"; the v1 must be dropped first (precedent:
-- migration 027 comment).
--
-- The atomic UPDATE pattern is preserved verbatim — the v1 was
-- documented as race-safe under concurrent multi-leader turns (migration
-- 017 §Atomic increment); the v2 only widens the column set.

DROP FUNCTION IF EXISTS public.increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.increment_conversation_cost(
  conv_id              UUID,
  cost_delta           NUMERIC,
  input_delta          INTEGER,
  output_delta         INTEGER,
  cache_read_delta     INTEGER DEFAULT 0,
  cache_creation_delta INTEGER DEFAULT 0
) RETURNS VOID AS $$
BEGIN
  IF cost_delta < 0
     OR input_delta < 0
     OR output_delta < 0
     OR cache_read_delta < 0
     OR cache_creation_delta < 0 THEN
    RAISE EXCEPTION 'Cost deltas must be non-negative';
  END IF;

  UPDATE conversations SET
    total_cost_usd              = total_cost_usd              + cost_delta,
    input_tokens                = input_tokens                + input_delta,
    output_tokens               = output_tokens               + output_delta,
    cache_read_input_tokens     = cache_read_input_tokens     + cache_read_delta,
    cache_creation_input_tokens = cache_creation_input_tokens + cache_creation_delta
  WHERE id = conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public, pg_temp;

-- Service-role only — end users must never call this directly. Mirrors
-- migration 017's ACL on the v1.
REVOKE ALL ON FUNCTION public.increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER, INTEGER, INTEGER) TO service_role;
