-- 135_statutory_repin_send.down.sql
-- Reversal of 135_statutory_repin_send.sql — drop the sweep RPC, the table
-- (which drops its CHECK constraint and RLS state with it), and the ledger row.
--
-- A rollback is INTENTIONALLY LOSSY, and lossy here has a specific consequence
-- worth stating: dropping the send markers re-arms every item in the current
-- danger band, so the next cron tick re-sends a statutory-deadline email for
-- each one. That is the safe direction (a duplicate beats silence on a
-- statutory clock), but it is not a no-op — expect the resend.
--
-- purge_email_triage_items and anonymise_email_triage_items are NOT touched
-- here; 135 deliberately never replaced them.
--
-- Expect a burst of Sentry warnings during the rollback window. In the normal
-- order (migrate down, then redeploy) the still-deployed code keeps inserting
-- into a dropped table, so every item in the band hits 42P01, fails open, and
-- contributes to one aggregated `deadline-repin-marker-insert-failed` event per
-- run. That is the guard working as designed — users still get their notices —
-- but it will read as a second incident stacked on the one being rolled back.

-- 1. Sweep RPC / operator release verb.
DROP FUNCTION IF EXISTS public.purge_statutory_repin_send(uuid);

-- 2. Table (drops statutory_repin_send_tick_key_shape with it).
DROP TABLE IF EXISTS public.statutory_repin_send;

-- 3. Ledger row. Required for re-apply — run-migrations.sh skips filenames
--    already present in public._schema_migrations.
DELETE FROM public._schema_migrations WHERE filename = '135_statutory_repin_send.sql';
