-- Cache-token columns for parity with the Anthropic SDK `usage` shape.
-- Migration 017 added `total_cost_usd`, `input_tokens`, `output_tokens`
-- but dropped `cache_read_input_tokens` + `cache_creation_input_tokens`.
-- With prompt caching enabled the bulk of "real" input tokens land in
-- the cache_read axis and are silently discarded — the dashboard's
-- "Input" pill renders ~5-15% of the Anthropic Console's headline
-- number for cached prompts, breaking the "match to the cent" footnote
-- (feat-restore-byok-usage-dashboard/spec.md AC #11).
--
-- No down migration: financial telemetry columns are irreversible by
-- design (precedent: migration 017).
-- No backfill from Admin API in this PR (deferred to a follow-up).

ALTER TABLE conversations
  ADD COLUMN cache_read_input_tokens INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0;

-- Defense-in-depth: cache token counts cannot be negative.
ALTER TABLE conversations
  ADD CONSTRAINT conversations_cache_tokens_non_negative
  CHECK (cache_read_input_tokens >= 0 AND cache_creation_input_tokens >= 0);

-- Extend the dashboard list query's covering index so the
-- per-conversation SELECT stays index-only after the schema widening.
-- The list query SELECTs: id, domain_leader, created_at,
-- input_tokens, output_tokens, cache_read_input_tokens,
-- cache_creation_input_tokens, total_cost_usd. `id`, `user_id`,
-- `created_at` are in the index key; the other 6 must be in INCLUDE
-- for the planner to choose an Index-Only Scan. `domain_leader`
-- was the missing column pre-2026-05-12.
-- Supabase wraps the migration in a transaction (CONCURRENTLY forbidden,
-- per learning 2026-04-18-supabase-migration-concurrently-forbidden).
-- A brief AccessExclusive lock at current scale is acceptable.
DROP INDEX IF EXISTS idx_conversations_user_cost;
CREATE INDEX idx_conversations_user_cost
  ON conversations (user_id, created_at DESC)
  INCLUDE (
    domain_leader,
    total_cost_usd,
    input_tokens,
    output_tokens,
    cache_read_input_tokens,
    cache_creation_input_tokens
  )
  WHERE total_cost_usd > 0;
