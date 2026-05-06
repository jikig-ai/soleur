-- 038_rls_schema_migrations.sql
-- Clear Supabase advisor lint `rls_disabled_in_public` on
-- public._schema_migrations (alert dated 2026-05-03 on soleur-dev,
-- project ref mlwiodleouzwniehynfz).
--
-- Pre-fix exposure (verified live with anon key on 2026-05-06):
--   - anon SELECT: 200 OK with all 40 migration filenames
--   - anon INSERT: 201 Created (arbitrary filename accepted)
--   - anon DELETE: 204 No Content (matched rows removed)
-- A malicious DELETE would force the runner to re-attempt an applied
-- migration; many migrations are not idempotent (`CREATE TABLE`
-- without IF NOT EXISTS, ALTER TABLE ADD COLUMN), so this is a
-- direct prd-deploy DoS vector available to any internet user with
-- the public Soleur URL.
--
-- Fix pattern: enable RLS, zero policies. Matches migration 030
-- (processed_stripe_events) for service-role-only tables.
--   - The migration runner (apps/web-platform/scripts/run-migrations.sh)
--     uses psql over DATABASE_URL, which connects as the postgres role
--     and is RLS-exempt. No runner change required.
--   - Service-role HTTP clients bypass RLS via the Authorization
--     header (no application code reads this table; verified by
--     `rg "_schema_migrations" apps/ plugins/ scripts/`).
--   - anon and authenticated roles are denied by default once RLS is
--     on with zero policies — both reads and writes return empty/403.
--
-- Forward-only. Rollback path: `ALTER TABLE public._schema_migrations
-- DISABLE ROW LEVEL SECURITY;` — re-exposes the lint surface, do NOT
-- run unprompted.
--
-- CONCURRENTLY / VACUUM / ALTER SYSTEM are not used; the migration
-- is transaction-safe per the Supabase migration runner contract
-- (see comments in 025, 027, 028, 029, 035).
--
-- DO NOT add `ALTER TABLE ... FORCE ROW LEVEL SECURITY`. The runner
-- (apps/web-platform/scripts/run-migrations.sh) connects as the
-- `postgres` role, which OWNS this table. Postgres docs: row
-- security policies do not apply to the table owner unless FORCE
-- is set. FORCE would break the runner's INSERT at line 104/139.
--
-- DO NOT add a permissive SELECT policy for `anon`. Per learning
-- knowledge-base/project/learnings/security-issues/rls-column-takeover-github-username-20260407.md,
-- permissive RLS is row-level (not column-level) — a single permissive
-- policy would re-expose the entire migration history to any internet
-- user with the anon key, undoing this fix.

ALTER TABLE public._schema_migrations ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public._schema_migrations IS
  'Migration runner tracking table. Service-role-only / postgres-role-only '
  'access (no policies; RLS-empty for anon and authenticated roles). '
  'Written by apps/web-platform/scripts/run-migrations.sh via psql/'
  'DATABASE_URL as the postgres role, which OWNS the table and is '
  'therefore RLS-exempt by default (do not add FORCE ROW LEVEL '
  'SECURITY — it would break the runner). See migration 038.';
