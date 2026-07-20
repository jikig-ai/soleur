-- feat-guided-tour (#5743): persist guided-tour completion on the users row.
--
-- NULL = the user has never finished or skipped the onboarding tour (auto-start
-- eligible). Set to now() when the user finishes OR skips, so the tour never
-- auto-fires again. Manual relaunch remains available regardless of this value.
--
-- WRITE POSTURE: migration 006 REVOKEd authenticated UPDATE on public.users
-- (granting it back only on the narrow `email` column), so a client-side write to
-- this column silently affects 0 rows. Completion is persisted via the
-- service-role route POST /api/tour/complete. This migration adds the column and
-- a COMMENT only — it deliberately does NOT grant any client UPDATE.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS tour_completed_at timestamptz NULL;

COMMENT ON COLUMN public.users.tour_completed_at IS
  'feat-guided-tour: timestamp the user finished or skipped the onboarding tour; NULL = never run (auto-start eligible). Written only via the service-role /api/tour/complete route (client UPDATE on public.users is revoked, migration 006).';
