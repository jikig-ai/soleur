-- 049_runtime_explainer_state.sql
-- PR-G (#3947) — Track first-time dismissal of the runtime onboarding
-- explainer banner. Nullable timestamptz; NULL = not yet dismissed.
--
-- Mirrors migration 012_onboarding_state.sql pattern (onboarding_completed_at,
-- pwa_banner_dismissed_at).

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS runtime_explainer_dismissed_at timestamptz NULL;

COMMENT ON COLUMN public.users.runtime_explainer_dismissed_at IS
  'NULL = banner shows on Today section first render. Non-NULL = dismissed. '
  'Set via useOnboarding.updateUserField. PR-G (#3947).';
