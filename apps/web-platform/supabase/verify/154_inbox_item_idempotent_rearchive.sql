-- Verify 154_inbox_item_idempotent_rearchive.sql (#9284).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (run-verify.sh parses tab-separated (check_name TEXT,
-- bad INT) rows under ON_ERROR_STOP=1).
--
-- WHY THIS FILE EXISTS. The idempotent re-archive early-return is a
-- bulk-path safety property a later CREATE OR REPLACE could silently drop.

-- (1) Idempotent early-return present in the live body.
SELECT 'idempotent_rearchive' AS check_name,
       CASE WHEN pg_get_functiondef(
              'public.set_inbox_item_state(uuid,text)'::regprocedure)
                 LIKE '%status = ''archived'' THEN RETURN%'
            THEN 0 ELSE 1 END AS bad;

-- (2) The archive-guard still fires on un-acted action_required.
SELECT 'archive_guard_intact' AS check_name,
       CASE WHEN pg_get_functiondef(
              'public.set_inbox_item_state(uuid,text)'::regprocedure)
                 LIKE '%cannot archive an un-acted action_required item%'
            THEN 0 ELSE 1 END AS bad;
