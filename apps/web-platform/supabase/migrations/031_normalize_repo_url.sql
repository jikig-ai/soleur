-- 031_normalize_repo_url.sql
-- Backfill users.repo_url AND conversations.repo_url to the canonical form
-- produced by lib/repo-url.ts::normalizeRepoUrl. Coupling invariant documented
-- in 029_conversations_repo_url.sql COMMENT -- any normalization of
-- users.repo_url MUST also rewrite conversations.repo_url in the same file
-- or previously-connected conversations go dark.
--
-- Canonical form (must match lib/repo-url.ts byte-for-byte):
--   1. trim() leading/trailing whitespace
--   2. Lowercase scheme + host only (preserve owner/repo path case)
--   3. Strip trailing / (one or more) -- MUST run before .git strip so
--      `.../Repo.git/` normalizes via `.../Repo.git` -> `.../Repo`.
--   4. Strip trailing (.git)+ (case-insensitive, anchored) -- matches one
--      or more repetitions so `bar.git.git` collapses in one pass
--      (idempotence guarantee).
--   5. Strip any trailing / the .git strip may have exposed (defensive).
--
-- Idempotent: the WHERE predicate `repo_url <> <normalized-expr>` ensures
-- already-canonical rows are untouched. Second run is `UPDATE 0`.
--
-- CONCURRENTLY is NOT used. Supabase's migration runner wraps each file in
-- a transaction (SQLSTATE 25001). UPDATE is transaction-safe. Pattern matches
-- migrations 025, 027, 029 -- see
-- knowledge-base/project/learnings/integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md.
--
-- No NOT NULL transition. Column stays nullable (consistent with 029).
-- Disconnected users (repo_url IS NULL) stay NULL -- the backfill is
-- best-effort, not total. See
-- knowledge-base/project/learnings/2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md.
--
-- The last guard (`substring(... '^([^/]*//[^/]+)') IS NOT NULL`) skips
-- rows whose repo_url doesn't parse as scheme://host. Those are pre-existing
-- garbage; hands-off is safer than rewriting.

UPDATE public.users u
   SET repo_url = regexp_replace(
     regexp_replace(
       regexp_replace(
         LOWER(substring(trim(u.repo_url) from '^([^/]*//[^/]+)'))
         || COALESCE(substring(trim(u.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
         '/+$', '', 'g'),
       '(\.git)+$', '', 'i'),
     '/+$', '', 'g')
 WHERE u.repo_url IS NOT NULL
   AND substring(trim(u.repo_url) from '^([^/]*//[^/]+)') IS NOT NULL
   AND u.repo_url <> regexp_replace(
     regexp_replace(
       regexp_replace(
         LOWER(substring(trim(u.repo_url) from '^([^/]*//[^/]+)'))
         || COALESCE(substring(trim(u.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
         '/+$', '', 'g'),
       '(\.git)+$', '', 'i'),
     '/+$', '', 'g');

UPDATE public.conversations c
   SET repo_url = regexp_replace(
     regexp_replace(
       regexp_replace(
         LOWER(substring(trim(c.repo_url) from '^([^/]*//[^/]+)'))
         || COALESCE(substring(trim(c.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
         '/+$', '', 'g'),
       '(\.git)+$', '', 'i'),
     '/+$', '', 'g')
 WHERE c.repo_url IS NOT NULL
   AND substring(trim(c.repo_url) from '^([^/]*//[^/]+)') IS NOT NULL
   AND c.repo_url <> regexp_replace(
     regexp_replace(
       regexp_replace(
         LOWER(substring(trim(c.repo_url) from '^([^/]*//[^/]+)'))
         || COALESCE(substring(trim(c.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
         '/+$', '', 'g'),
       '(\.git)+$', '', 'i'),
     '/+$', '', 'g');
