-- 086_setup_key_skipped_state.sql
-- feat-skip-api-key-onboarding (#4642; PR #4640). Persists the user's
-- explicit "Set up later" choice on the /setup-key onboarding gate so the
-- effective-key-aware redirect gates (callback, accept-terms) stop
-- force-routing a skipped keyless user back to /setup-key.
--
-- LAWFUL_BASIS: contract (Art. 6(1)(b)) — operational onboarding-state flag.
--
-- Mirrors migration 049_runtime_explainer_state.sql (nullable timestamptz;
-- NULL = not skipped). Written ONLY by the service-role skip route
-- (POST /api/setup-key/skip). No GRANT: service role bypasses RLS, and
-- `authenticated` keeps the table-level SELECT default for the onboarding
-- fetch — a client-side UPDATE would silently no-op anyway (migration 006
-- REVOKEd UPDATE on public.users from authenticated except (email)).

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS setup_key_skipped_at timestamptz NULL;

COMMENT ON COLUMN public.users.setup_key_skipped_at IS
  'NULL = not skipped; non-NULL = user chose "Set up later" on /setup-key. '
  'Set via POST /api/setup-key/skip (service role). #4642.';
