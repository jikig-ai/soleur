-- apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql
-- Remediates rls_disabled_in_public (lint 0013) on soleur-inngest-prd (pigsfuxruiopinouvjwy).
-- TARGET: the DEDICATED Inngest backing project ONLY. NEVER the web-platform project.
-- Applied as role `postgres` via the Supabase Management API (database/query). Idempotent.
--
-- SAFETY: RLS is enabled WITHOUT FORCE. Inngest connects as `postgres` (the table owner) over
-- the session pooler; a non-forced policy-set does not apply to the owner, so Inngest keeps
-- full access. We NEVER revoke from postgres/service_role. Zero policies: these tables are
-- service-internal and must never be reachable by anon/authenticated.

-- 0) Lock-acquisition + statement guards (data-integrity HIGH). ALTER TABLE ... ENABLE RLS takes
--    ACCESS EXCLUSIVE; on a live queue/telemetry DB a hot table (function_runs, queue_snapshot_
--    chunks, spans, history) may have an in-flight txn. lock_timeout makes a blocked ALTER FAIL
--    FAST (SQLSTATE 55P03) instead of stalling Inngest behind the lock queue. Because the
--    migration is idempotent + the workflow retries, a lock-timeout failure is a safe, retryable
--    outcome — NOT a stall. (Metadata-only DDL: no table rewrite.)
SET lock_timeout = '3s';
SET statement_timeout = '30s';

-- 0b) FAIL-CLOSED project-identity preflight (architecture P1; hr-dev-prd-distinct-supabase-projects).
--     A destructive REVOKE-all must NOT trust only the workflow URL's ref string. Abort unless an
--     Inngest-specific sentinel table exists — i.e. we are on the Inngest project, never web-platform.
DO $$
BEGIN
  IF to_regclass('public.goose_db_version') IS NULL
     OR to_regclass('public.function_runs') IS NULL THEN
    RAISE EXCEPTION 'ABORT: Inngest sentinel tables absent — refusing to run lockdown against a non-Inngest project';
  END IF;
END $$;

-- 0c) FAIL-CLOSED *negative* guard — the missing half of 0b (2026-07-15).
--     0b encodes the inference "goose tables exist ⟹ this is an Inngest-ONLY project".
--     The pre-cutover DARK Inngest backend (#6178 / ADR-100) FALSIFIED that inference:
--     it ran goose against soleur-dev, so soleur-dev — a CO-TENANTED project holding the
--     web-platform app's 52 dev tables — satisfies 0b and would let this schema-wide
--     REVOKE-all proceed, revoking anon/authenticated across every app table and
--     poisoning default privileges for every future dev migration. 0b alone cannot
--     distinguish "Inngest-only" from "Inngest + an app"; this guard adds the other half
--     by aborting when APP-owned tables are present.
--
--     INVARIANT: these three tables exist in the web-platform schema and MUST NEVER exist
--     on the dedicated Inngest project. They are chosen to be APP-DISTINCTIVE. Do NOT
--     substitute generic nouns like `users` or `conversations`: Inngest has no namespace
--     discipline and already ships `apps`, `events`, `functions`, `history`, `migrations`
--     and `traces`, so the day a goose migration ships `public.users` this guard would
--     RAISE on soleur-inngest-prd FOREVER, permanently killing the ADR-030 I8 self-heal.
--     Verified 2026-07-15: to_regclass of all three is NULL on pigsfuxruiopinouvjwy.
--
--     DEGRADATION MODE: if web-platform ever RENAMES all three of these tables, this guard
--     silently degrades to a no-op (it can only detect tables it names) and 0b's falsified
--     inference is all that remains. The workflow-level Management-API project-name
--     preflight in apply-inngest-rls.yml is the PRIMARY guard for exactly this reason;
--     this in-DB check is defense-in-depth, not the load-bearing control.
--
--     ORDERING IS LOAD-BEARING: this MUST precede the revoke loop below — a guard that
--     runs after the REVOKE aborts nothing. Asserted statically by inngest-rls.test.sh
--     (byte-offset of the guard < byte-offset of the first REVOKE).
DO $$
BEGIN
  IF to_regclass('public.kb_files') IS NOT NULL
     OR to_regclass('public.workspace_invitations') IS NOT NULL
     OR to_regclass('public.byok_delegation_acceptances') IS NOT NULL THEN
    RAISE EXCEPTION 'ABORT: web-platform app tables detected — this project is CO-TENANTED, not an Inngest-only project. A schema-wide REVOKE here would break the app. Use the table-scoped 0002_dev_inngest_tables_lockdown.sql instead.';
  END IF;
END $$;

-- 1) Enable RLS + revoke client-role grants on every current public base table + sequence.
--    Each ALTER/REVOKE is its own statement (autocommit) so a contended table holds only its own
--    ACCESS EXCLUSIVE lock, not all N at once. (If the Management-API endpoint wraps the whole
--    payload in one txn regardless, lock_timeout above remains the load-bearing mitigation.)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', r.tablename);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated;', r.tablename);
  END LOOP;
  -- Sequences: anon retaining USAGE/SELECT on serial/identity sequences is residual surface (security P2).
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON SEQUENCE public.%I FROM anon, authenticated;', r.sequencename);
  END LOOP;
  -- Materialized views: RLS does NOT apply to matviews, so a grant is their ONLY access control.
  -- Inngest ships none today, but a future version's matview in public would be anon-reachable on
  -- a grant alone — revoke defensively so the lockdown is complete for every relkind (data-integrity).
  FOR r IN SELECT matviewname FROM pg_matviews WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated;', r.matviewname);
  END LOOP;
END $$;

-- 2) Stop recurrence at the source. Supabase default privileges auto-GRANT anon/authenticated
--    full DML on every NEW table created by `postgres`; Inngest adds tables across versions.
--    Revoking the default (grantor = postgres, the role Inngest creates tables as) closes the
--    hole for future tables too. TABLES + SEQUENCES + FUNCTIONS (security P2). (The
--    supabase_admin-grantor default ACL governs Supabase's own tables, not Inngest's, and
--    postgres cannot alter it — intentionally omitted; verified postgres is not a supabase_admin member.)
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON FUNCTIONS FROM anon, authenticated;

-- ============================================================================================
-- BREAK-GLASS (NOT auto-applied — incident response only). If the apply ever breaks Inngest
-- (e.g. the connection role proves NOT to be the owner in prod), the FASTEST non-re-exposing
-- unblock is to DISABLE RLS while KEEPING grants revoked (anon stays locked out by missing grant):
--     ALTER TABLE public.<t> DISABLE ROW LEVEL SECURITY;   -- per affected table
-- Re-GRANTing anon/authenticated is the LAST resort (it re-opens the vulnerability) and must be
-- paired with an immediate re-apply of this lockdown. There is intentionally NO automated .down.
-- ============================================================================================
