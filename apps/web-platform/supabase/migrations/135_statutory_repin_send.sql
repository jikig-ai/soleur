-- 135_statutory_repin_send.sql
-- fix(notifications) #6781 — a durable send-marker for the statutory-deadline
-- repin cron, so a double-fire cannot send duplicate statutory-deadline email
-- per user per tick, indefinitely.
--
-- The send path (cron-email-ingress-probe's `deadline-repin` step →
-- notifyOfflineUser → sendEmailTriageEmailNotification → resend.emails.send)
-- carried NO idempotency key, no sent-marker row, and no Inngest
-- idempotency/concurrency config. The sibling inbox path (notifyInboxItem,
-- mig 122) already had the guard; this closes an asymmetry WITHIN the same
-- module rather than adding a new capability. Governing decision: ADR-035
-- (plain-insert-catch-23505).
--
-- Four properties of this table are deliberate and load-bearing:
--
--   1. NO `user_id` COLUMN. The marker is item-grain. `email_triage_items` is
--      already the GDPR-hardened WORM ledger holding the subject linkage, and
--      Art. 17 anonymisation NULLs `email_triage_items.user_id` in place. A
--      `user_id` here would be a SECOND erasure surface for no benefit — the FK
--      cascade below already ties the marker's lifetime to the parent row.
--
--   2. RETENTION IS EXPLICIT, NOT BY CASCADE. Statutory parent rows are never
--      purged (they are evidence), so "the cascade will clean it up" is FALSE
--      for this table specifically. Hence the standalone 90-day sweep RPC
--      below, called from the cron's existing `retention-purge` step.
--
--   3. `tick_key` IS BRANCH-DERIVED, NOT A SINGLE VALUE. The repin has TWO
--      cadences: a one-shot heads-up at T-7, and a daily ping from T-2 through
--      overdue. A key modelling only one fails on the other:
--        * "have we pinged this item"  → silences the whole daily danger band
--                                        after day 1.
--        * `daysUntilDue`              → `due` inherits `received_at`'s
--                                        time-of-day, so a cron run and a
--                                        manual trigger minutes apart compute
--                                        DIFFERENT values → same-day duplicate.
--        * UTC calendar date           → correct for the daily band, WRONG for
--                                        the one-shot: `daysUntilDue === 7`
--                                        holds across a 24h window that
--                                        straddles two calendar dates, so ~5min
--                                        of ordinary jitter yields TWO T-7
--                                        emails.
--      So: 'headsup' (a constant, one-shot) OR 'daily:YYYY-MM-DD' (the band).
--      The CHECK below pins exactly those two shapes.
--
--   4. RECIPIENT-GRAIN CONSTRAINT (ADR-035, and see the loop comment in
--      cron-email-ingress-probe.ts). Item-grain equals recipient-grain ONLY
--      while the send path is single-recipient — it pings `row.user_id` alone.
--      Migration 111 already makes items visible to every workspace Owner, so
--      this is a property of the SEND PATH, not a structural guarantee. If a
--      future change fans out to multiple Owners, the first Owner's marker
--      would suppress every other Owner: N-1 recipients get SILENCE on a
--      statutory deadline while the run reports success. That is the
--      `(workspace_id, dedup_key)` collapse class the sibling notifyInboxItem
--      comment warns about. Re-key to recipient-grain BEFORE any such fan-out.
--      Test T12 in cron-email-ingress-probe-repin-idempotency.test.ts is the
--      tripwire that reds when the send path stops being single-recipient.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: the RPC pins
-- SET search_path = public, pg_temp.
-- Transaction wrapping: NO top-level BEGIN/COMMIT — run-migrations.sh wraps the
-- body + the _schema_migrations INSERT in one --single-transaction stream.

-- =====================================================================
-- 0. Preconditions
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.email_triage_items') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.email_triage_items must exist before 135 (mig 102)';
  END IF;
END $$;

-- =====================================================================
-- 1. Table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.statutory_repin_send (
  item_id    uuid        NOT NULL
    REFERENCES public.email_triage_items(id) ON DELETE CASCADE,
  tick_key   text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (item_id, tick_key)
);

-- Pins the two legal tick_key shapes (see header note 3). A third shape
-- reaching this table means the cadence derivation drifted — fail loudly at
-- the write rather than silently keying duplicates apart.
ALTER TABLE public.statutory_repin_send
  DROP CONSTRAINT IF EXISTS statutory_repin_send_tick_key_shape;
ALTER TABLE public.statutory_repin_send
  ADD CONSTRAINT statutory_repin_send_tick_key_shape
  CHECK (tick_key = 'headsup' OR tick_key ~ '^daily:\d{4}-\d{2}-\d{2}$');

COMMENT ON TABLE public.statutory_repin_send IS
  'Send-marker for the statutory-deadline repin cron (#6781). One row per '
  '(item, logical tick); a 23505 on insert means "already sent for this tick" '
  'and the dispatch is skipped. Item-grain, NOT recipient-grain — see the '
  'migration header note 4 before fanning out to multiple recipients. No '
  'user_id by design (Art. 17 erasure already runs on the parent ledger row).';

-- Service-role only: nothing here is client-readable, and the write is made
-- exclusively by the cron under the service key.
ALTER TABLE public.statutory_repin_send ENABLE ROW LEVEL SECURITY;
-- Deliberately ZERO policies. RLS-enabled with no policy denies every
-- non-service-role read and write outright.

-- REVOKE ALL, not the four DML verbs: the verb-list form leaves TRIGGER and
-- REFERENCES granted wherever Supabase's ALTER DEFAULT PRIVILEGES on `public`
-- hands them out. TRIGGER is the one that matters — a trigger created by
-- `authenticated` executes under the DML invoker, and the only writer here is
-- service_role. Precedent: 049_runtime_mint_intent.sql.
REVOKE ALL ON TABLE public.statutory_repin_send FROM PUBLIC, anon, authenticated;

-- =====================================================================
-- 2. Retention sweep + operator release verb
-- =====================================================================
--
-- NOT a CREATE OR REPLACE of purge_email_triage_items. That function's
-- security attributes would not survive a replace, both AP-018 guard tiers are
-- blind to the drop, its anonymise UPDATE rebinds GET DIAGNOSTICS, and a
-- failure in the purge step zeroes the entire danger band. A standalone
-- function is strictly safer and is what the cron calls alongside the existing
-- purge.
--
-- Two modes:
--   * p_item_id NULL (the cron's call)  → 90-day sweep.
--   * p_item_id supplied               → targeted delete. This is the operator
--     RELEASE verb, for the case where a send was marked but demonstrably
--     never delivered.
--
--     READ THIS BEFORE RELYING ON IT: clearing a marker does NOT guarantee a
--     re-send. It only re-arms the item; the next tick still has to WANT to
--     fire. The repin predicate fires at exactly T-7, then daily from T-2
--     through overdue — so days 6, 5, 4 and 3 fire NOTHING. Releasing a
--     `headsup` marker at T-6 re-arms an item that no tick will pick up until
--     T-2, and the T-7 heads-up is gone for good (`daysUntilDue === 7` never
--     holds again). On a 72-hour breach-art33 clock that dead zone is most of
--     the remaining time.
--
--     So: releasing inside a fire window re-sends on the next tick; releasing
--     inside the T-7→T-2 dead zone does not, and the operator needs to know
--     which case they are in.

CREATE OR REPLACE FUNCTION public.purge_statutory_repin_send(
  p_item_id uuid DEFAULT NULL
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted integer;
BEGIN
  IF p_item_id IS NULL THEN
    DELETE FROM public.statutory_repin_send
      WHERE created_at < now() - interval '90 days';
  ELSE
    DELETE FROM public.statutory_repin_send
      WHERE item_id = p_item_id;
  END IF;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_statutory_repin_send(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.purge_statutory_repin_send(uuid)
  TO service_role;

COMMENT ON FUNCTION public.purge_statutory_repin_send(uuid) IS
  'SECURITY DEFINER; service_role only. p_item_id NULL sweeps markers older '
  'than 90 days (called from the cron retention-purge step). p_item_id '
  'supplied is the operator release verb: clears that item''s markers, re-arming '
  'it. NOTE: re-arming only re-sends if a later tick actually fires — the '
  'predicate is silent on days 6..3, so a release inside that dead zone does '
  'nothing until T-2.';
