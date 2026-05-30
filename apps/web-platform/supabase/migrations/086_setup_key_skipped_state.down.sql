-- 086_setup_key_skipped_state.down.sql
-- Reverse of 086_setup_key_skipped_state.sql. Drops the onboarding-skip
-- flag column. A skipped keyless user reverts to being force-routed to
-- /setup-key on next login (the pre-085 behavior) — acceptable for a
-- deliberate rollback.

ALTER TABLE public.users
  DROP COLUMN IF EXISTS setup_key_skipped_at;
