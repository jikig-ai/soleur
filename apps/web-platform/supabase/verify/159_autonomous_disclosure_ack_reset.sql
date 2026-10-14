-- verify/159_autonomous_disclosure_ack_reset.sql
-- Post-apply sentinel for the #9776 ack reset. Each row returns bad=1 on a
-- drift; run-verify.sh fails the deploy if any bad=1. Idempotent and
-- read-only: it must stay valid after owners re-ack, so it asserts structure
-- and the invariant that a superseded timestamp is never set without the
-- workspace having been acked (superseded_at never exceeds now()).

SELECT 'ack_superseded_column_exists' AS check_name,
       CASE WHEN EXISTS (
              SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public'
                AND table_name   = 'workspaces'
                AND column_name  = 'autonomous_disclosure_ack_superseded_at'
                AND data_type    = 'timestamp with time zone'
                AND is_nullable  = 'YES')
            THEN 0 ELSE 1 END::int AS bad
UNION ALL
SELECT 'ack_live_column_still_exists',
       CASE WHEN EXISTS (
              SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public'
                AND table_name   = 'workspaces'
                AND column_name  = 'autonomous_disclosure_ack_at')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'ack_superseded_not_in_future',
       (SELECT count(*) FROM public.workspaces
        WHERE autonomous_disclosure_ack_superseded_at > now())::int
UNION ALL
-- A live ack never predates the superseded one it replaced (COALESCE keeps the
-- FIRST superseded value, so a later re-ack is always newer).
SELECT 'ack_not_older_than_superseded',
       (SELECT count(*) FROM public.workspaces
        WHERE autonomous_disclosure_ack_superseded_at IS NOT NULL
          AND autonomous_disclosure_ack_at IS NOT NULL
          AND autonomous_disclosure_ack_at < autonomous_disclosure_ack_superseded_at)::int
UNION ALL
-- Detects a no-op migration: after 159 no autonomous workspace may still hold an
-- ack that predates the 2026-10-08 copy re-lock.
SELECT 'no_autonomous_ack_predates_relock',
       (SELECT count(*) FROM public.workspaces
        WHERE bash_autonomous
          AND autonomous_disclosure_ack_at < timestamptz '2026-10-08 00:00:00+00')::int;
