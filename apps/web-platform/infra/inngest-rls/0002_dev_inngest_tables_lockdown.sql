-- apps/web-platform/infra/inngest-rls/0002_dev_inngest_tables_lockdown.sql
-- Remediates rls_disabled_in_public (lint 0013, advisor 2026-07-12) on soleur-dev
-- (mlwiodleouzwniehynfz) for the 14 tables created by the pre-cutover DARK Inngest
-- host (#6178 / ADR-100). Applied as role `postgres` via the Supabase Management API
-- (database/query) by .github/workflows/apply-inngest-rls-dev.yml. Idempotent.
--
-- ⚠️ TARGET: soleur-dev, which is CO-TENANTED — the dark Inngest backend shares the
-- `public` schema with the web-platform app's 52 dev tables. This artifact is
-- therefore TABLE-SCOPED and must stay that way. It is NOT a copy of 0001:
--
--   0001 -> soleur-inngest-prd: a DEDICATED, single-tenant Inngest project. There a
--           schema-wide revoke loop is correct, and `ALTER DEFAULT PRIVILEGES ...
--           REVOKE` is the durable recurrence fix for future Inngest tables.
--   0002 -> soleur-dev: NEITHER of those is safe here. See the two blocks below.
--
-- ❌ WHY THERE IS NO `ALTER DEFAULT PRIVILEGES ... REVOKE` IN THIS FILE (read before
--    adding one). On soleur-dev the grantor-`postgres` default ACL is what gives
--    anon/authenticated their grants on every NEW table an app migration creates.
--    Revoking it here would silently break EVERY FUTURE dev app migration — the dev
--    app would start returning `permission denied` on newly-created tables, with no
--    failing test to catch it. 0001 needs it because nothing but Inngest lives on its
--    project; 0002 must never have it. The shape guard in inngest-rls.test.sh FORBIDS
--    this statement in 0002's applied code and REQUIRES it in 0001's.
--    Recurrence on soleur-dev is instead handled by re-apply on a goose image-pin bump
--    (the bootstrap image is pinned at cloud-init-inngest.yml:330, so goose cannot run
--    without a deliberate, reviewable PR) — and permanently retired by the Phase-5 drop.
--
-- ❌ WHY THERE IS NO SCHEMA-WIDE `pg_tables` / `pg_class` LOOP. 0001 loops
--    `SELECT tablename FROM pg_tables WHERE schemaname='public'`. On this co-tenanted
--    project that loop would revoke anon/authenticated across the app's 52 dev tables
--    and kill the dev app. The target set below is an EXPLICIT 14-name allowlist; a
--    non-allowlisted table is structurally unreachable by this script.
--
-- SAFETY: RLS is enabled WITHOUT FORCE. Inngest connects as `postgres` (the table
-- owner, verified 2026-07-15: all 14 report pg_get_userbyid(relowner)='postgres') over
-- the session pooler; a non-forced policy-set does not apply to the owner, so Inngest
-- keeps full access. We NEVER revoke from postgres/service_role. Zero policies is
-- correct rather than a blanket-deny: the only client is Inngest as the owner, which
-- bypasses non-forced RLS entirely.
--
-- LIFETIME: transient. soleur-dev hosts Inngest's tables only until the cutover
-- (`op=arm` writes the prod DSN). Phase 5 drops the 14 and retires this file + its
-- workflow ATOMICALLY — if the tables are dropped while this file still applies, its
-- positive sentinel below RAISEs hourly forever.

-- 0) Lock-acquisition + statement guards (data-integrity HIGH). ALTER TABLE ... ENABLE
--    RLS takes ACCESS EXCLUSIVE. lock_timeout makes a blocked ALTER FAIL FAST (SQLSTATE
--    55P03) instead of stalling behind the lock queue. Because this migration is
--    idempotent and re-applied on merge, a lock-timeout failure is a safe, retryable
--    outcome — NOT a stall. (Metadata-only DDL: no table rewrite.)
SET lock_timeout = '3s';
SET statement_timeout = '30s';

-- 0b) FAIL-CLOSED positive sentinel. Abort unless the Inngest/goose sentinel tables
--     exist — i.e. refuse to run anywhere the dark backend has not provisioned.
--     NOTE: this sentinel is NOT a project-identity check. soleur-dev satisfies it AND
--     so does soleur-inngest-prd; "these tables exist" does NOT imply "Inngest-only
--     project" (the dark backend is exactly what falsified that inference for 0001).
--     Project identity is asserted by the workflow's Management-API name preflight
--     (apply-inngest-rls-dev.yml: GET /v1/projects/<ref> -> .name == 'soleur-dev'),
--     which binds ref->project via Supabase's own identity record.
DO $$
BEGIN
  IF to_regclass('public.goose_db_version') IS NULL
     OR to_regclass('public.function_runs') IS NULL THEN
    RAISE EXCEPTION 'ABORT: Inngest sentinel tables absent — refusing to run the dev Inngest lockdown against a project the dark backend has not provisioned';
  END IF;
END $$;

-- 1) Table-scoped lockdown over the EXPLICIT allowlist.
DO $$
DECLARE
  -- The 14 dark-Inngest tables on soleur-dev, re-derived from the live catalog
  -- 2026-07-15 (never from a migration grep). This list is STATIC by design: a 15th
  -- goose table is REPORTED below, not auto-locked — auto-locking would require a
  -- schema-wide scan, which is the exact thing that makes 0001 unsafe here.
  allow constant text[] := ARRAY[
    'apps',
    'event_batches',
    'events',
    'function_finishes',
    'function_runs',
    'functions',
    'goose_db_version',
    'history',
    'migrations',
    'queue_snapshot_chunks',
    'spans',
    'trace_runs',
    'traces',
    'worker_connections'
  ];
  t        text;
  seq      text;
  n_other  integer;
  n_locked integer := 0;
BEGIN
  FOREACH t IN ARRAY allow
  LOOP
    -- IF EXISTS semantics: a vanished table is a no-op, never an error. This keeps the
    -- artifact idempotent across the Phase-5 drop window.
    IF to_regclass(format('public.%I', t)) IS NULL THEN
      RAISE NOTICE 'skip: public.% is absent — no-op', t;
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
    n_locked := n_locked + 1;

    -- Sequences owned BY THIS ALLOWLISTED TABLE. Derived through pg_depend rather than
    -- hard-coded (a literal goose_db_version_id_seq goes stale the next time goose adds
    -- an identity column). anon retaining USAGE/SELECT on a serial sequence is residual
    -- surface. Scoped to relkind='S' and to this table — never a schema-wide scan.
    --
    -- BOTH classid AND refclassid are pinned to pg_class, and deptype to a/i, on purpose.
    -- A sequence carries several pg_depend rows: an ownership row on its table
    -- (refclassid=pg_class, deptype='a' for serial / 'i' for identity) AND a normal row on
    -- its SCHEMA (refclassid=pg_namespace, deptype='n'). Without the refclassid pin, the
    -- schema row's refobjid — a pg_namespace oid — is joined against pg_class.oid. Those
    -- counters share a space, so a collision could match an unrelated relation; if its
    -- relname happened to equal an allowlisted name, this loop would revoke on a sequence
    -- owned by an APP table. On a co-tenanted project that is precisely the blast radius
    -- this whole artifact exists to prevent, so the join is pinned rather than trusted.
    FOR seq IN
      SELECT s.relname
      FROM pg_class s
      JOIN pg_depend d  ON d.objid = s.oid
                       AND d.classid = 'pg_class'::regclass
                       AND d.refclassid = 'pg_class'::regclass
                       AND d.deptype IN ('a', 'i')
      JOIN pg_class tc  ON tc.oid = d.refobjid
      JOIN pg_namespace tn ON tn.oid = tc.relnamespace
      WHERE s.relkind = 'S'
        AND tn.nspname = 'public'
        AND tc.relname = t
    LOOP
      EXECUTE format('REVOKE ALL ON SEQUENCE public.%I FROM anon, authenticated', seq);
    END LOOP;
  END LOOP;

  RAISE NOTICE 'dev Inngest lockdown: % of % allowlisted tables locked down', n_locked, array_length(allow, 1);

  -- 2) REPORT-ONLY: non-allowlisted RLS-disabled public tables.
  --    This deliberately does NOT abort. An allowlist-driven revoke structurally cannot
  --    touch a non-allowlisted table, so aborting here would protect nothing — while
  --    ALSO halting the re-assertion of the 14 (v1's subset assertion did exactly that).
  --    On soleur-dev a non-zero count means either a 15th goose table (needs a human PR
  --    adding the name above — the window is time-to-PR, NOT self-healing) or an APP
  --    table that lost RLS (routed to the advisor scan, issue #3366). The workflow gate
  --    surfaces this count as a non-fatal signal.
  --    This query reads relkind='r' schema-wide, which is safe precisely because it
  --    emits no DDL — it only counts.
  SELECT count(*) INTO n_other
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND c.relrowsecurity = false
    AND NOT (c.relname = ANY(allow));

  IF n_other > 0 THEN
    RAISE WARNING 'REPORT (non-fatal): % non-allowlisted public table(s) have RLS disabled on this project — not touched by this allowlist-driven lockdown; triage via the advisor scan', n_other;
  ELSE
    RAISE NOTICE 'report: no non-allowlisted RLS-disabled public tables';
  END IF;
END $$;

-- Materialized views: out of scope here. RLS does not apply to matviews, so a grant is
-- their only access control — but Inngest ships none, and a schema-wide matview sweep
-- (as 0001 performs via its own catalog loop) would reach the APP's matviews on this
-- co-tenanted project. If a future Inngest version ships one, add its name to the
-- allowlist above and extend this file deliberately.

-- ============================================================================================
-- BREAK-GLASS (NOT auto-applied — incident response only). If this apply ever breaks the dark
-- Inngest host (e.g. the connection role proves NOT to be the owner), the FASTEST
-- non-re-exposing unblock is to DISABLE RLS while KEEPING grants revoked (anon stays locked
-- out by the missing grant):
--     ALTER TABLE public.<t> DISABLE ROW LEVEL SECURITY;   -- per affected table
-- Re-GRANTing anon/authenticated is the LAST resort (it re-opens the vulnerability) and must
-- be paired with an immediate re-apply of this lockdown. There is intentionally NO automated
-- .down. Do NOT "fix" a dev-app permission error by adding ALTER DEFAULT PRIVILEGES here — see
-- the header; that breaks future app migrations rather than fixing anything.
-- ============================================================================================
