-- 141_users_cohort_key.sql (#8880)
--
-- LAWFUL_BASIS: Art. 6(1)(f) legitimate interest — cohort membership tag used
-- solely for alpha-cohort funnel/quiet measurement (the Phase 4 validation
-- protocol). Low-sensitivity label; disclosed in the runbook's tester-facing
-- notes and readable by the owning user via the existing owner-select policy.
--
-- WHAT. Nullable `cohort_key` on public.users — the cohort attribution the
-- invite-token mechanism cannot provide (invite tokens encode workspace
-- membership, not cohort). Written only by the service role via the
-- /api/admin/cohort PATCH route; migration 006 already REVOKEs authenticated
-- UPDATE on users.
--
-- SHAPE. `text` + CHECK `^[a-z0-9-]+$` — free-text tags like `alpha-3` vs
-- `alpha-03` would silently fragment the cohort; the CHECK plus route-side
-- lowercase normalization keep the tag space canonical.
--
-- DOWNTIME. None: nullable column, no default, no table rewrite; the inline
-- CHECK validates existing rows trivially (all NULL).

BEGIN;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS cohort_key text
    CHECK (cohort_key ~ '^[a-z0-9-]+$');

COMMENT ON COLUMN public.users.cohort_key IS
  'Cohort membership tag (e.g. alpha). Written by service role via /api/admin/cohort only. LAWFUL_BASIS: Art. 6(1)(f).';

COMMIT;
