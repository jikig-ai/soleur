-- Down migration for 118_tour_completed_state.sql (feat-guided-tour #5743).
ALTER TABLE public.users
  DROP COLUMN IF EXISTS tour_completed_at;
