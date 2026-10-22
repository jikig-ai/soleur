-- Golden-table generator for test/repo-url-sql-parity.test.ts (PG_GOLDEN_163).
-- SELECT only. Run it from apps/web-platform against the DEV database (never
-- prd), then paste the output into PG_GOLDEN_163:
--
--   doppler run -p soleur -c dev -- sh -c \
--     'psql "$DATABASE_URL_POOLER" --no-psqlrc -X -tA -f test/fixtures/sql/normalize-repo-url-163-golden.sql'
--
-- Each output line is one JSON array of 4 values (a value can be JSON null), in
-- row order of the VALUES list below: raw input, the OLD 031 chain, the 163
-- chain, the 163 backfill outcome (canon_ok when eligible, else the row as is).
-- to_json keeps tab/newline and NULL intact on a line. Paste each line as one
-- array element of PG_GOLDEN_163 (add the trailing comma); a raw longer than 200
-- characters is written in the test as a repeat() expression of the same shape.
-- Control characters are built with chr(): 9 tab, 10 newline, 11 VT, 12 FF,
-- 13 CR, 160 NBSP, 304 U+0130, 8490 Kelvin sign.
-- Never fill the table with values produced by the JS port: the point of this
-- file is that Postgres, not the port, produces them. If the canon-expr block
-- below changes, the pinned hash in the test fails until this file is re-run.

SELECT '[' || COALESCE(to_json(x.repo_url)::text, 'null')
       || ',' || COALESCE(to_json(CASE WHEN substring(trim(x.repo_url) from '^([^/]*//[^/]+)') IS NOT NULL
                              THEN regexp_replace(regexp_replace(regexp_replace(
                                     lower(substring(trim(x.repo_url) from '^([^/]*//[^/]+)'))
                                     || COALESCE(substring(trim(x.repo_url) from '^[^/]*//[^/]+(/.*)$'), ''),
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
    ('foo/bar'),
    ('https://0/x/'),
    ('http://a.aa:80/x/'),
    ('http://a.aa/./x.git'),
    ('https://github.com/o%20x/'),
    ('https://github.com/o?q=1'),
    ('https://github.com/o#f'),
    ('https://github.com//o/'),
    ('https://github.com/.github.git'),
    ('https://h.1a/x/'),
    ('https://' || chr(304) || '.com/o/'),
    ('https://' || chr(8490) || '.com/o/'),
    ('https://github.com/o' || chr(160)),
    ('https://github.com/o' || chr(13)),
    ('https://github.com/o/' || chr(12) || chr(11)),
    ('https://My-Host.Example.io/my_repo/~x/Repo.git.git/'),
    ('https://h.io/' || repeat('a', 2034) || '/'),
    ('https://h.io/' || repeat('a', 2035) || '/')
    -- golden-rows end
  ) AS x(repo_url)
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
;
