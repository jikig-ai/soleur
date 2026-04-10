-- Cost tracking columns for BYOK usage visibility
-- No down migration — financial PII is irreversible by design

ALTER TABLE conversations
  ADD COLUMN total_cost_usd NUMERIC(10, 6) DEFAULT 0,
  ADD COLUMN input_tokens INTEGER DEFAULT 0,
  ADD COLUMN output_tokens INTEGER DEFAULT 0;

-- Atomic increment to avoid race conditions under concurrent multi-leader turns
CREATE OR REPLACE FUNCTION increment_conversation_cost(
  conv_id UUID,
  cost_delta NUMERIC,
  input_delta INTEGER,
  output_delta INTEGER
) RETURNS VOID AS $$
BEGIN
  UPDATE conversations SET
    total_cost_usd = total_cost_usd + cost_delta,
    input_tokens = input_tokens + input_delta,
    output_tokens = output_tokens + output_delta
  WHERE id = conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
