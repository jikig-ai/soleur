-- 163_renormalize_repo_url.sql
-- Re-normalize conversations.repo_url AND workspaces.repo_url to the canonical
-- form of lib/repo-url.ts::normalizeRepoUrl. This SUPERSEDES the chain in
-- 031_normalize_repo_url.sql, which is merged and immutable (see
-- apps/web-platform/scripts/lint-migration-immutability.sh), so the corrected
-- chain ships as a new file. Coupling invariant (029 COMMENT): both tables are
-- rewritten in this one file, or conversations go dark. users.repo_url was
-- dropped by 112 and is not touched.
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
-- ELIGIBILITY: a row is rewritten only when this SQL provably equals what
-- normalizeRepoUrl returns for it. Readers compare a conversation's stored value
-- to normalizeRepoUrl(workspaces.repo_url), so a SQL-only rewrite that differs
-- from the TS result (for example "https://github.com/o .git": TS gives
-- ".../o%20", SQL ".../o") would hide that user's conversations. Eligible =
-- no internal whitespace in the trimmed input, at most 2048 characters, and a
-- canonical result of a clean http(s) shape (no userinfo, port, %, ?, #,
-- dot-segment or empty segment, letter-bearing final host label). Ineligible
-- rows are left untouched, exactly as 031 left non-URL rows.
--
-- Idempotent: the UPDATE guard is `repo_url <> canon_ok`; a second run is
-- UPDATE 0. Observed 2026-10-22 (an observation, not a guarantee): prod had no
-- row to rewrite in either table (conversations 187 with a url, workspaces 6).
--
-- A conversation collision on the unique index (user_id, repo_url, context_path)
-- (live rows only) is detected up front. The DO block raises with a COUNT only
-- and writes nothing; resolving it is a data decision (which conversation to
-- keep), then the release re-runs. LOCK TABLE (with a 5 s lock_timeout) closes
-- the race between that check and the UPDATE so a concurrent insert cannot turn
-- it into a mid-UPDATE 23505 whose DETAIL would print row data.
--
-- verify/163 is deliberately strict and permanent: a future writer that bypasses
-- normalizeRepoUrl blocks deploys until the row is fixed. verify/031 is untouched;
-- its input-guarded idempotence probe would stay red for a row the old chain
-- rewrites but this migration skips (internal whitespace, port, userinfo, non-http
-- or degenerate host), so the baseline for such rows must be 0 before merge.
--
-- No grant, function or table is added; values are rewritten in place and
-- github_installation_id is never touched. Forward-fix rule: a defect in this
-- file ships as migration 164, never as an edit of 163. No BEGIN/COMMIT, no
-- CONCURRENTLY (the runner wraps each file in one transaction).

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
    SELECT x.id, c.canon_ok
      FROM public.conversations x
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
     WHERE x.repo_url IS NOT NULL
  ) n
 WHERE n.id = t.id
   AND n.canon_ok IS NOT NULL
   AND t.repo_url <> n.canon_ok;

UPDATE public.workspaces t
   SET repo_url = n.canon_ok
  FROM (
    SELECT x.id, c.canon_ok
      FROM public.workspaces x
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
     WHERE x.repo_url IS NOT NULL
  ) n
 WHERE n.id = t.id
   AND n.canon_ok IS NOT NULL
   AND t.repo_url <> n.canon_ok;
