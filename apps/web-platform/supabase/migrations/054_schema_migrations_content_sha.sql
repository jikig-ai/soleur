-- 054_schema_migrations_content_sha.sql
-- #4241 — content-drift detection for dev-Supabase drift probe.
--
-- Adds a `content_sha` column to `public._schema_migrations` so the runner
-- can record the git blob SHA of the migration body it applied. The drift
-- probe (`.github/actions/dev-migration-drift-probe/action.yml`) compares
-- this against `git ls-tree origin/main`'s blob SHA for the same path,
-- catching the "same filename, different body" drift class that filename-
-- identity alone misses.
--
-- Additive, backward-compat: nullable column; existing rows stay NULL
-- (the runner does NOT backfill them — the only way an existing row's
-- content could change post-apply is via direct DDL, which is the very
-- drift the probe is designed to detect, but we have no record of what
-- was originally applied to compare against). New apply paths populate
-- `content_sha` going forward.
--
-- Per ADR-023, this migration applies to BOTH dev and prd. No RLS change
-- (table is service-role-only, mig 038 RLS posture unchanged).

ALTER TABLE public._schema_migrations
  ADD COLUMN IF NOT EXISTS content_sha text;

COMMENT ON COLUMN public._schema_migrations.content_sha IS
  'PR #4241: git blob SHA-1 of the migration file body at apply time '
  '(matches `git hash-object <file>`). NULL for rows applied before this '
  'column existed; backfill is intentionally skipped — the column tracks '
  'apply-time content, not retroactive content.';
