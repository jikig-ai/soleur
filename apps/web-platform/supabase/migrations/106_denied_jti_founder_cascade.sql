-- 106_denied_jti_founder_cascade.sql
-- GDPR Art-17 — make denied_jti rows deletable on founder erasure (#5372).
--
-- PROBLEM: migration 037 defined `denied_jti.founder_id uuid NOT NULL
-- REFERENCES public.users(id) ON DELETE RESTRICT`. RESTRICT means that if a
-- founder who has ANY revoked-JTI row tries to erase their account, the
-- auth.users → public.users delete cascade is BLOCKED by the FK, aborting the
-- Art-17 deletion. account-delete.ts has no anonymise/cascade step for
-- denied_jti, so the row is un-handled. (This is NOT the #5372 root cause —
-- the failing tests seed no denied_jti rows — but it is a real, independently-
-- motivated erasure gap surfaced while fixing #5372.)
--
-- FIX: switch the FK to ON DELETE CASCADE. When the founder is erased, their
-- denied_jti rows are deleted with them. This is correct because:
--   * the deny KEY is `jti` (PRIMARY KEY); `is_jti_denied(uuid)` checks by jti
--     ONLY and never reads founder_id — founder_id is metadata, not load-bearing
--     for deny-list correctness;
--   * once the founder's auth.users row is gone, every JWT bearing their jti is
--     invalid regardless (no user to authenticate), so the deny entry serves no
--     further purpose — keeping it would be retained PII past a confirmed erasure.
-- SET NULL is not an option: founder_id is NOT NULL.
--
-- denied_jti has NO WORM trigger (mig 037: zero policies, no triggers), so the
-- CASCADE delete is not blocked — and the new preflight-worm-cascade-
-- contradiction gate confirms this table is not a deletion-blocker.
--
-- Conventions: idempotent (DROP IF EXISTS + ADD re-creates deterministically),
-- no outer BEGIN/COMMIT (the runner wraps each migration in a transaction).

-- Precondition: surface schema-vs-ledger drift (#4338) with a named error
-- instead of a cryptic FK/ALTER failure.
DO $$
BEGIN
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 106 precondition failed: public.users is absent',
      DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md';
  END IF;
  IF to_regclass('public.denied_jti') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 106 precondition failed: public.denied_jti is absent (expected from migration 037)',
      DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md';
  END IF;
END $$;

ALTER TABLE public.denied_jti
  DROP CONSTRAINT IF EXISTS denied_jti_founder_id_fkey;

ALTER TABLE public.denied_jti
  ADD CONSTRAINT denied_jti_founder_id_fkey
  FOREIGN KEY (founder_id) REFERENCES public.users(id) ON DELETE CASCADE;
