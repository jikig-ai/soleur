-- Golden-table generator for test/repo-url-sql-parity.test.ts (PG_GOLDEN_163).
-- SELECT only. Run it against the DEV database (never prd), then paste the
-- output into PG_GOLDEN_163 (one JSON array of 4 JSON strings per line):
--
--   doppler run -p soleur -c dev -- sh -c \
--     'psql "$DATABASE_URL_POOLER" --no-psqlrc -X -tA -f test/fixtures/sql/normalize-repo-url-163-golden.sql'
--
-- Columns, each rendered with to_json so tab/newline and NULL survive the
-- line format: raw input, the OLD 031 chain, the 163 chain, the 163 backfill
-- outcome (canon_ok when eligible, else the row is left as is).
-- Control characters are built with chr(): 9 tab, 10 newline.
-- Never hand-edit the table with values produced by the JS port: the point of
-- this file is that Postgres, not the port, produces them.

SELECT '[' || COALESCE(to_json(x.repo_url)::text, 'null')
       || ',' || COALESCE(to_json(CASE WHEN substring(trim(x.repo_url) from '^([^/]*//[^/]+)') IS NOT NULL
                              THEN regexp_replace(regexp_replace(regexp_replace(
                                     -- chain-031 begin
                                     lower(substring(trim(x.repo_url) from '^([^/]*//[^/]+)'))
                                     || COALESCE(substring(trim(x.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
                                     -- chain-031 end
                                     '/+$', '', 'g'), '(\.git)+$', '', 'i'), '/+$', '', 'g')
                              ELSE x.repo_url END)::text, 'null')
       || ',' || COALESCE(to_json(CASE WHEN b.canon ~ '^[^/]*//[^/]+' THEN b.canon END)::text, 'null')
       || ',' || COALESCE(to_json(COALESCE(c.canon_ok, x.repo_url))::text, 'null') || ']' AS golden_row
  FROM (VALUES
    -- golden-rows begin
    ('http://a.aa .git'),
    ('http://a.aa /'),
    ('a://A .git'),
    ('http://a.aa' || chr(9) || '.git'),
    ('http://a.aa/' || chr(10) || '.git/'),
    ('https://github.com/foo/bar/.git/.git'),
    ('https://github.com/foo/bar.GIT' || chr(9) || '/'),
    (chr(9) || 'https://github.com/foo/bar' || chr(10)),
    ('https://x/y .git'),
    ('http://a.aa/ ' || chr(10) || '.git/ '),
    ('http://a.aa/./x'),
    ('http://a.aa:80/x'),
    ('http://.git'),
    ('http://a.aa '),
    ('https://github.com/Foo/Bar/ '),
    ('HTTPS://GitHub.com/foo/bar.git/'),
    ('https://github.com/o .git'),
    ('https://u:p@Host/x'),
    ('https://0/x'),
    ('a://A'),
    ('https://github.com/Owner/Repo'),
    ('foo/bar')
    -- golden-rows end
  ) AS x(repo_url)
  -- canon-expr begin
  CROSS JOIN LATERAL (SELECT regexp_replace(x.repo_url, '^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$', '', 'g') AS t) a
  CROSS JOIN LATERAL (SELECT regexp_replace(
          lower(substring(a.t FROM '^([^/]*//[^/]+)')) || COALESCE(substring(a.t FROM '^[^/]*//[^/]+(/.*)$'), ''),
          '(/|\.git|[ \t\n\r\f\v])+$', '', 'i') AS canon) b
  CROSS JOIN LATERAL (SELECT CASE
          WHEN a.t !~ '[ \t\n\r\f\v]'
           AND char_length(a.t) <= 2048
           AND b.canon ~ '^https?://([a-z0-9-]+[.])*[a-z][a-z0-9-]*(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$'
          THEN b.canon END AS canon_ok) c
  -- canon-expr end
;
