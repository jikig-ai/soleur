-- Verify 031_normalize_repo_url.sql.
--
-- Contract (see run-verify.sh): every row returns `check_name` + `bad`.
-- Any row with `bad > 0` fails the CI verify-migrations job.
--
-- Sentinels reject any repo_url that still carries a form 031 was meant
-- to strip: `.git`/`.GIT` suffix, trailing slash, or uppercase scheme/host.
-- Idempotence probes replay the migration's WHERE clause as a SELECT — a
-- second run would UPDATE zero rows when the data is canonical.

SELECT 'users_sentinel' AS check_name,
       count(*)::int AS bad
  FROM public.users
 WHERE repo_url IS NOT NULL
   AND (repo_url ~ '\.git$' OR repo_url ~ '\.GIT$'
        OR repo_url ~ '/$' OR repo_url ~ '^https://[^/]*[A-Z]')
UNION ALL
SELECT 'conversations_sentinel', count(*)::int
  FROM public.conversations
 WHERE repo_url IS NOT NULL
   AND (repo_url ~ '\.git$' OR repo_url ~ '\.GIT$'
        OR repo_url ~ '/$' OR repo_url ~ '^https://[^/]*[A-Z]')
UNION ALL
SELECT 'users_idempotence', count(*)::int
  FROM public.users u
 WHERE u.repo_url IS NOT NULL
   AND substring(trim(u.repo_url) from '^([^/]*//[^/]+)') IS NOT NULL
   AND u.repo_url <> regexp_replace(
     regexp_replace(
       regexp_replace(
         LOWER(substring(trim(u.repo_url) from '^([^/]*//[^/]+)'))
         || COALESCE(substring(trim(u.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
         '/+$', '', 'g'),
       '(\.git)+$', '', 'i'),
     '/+$', '', 'g')
UNION ALL
SELECT 'conversations_idempotence', count(*)::int
  FROM public.conversations c
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
