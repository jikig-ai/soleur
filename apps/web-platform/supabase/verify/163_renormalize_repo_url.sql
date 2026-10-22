-- Verify 163_renormalize_repo_url.sql.
--
-- Contract (see run-verify.sh): every row returns check_name + bad.
-- Any row with bad > 0 fails the CI verify-migrations job where that job runs.
--
-- Deliberately strict and permanent: no excused residue. A future writer that
-- bypasses normalizeRepoUrl leaves an eligible non-canonical row here and blocks
-- release dispatches until that row is fixed. Rows the eligibility guard skips (internal
-- whitespace, port, userinfo, non-http, degenerate host) are excluded by
-- construction, exactly as the migration leaves them alone.
--
-- The canon-expr block is the migration's own expression, kept identical by
-- test/supabase-migrations/163-renormalize-repo-url.test.ts. The selftest row
-- runs it on the live engine against fixed inputs, so an engine or locale change
-- that alters regex semantics shows up here instead of silently on data.
-- users.repo_url was dropped by migration 112 and is not probed.
--
-- verify-migrations currently does not run on the workflow_run deploy arm (#9471), so
-- this file executes on a release dispatch and when run by hand, not on every merge.

SELECT 'conversations_noncanonical' AS check_name, count(*)::int AS bad
  FROM public.conversations x
  -- canon-expr begin
  CROSS JOIN LATERAL (SELECT regexp_replace(x.repo_url, '^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$', '', 'g') AS t OFFSET 0) a
  CROSS JOIN LATERAL (SELECT regexp_replace(
          lower(substring(a.t FROM '^([^/]*//[^/]+)')) || COALESCE(substring(a.t FROM '^[^/]*//[^/]+(/.*)$'), ''),
          '(/|\.git|[ \t\n\r\f\v])+$', '', 'i') AS canon OFFSET 0) b
  CROSS JOIN LATERAL (SELECT CASE
          WHEN a.t !~ '[ \t\n\r\f\v]'
           AND octet_length(a.t) = char_length(a.t)
           AND char_length(a.t) <= 2048
           AND b.canon ~ '^https?://([a-z0-9-]+[.])*[a-z][a-z0-9-]*(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$'
          THEN b.canon END AS canon_ok OFFSET 0) c
  -- canon-expr end
 WHERE x.repo_url IS NOT NULL
   AND c.canon_ok IS NOT NULL
   AND x.repo_url <> c.canon_ok
UNION ALL
SELECT 'workspaces_noncanonical', count(*)::int
  FROM public.workspaces x
  -- canon-expr begin
  CROSS JOIN LATERAL (SELECT regexp_replace(x.repo_url, '^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$', '', 'g') AS t OFFSET 0) a
  CROSS JOIN LATERAL (SELECT regexp_replace(
          lower(substring(a.t FROM '^([^/]*//[^/]+)')) || COALESCE(substring(a.t FROM '^[^/]*//[^/]+(/.*)$'), ''),
          '(/|\.git|[ \t\n\r\f\v])+$', '', 'i') AS canon OFFSET 0) b
  CROSS JOIN LATERAL (SELECT CASE
          WHEN a.t !~ '[ \t\n\r\f\v]'
           AND octet_length(a.t) = char_length(a.t)
           AND char_length(a.t) <= 2048
           AND b.canon ~ '^https?://([a-z0-9-]+[.])*[a-z][a-z0-9-]*(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$'
          THEN b.canon END AS canon_ok OFFSET 0) c
  -- canon-expr end
 WHERE x.repo_url IS NOT NULL
   AND c.canon_ok IS NOT NULL
   AND x.repo_url <> c.canon_ok
UNION ALL
SELECT 'canon_expr_selftest', count(*)::int
  FROM (VALUES
    ('http://a.aa '::text, 'http://a.aa'::text),
    ('https://github.com/Foo/Bar/ ', 'https://github.com/Foo/Bar'),
    ('HTTPS://GitHub.com/foo/bar.git/', 'https://github.com/foo/bar'),
    ('https://github.com/foo/bar/.git/.git', 'https://github.com/foo/bar'),
    (chr(9) || 'https://github.com/foo/bar' || chr(10), 'https://github.com/foo/bar'),
    ('https://github.com/foo/bar.GIT' || chr(9) || '/', NULL),
    ('https://github.com/Owner/Repo', 'https://github.com/Owner/Repo'),
    ('https://github.com/o .git', NULL),
    ('http://a.aa .git', NULL),
    ('https://u:p@Host/x', NULL),
    ('http://a.aa:80/x', NULL),
    ('http://a.aa/./x', NULL),
    ('https://0/x', NULL),
    ('http://.git', NULL),
    ('a://A', NULL),
    ('https://' || chr(304) || '.com/o/', NULL),
    ('https://' || chr(8490) || '.com/o/', NULL),
    ('foo/bar', NULL)
  ) AS x(repo_url, expected)
  -- canon-expr begin
  CROSS JOIN LATERAL (SELECT regexp_replace(x.repo_url, '^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$', '', 'g') AS t OFFSET 0) a
  CROSS JOIN LATERAL (SELECT regexp_replace(
          lower(substring(a.t FROM '^([^/]*//[^/]+)')) || COALESCE(substring(a.t FROM '^[^/]*//[^/]+(/.*)$'), ''),
          '(/|\.git|[ \t\n\r\f\v])+$', '', 'i') AS canon OFFSET 0) b
  CROSS JOIN LATERAL (SELECT CASE
          WHEN a.t !~ '[ \t\n\r\f\v]'
           AND octet_length(a.t) = char_length(a.t)
           AND char_length(a.t) <= 2048
           AND b.canon ~ '^https?://([a-z0-9-]+[.])*[a-z][a-z0-9-]*(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$'
          THEN b.canon END AS canon_ok OFFSET 0) c
  -- canon-expr end
 WHERE c.canon_ok IS DISTINCT FROM x.expected;
