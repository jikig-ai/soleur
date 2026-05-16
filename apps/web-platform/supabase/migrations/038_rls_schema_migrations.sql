-- 038_rls_schema_migrations.sql
-- Clears Supabase advisor lint `rls_disabled_in_public` on
-- public._schema_migrations (alert 2026-05-03, soleur-dev
-- project ref mlwiodleouzwniehynfz). Pre-fix anon-key probe
-- confirmed SELECT/INSERT/DELETE were possible.
--
-- Pattern: enable RLS with zero policies (matches migration 030
-- precedent for processed_stripe_events). The runner script
-- run-migrations.sh connects via psql as the `postgres` role,
-- which OWNS this table and is RLS-exempt by default. No runner
-- change required; no application code reads this table.
--
-- DO NOT add `FORCE ROW LEVEL SECURITY` — owner-bypass is the
-- load-bearing invariant; FORCE would break the runner's per-
-- migration INSERT INTO public._schema_migrations.
--
-- DO NOT add a permissive `anon` policy. Per learning
-- knowledge-base/project/learnings/security-issues/rls-column-takeover-github-username-20260407.md,
-- permissive RLS is row-level, not column-level — re-exposes the
-- full migration history.

ALTER TABLE public._schema_migrations ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public._schema_migrations IS
  'Migration runner tracking table. Service-role / postgres-role only '
  '(zero policies; RLS-empty for anon and authenticated). Owner-bypass '
  'is load-bearing — do NOT add FORCE ROW LEVEL SECURITY. See migration 038.';
