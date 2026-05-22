-- 064_action_sends_acknowledgment.sql (#4124 PR-A)
--
-- Adds three acknowledgment columns to public.action_sends and reshapes
-- the existing pure-reject WORM UPDATE trigger so the new columns are
-- writable while every pre-064 column remains immutable.
--
-- Renumbered from plan-time "062" → "064" because main shipped
-- 062_workspace_member_removals_and_remove_rpc_update.sql and
-- 063_workspace_member_actions.sql between plan authorship and /work.
--
-- The Inngest function `agent-on-spawn-requested` is the sole writer of
-- acknowledged_at + artifact_url + failure_reason. It writes via the
-- service-role client (RLS owner-only SELECT/INSERT policies still gate
-- founder access). PR-A ships a deterministic-stub artifact; PR-B will
-- replace the stub body with the Anthropic SDK leader-prompt loop.
--
-- Per Kieran P1-4 (mig 051 precedent): NO outer BEGIN/COMMIT (Supabase
-- runner already wraps each migration in a transaction).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: the trigger
-- function already pins SET search_path = public, pg_temp (mig 051);
-- the reshape here only touches the trigger declaration, not the
-- function body, so the pin is preserved.

-- =============================================================================
-- (a) Add the three nullable columns. NULL = pending (Inngest function has
--     not yet written acknowledgment / failure state).
-- =============================================================================
ALTER TABLE public.action_sends
  ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz,
  ADD COLUMN IF NOT EXISTS artifact_url    text,
  ADD COLUMN IF NOT EXISTS failure_reason  text;

COMMENT ON COLUMN public.action_sends.acknowledged_at IS
  'Set by agent-on-spawn-requested Inngest function on successful artifact emit. NULL = pending. Writer: service-role only (UPDATE allowed on this column by the reshaped WORM trigger).';

COMMENT ON COLUMN public.action_sends.artifact_url IS
  'GitHub URL of the acknowledgment artifact (PR comment html_url or issue page). Single-fetch, no listing. Writer: service-role only (UPDATE allowed on this column by the reshaped WORM trigger).';

COMMENT ON COLUMN public.action_sends.failure_reason IS
  'Set on terminal Inngest failure (e.g., github_installation_unauthorized). NULL on success or in-flight. Writer: service-role only (UPDATE allowed on this column by the reshaped WORM trigger).';

-- =============================================================================
-- (b) Reshape the WORM UPDATE trigger so the three new columns are writable.
--
--     Mig 051 installed `action_sends_no_update` as `BEFORE UPDATE ... FOR
--     EACH STATEMENT` which rejected every UPDATE unconditionally. The
--     `BEFORE UPDATE OF <column_list>` form fires the trigger only when at
--     least one of the listed columns appears in the UPDATE's SET list
--     (per PostgreSQL docs). So an UPDATE that touches ONLY
--     acknowledged_at / artifact_url / failure_reason is admitted; an
--     UPDATE that touches any pre-064 column is rejected exactly as
--     before. Same trigger function — only the trigger declaration
--     changes.
--
--     The DELETE-rejection trigger (`action_sends_no_delete`) is
--     untouched: WORM still forbids deletion. Art-17 erasure continues to
--     run through the anonymise_action_sends RPC's session-replication-
--     role bypass.
-- =============================================================================
DROP TRIGGER IF EXISTS action_sends_no_update ON public.action_sends;
CREATE TRIGGER action_sends_no_update
  BEFORE UPDATE OF
    id,
    user_id,
    message_id,
    action_class,
    tier_at_send,
    template_hash,
    per_send_body_sha256,
    recipient_id_hash,
    clicked_at,
    confirmed_typed,
    approval_signature_sha256,
    grant_id
  ON public.action_sends
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.action_sends_no_mutate();
