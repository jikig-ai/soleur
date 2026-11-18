-- Prepared SQL only. Must run exclusively in an approved owned synthetic DB.
\set ON_ERROR_STOP on
SET statement_timeout = '30s';
SET lock_timeout = '5s';
-- No IF NOT EXISTS: a reused fixture namespace is a hard refusal.
CREATE SCHEMA codex_rehearsal;
REVOKE ALL ON SCHEMA codex_rehearsal FROM PUBLIC;
CREATE FUNCTION codex_rehearsal.id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
 SELECT ('00000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid
$$;
CREATE FUNCTION codex_rehearsal.assert(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'rehearsal assertion: %',label; END IF; END
$$;
CREATE FUNCTION codex_rehearsal.expect_error(statement text, expected text) RETURNS void LANGUAGE plpgsql AS $$
 DECLARE caught text; BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS caught=RETURNED_SQLSTATE; END;
 IF caught IS DISTINCT FROM expected THEN RAISE EXCEPTION 'expected %, got %',expected,coalesce(caught,'success'); END IF;
 END
$$;
CREATE TABLE codex_rehearsal.ids (label text PRIMARY KEY, value uuid NOT NULL);
CREATE TABLE codex_rehearsal.snapshots (label text PRIMARY KEY, state jsonb NOT NULL);
-- Full rows from every public/auth/storage table, dynamically discovered, with
-- duplicate rows preserved and order normalized. A table/column census detects
-- empty relation and structural loss too. Results never leave the owned DB.
CREATE FUNCTION codex_rehearsal.state() RETURNS jsonb LANGUAGE plpgsql AS $$
 DECLARE rel record; rows jsonb; result jsonb := '{}'::jsonb; columns jsonb;
 BEGIN
 FOR rel IN SELECT n.nspname, c.relname, c.relkind, c.oid FROM pg_class c
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('public','auth','storage') AND c.relkind IN ('r','p')
 ORDER BY n.nspname,c.relname LOOP
   EXECUTE format('SELECT coalesce(jsonb_agg(row_value ORDER BY row_value::text),''[]''::jsonb) FROM (SELECT to_jsonb(t) AS row_value FROM %I.%I t) full_rows',rel.nspname,rel.relname) INTO rows;
   SELECT coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'generated',a.attgenerated,'identity',a.attidentity) ORDER BY a.attnum),'[]'::jsonb)
    INTO columns FROM pg_attribute a WHERE a.attrelid=rel.oid AND a.attnum>0 AND NOT a.attisdropped;
   result := result || jsonb_build_object(rel.nspname||'.'||rel.relname,
      jsonb_build_object('kind',rel.relkind,'columns',columns,'rows',rows,'fingerprint',md5(rows::text)));
 END LOOP;
 RETURN result;
 END
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA codex_rehearsal FROM PUBLIC;
GRANT USAGE ON SCHEMA codex_rehearsal TO authenticated,service_role;
GRANT SELECT ON codex_rehearsal.ids TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION codex_rehearsal.id(integer),codex_rehearsal.assert(boolean,text),codex_rehearsal.expect_error(text,text) TO authenticated,service_role;
-- state() is deliberately owner-only; it reads complete auth/storage rows.
