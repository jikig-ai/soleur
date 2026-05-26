-- 069_action_sends_leader_loop.sql (#4379 PR-B — Anthropic SDK leader loop)
--
-- Adds 6 nullable columns to public.action_sends for the per-turn leader-
-- prompt loop. The Inngest function `agent-on-spawn-requested` (PR-B body
-- replacement of step.run("post-acknowledgment", ...)) is the sole writer
-- of these columns via the service-role client. Reads happen via the
-- existing owner-only RLS SELECT policy.
--
-- Renumbered from plan-time "065" → "067" per Reality-Check Findings row 1
-- in 2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md: migrations 065
-- (art17_cascade_deadlock_repair) and 066 (audit_byok_use_art17_carveout)
-- both landed in #4357 between plan authorship and /work.
--
-- WORM-TRIGGER COMPAT (Reality-Check Findings row 2): mig 064's
-- `action_sends_no_update` trigger uses the
-- `BEFORE UPDATE OF <pre-064 immutable columns>` form (064:62-78). The
-- trigger fires ONLY when one of the listed columns appears in the UPDATE's
-- SET list. UPDATEs touching ONLY these 6 new columns are admitted by
-- default — NO admit-list extension or trigger reshape is required.
--
-- LOAD-BEARING WRITERS:
--   reversal_handles          — set on `end_turn` success (mark-acknowledged
--                                step); cleared on Undo success.
--   current_turn              — set per `turn-${n}-progress-write` step.
--   current_turn_started_at   — set per `turn-${n}-progress-write` step.
--   cancellation_requested_at — set by /api/dashboard/today/[id]/cancel
--                                route via service-role UPDATE.
--   prompt_version            — set once at `turn-1-progress-write` for
--                                in-flight replay determinism.
--   undone_at                 — set by /api/dashboard/today/[id]/undo
--                                route on full reversal success.
--
-- Per Kieran P1-4 (mig 051 precedent): NO outer BEGIN/COMMIT (Supabase
-- runner already wraps each migration in a transaction).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: the existing trigger
-- function `action_sends_no_mutate` already pins SET search_path = public,
-- pg_temp (mig 051). This migration does not touch trigger functions.

-- =============================================================================
-- (a) Add the 6 nullable columns.
-- =============================================================================
ALTER TABLE public.action_sends
  ADD COLUMN IF NOT EXISTS reversal_handles          jsonb,
  ADD COLUMN IF NOT EXISTS current_turn              smallint,
  ADD COLUMN IF NOT EXISTS current_turn_started_at   timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS prompt_version            text,
  ADD COLUMN IF NOT EXISTS undone_at                 timestamptz;

-- =============================================================================
-- (b) COMMENTs documenting the writer contract per column.
-- =============================================================================
COMMENT ON COLUMN public.action_sends.reversal_handles IS
  'JSONB ARRAY of per-artifact reversal records. Each element shape: {kind:"pr_review_comment"|"pr_comment"|"issue_comment"|"issue_label"|"branch"|"pr", owner, repo, ...class-specific fields}. Multi-tool classes (engineering.pr_review_pending, triage.p0p1_issue, security.cve_alert) emit multiple artifacts per loop and therefore multiple handles. The Undo route reverses all elements in order; on partial failure, successfully-reverted elements are removed from the array and the remainder is preserved for retry. NULL = no artifact emitted. Writer: service-role only (UPDATE admitted by mig-064 trigger because this column is not in the BEFORE UPDATE OF list).';

COMMENT ON COLUMN public.action_sends.current_turn IS
  'Current turn index 1..maxTurns (8). UPDATEd by the Inngest function at the start of each turn (step.run "turn-${n}-progress-write"). NULL = pre-turn-1 (loop has not yet started; expected <500ms post-INSERT).';

COMMENT ON COLUMN public.action_sends.current_turn_started_at IS
  'UPDATEd alongside current_turn at each turn start. Used by the Today card to render "Working — turn N of 8, X elapsed".';

COMMENT ON COLUMN public.action_sends.cancellation_requested_at IS
  'Set by /api/dashboard/today/[id]/cancel route on operator Stop click (service-role UPDATE). The Inngest function inspects this column at the start of each turn (step.run "turn-${n}-cancel-check") and short-circuits the loop with failure_reason = "cancelled_by_operator". Mid-turn cancellation is NOT supported — the in-flight turn completes; the cancellation is honored on the next turn boundary.';

COMMENT ON COLUMN public.action_sends.prompt_version IS
  'sha256-of-prompt-shape pinned at loop start (turn-1-progress-write). Developer-maintained v{major}.{minor}.{patch} string from the per-class leader-prompt module. In-flight runs are deterministic against the prompt-version they started with even if the leader-prompt module is edited mid-run. NULL = pre-PR-B run or loop not yet started.';

COMMENT ON COLUMN public.action_sends.undone_at IS
  'Set by /api/dashboard/today/[id]/undo route ONLY when all elements in reversal_handles successfully revert (or are idempotently absent on GitHub). Partial-failure undo does NOT set this column; the failing elements remain in reversal_handles for retry. Writer: service-role only.';
