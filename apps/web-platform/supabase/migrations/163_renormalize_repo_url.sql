-- 163_renormalize_repo_url.sql
-- Re-normalize conversations.repo_url AND workspaces.repo_url to the canonical
-- form of lib/repo-url.ts::normalizeRepoUrl. This SUPERSEDES the chain in
-- 031_normalize_repo_url.sql, which is merged and immutable (see
-- apps/web-platform/scripts/lint-migration-immutability.sh), so the corrected
-- chain ships as a new file. Both tables are rewritten in this one file because
-- readers compare a conversation's stored repo_url to
-- normalizeRepoUrl(workspaces.repo_url) (server/current-repo-url.ts,
-- server/ws-handler.ts); rewriting one side only would hide conversations.
-- users.repo_url was dropped by 112 and is not touched.
--
-- Defects of the 031 chain fixed here (the TS twin gained all three):
--   D1  no re-trim: a strip can expose whitespace it was shielding
--       ("http://a.aa .git" -> "http://a.aa ").
--   D2  the strip is not interleaving-complete (".../r/.git/.git" kept "/.git").
--   D3  trim() removes only U+0020; JS trim() also removes tab, newline, etc.
-- One tail strip, regexp '(/|\.git|[ \t\n\r\f\v])+$' (case-insensitive), is the
-- exact fixpoint of all three. Whitespace is an explicit ASCII class, never
-- [[:space:]] (locale-dependent). Left alone, as before: D4 (URL-parser effects:
-- %20 encoding, dot-segments, userinfo, port, numeric-host canonicalization),
-- D5 (exotic Unicode whitespace) and D6 (rows that are not scheme://host).
--
-- ELIGIBILITY: a row is rewritten only when this SQL is expected to equal what
-- normalizeRepoUrl returns for it (evidence: a Postgres-generated golden table in
-- test/repo-url-sql-parity.test.ts plus a fuzz of the JS port against the TS
-- function; this is empirical, not a proof). A SQL-only rewrite that differs from
-- the TS result (for example "https://github.com/o .git": TS gives ".../o%20",
-- SQL ".../o") would hide that user's conversations. Eligible means: ASCII only
-- (lower() is locale-dependent and TS punycodes non-ASCII hosts), no internal
-- whitespace in the trimmed input, at most 2048 characters (a parity bound; the
-- regexes are linear, so it is not a DoS guard), and a canonical result of a
-- clean http(s) shape: no userinfo, port, %, ?, #, dot-segment or empty segment,
-- a final host label that starts with a letter (no IPv4 canonicalization), and
-- path segments that start with [A-Za-z0-9_~-] (so a dot-leading segment such as
-- ".github" is left as stored). Ineligible rows are left untouched, exactly as 031
-- left non-URL rows.
--
-- Idempotent: the UPDATE guard is `repo_url <> canon_ok`; a second run is
-- UPDATE 0. The canonical expression is repeated verbatim (see the canon-expr
-- markers); OFFSET 0 in each LATERAL stops the planner inlining a step into every
-- reference, which cost about 25x per row on 100k rows. Exact-expression baseline
-- read on 2026-10-23 (an observation, not a guarantee): prd conversations 187 with
-- a url, workspaces 6, to_rewrite 0, skipped_but_changed 0, collisions 0.
--
-- A conversation collision on the unique index (user_id, repo_url, context_path)
-- (live rows only) is detected up front. The DO block raises with a COUNT only
-- and writes nothing; resolving it is a data decision (which conversation to
-- keep), then the release re-runs. LOCK TABLE (with a 5 s lock_timeout) closes
-- the race between that check and the UPDATE so a concurrent insert cannot turn
-- it into a mid-UPDATE 23505 whose DETAIL would print row data. The runner applies
-- the file in one transaction, so a lock timeout or a collision raise rolls back
-- every change and the ledger row; re-running the release is safe. The UPDATEs
-- also compare-and-swap on the value they read (t.repo_url = n.old_url), so a
-- concurrent write to workspaces.repo_url is never overwritten with the canonical
-- form of the old value.
--
-- Known consequences, all loud rather than silent and none present in prd:
--   - Archived conversations are rewritten too but sit outside the unique index; a
--     later unarchive of one whose rewritten value now equals a live sibling's
--     fails with 23505.
--   - If two same-installation solo workspaces end up with an equal repo_url,
--     server/resolve-founder-for-installation.ts returns `ambiguous` for them
--     (event dropped, page raised) instead of matching one.
--
-- verify/163 is deliberately strict and permanent: a future writer that bypasses
-- normalizeRepoUrl blocks the release where verify-migrations runs until the row
-- is fixed (it does not currently run on the workflow_run deploy arm, #9471).
-- verify/031 is untouched; its sentinel and idempotence probes stay red for a row
-- the old chain rewrites but this migration skips (internal whitespace, port,
-- userinfo, non-http, degenerate host, non-ASCII); the prd count of such rows was 0
-- when this file was written.
--
-- No grant, function or table is added; values are rewritten in place and
-- github_installation_id is never touched. Forward-fix rule: a defect in this
-- file ships as migration 164, never as an edit of 163 once it is merged. No
-- BEGIN/COMMIT, no CONCURRENTLY (the runner wraps each file in one transaction).

SET LOCAL lock_timeout = '5s';

LOCK TABLE public.conversations IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
  collisions integer;
BEGIN
  SELECT count(*) INTO collisions
    FROM (
      SELECT x.user_id, COALESCE(c.canon_ok, x.repo_url) AS effective, x.context_path
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
         AND x.context_path IS NOT NULL
         AND x.archived_at IS NULL
       GROUP BY x.user_id, COALESCE(c.canon_ok, x.repo_url), x.context_path
      HAVING count(*) > 1
    ) g;

  IF collisions > 0 THEN
    RAISE EXCEPTION '163 precondition failed: % collision group(s)', collisions;
  END IF;
END $$;

UPDATE public.conversations t
   SET repo_url = n.canon_ok
  FROM (
    SELECT x.id, x.repo_url AS old_url, c.canon_ok
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
  ) n
 WHERE n.id = t.id
   AND n.canon_ok IS NOT NULL
   AND t.repo_url = n.old_url
   AND t.repo_url <> n.canon_ok;

UPDATE public.workspaces t
   SET repo_url = n.canon_ok
  FROM (
    SELECT x.id, x.repo_url AS old_url, c.canon_ok
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
  ) n
 WHERE n.id = t.id
   AND n.canon_ok IS NOT NULL
   AND t.repo_url = n.old_url
   AND t.repo_url <> n.canon_ok;
