-- increment_conversation_cost v2 — add an overloaded 6-arg signature
-- accepting cache_read_delta + cache_creation_delta so the cc-soleur-go
-- and legacy paths can persist the full 4-axis usage shape from the
-- Anthropic SDK result message.
--
-- Rolling-deploy safety: this migration intentionally creates a NEW
-- overload (6 args) and does NOT drop the v1 4-arg signature. Postgres
-- distinguishes overloads by parameter-list shape — calls bound to the
-- old signature route to v1; new callers route to v2. Both paths write
-- to the same columns; v1 simply leaves the two new cache columns at
-- their existing values. This eliminates the deploy-ordering window
-- where (a) prd schema-without-app would break new code with `function
-- not exist`, and (b) prd app-without-schema would break old pods'
-- cost writes. v1 is removed in a follow-up migration once the v1
-- callers have aged out (no in-tree v1 caller after this PR).
--
-- The atomic UPDATE pattern is preserved verbatim — the v1 was
-- documented as race-safe under concurrent multi-leader turns (migration
-- 017 §Atomic increment); the v2 only widens the column set.
--
-- supabase-js sends named-arg PostgREST envelopes, so once the v2
-- overload exists, every named-arg call (`{conv_id, cost_delta, ...}`)
-- routes to v2 by parameter name — v1 callers benefit transparently
-- once they redeploy to include the cache args.

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
