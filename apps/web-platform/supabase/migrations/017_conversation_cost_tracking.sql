-- Cost tracking columns for BYOK usage visibility
-- No down migration — financial data columns are irreversible by design

ALTER TABLE conversations
  ADD COLUMN total_cost_usd NUMERIC(12, 6) NOT NULL DEFAULT 0,
  ADD COLUMN input_tokens INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN output_tokens INTEGER NOT NULL DEFAULT 0;

-- Prevent negative cost values (defense-in-depth)
ALTER TABLE conversations
  ADD CONSTRAINT conversations_cost_non_negative
  CHECK (total_cost_usd >= 0 AND input_tokens >= 0 AND output_tokens >= 0);

-- Partial index for billing page query: WHERE user_id = $1 AND total_cost_usd > 0
-- ORDER BY created_at DESC LIMIT 50
CREATE INDEX idx_conversations_user_cost
  ON conversations (user_id, created_at DESC)
  WHERE total_cost_usd > 0;

-- Atomic increment to avoid race conditions under concurrent multi-leader turns
CREATE OR REPLACE FUNCTION increment_conversation_cost(
  conv_id UUID,
  cost_delta NUMERIC,
  input_delta INTEGER,
  output_delta INTEGER
) RETURNS VOID AS $$
BEGIN
  IF cost_delta < 0 OR input_delta < 0 OR output_delta < 0 THEN
    RAISE EXCEPTION 'Cost deltas must be non-negative';
  END IF;

  UPDATE conversations SET
    total_cost_usd = total_cost_usd + cost_delta,
    input_tokens = input_tokens + input_delta,
    output_tokens = output_tokens + output_delta
  WHERE id = conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

-- Restrict to service_role only — end users must never call this directly
REVOKE EXECUTE ON FUNCTION increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER) FROM authenticated;
REVOKE EXECUTE ON FUNCTION increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER) TO service_role;
