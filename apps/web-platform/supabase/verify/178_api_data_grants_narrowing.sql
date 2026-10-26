-- Verify 178_api_data_grants_narrowing.sql — contract: check_name + bad (run-verify.sh).
-- Per relation: every verb a revoked role must NOT hold counts held -> 0 over
-- the TABLE_VERBS probe universe; every kept grant asserts held -> bad counts
-- the misses. For `users` the census column grants assert has_column_privilege
-- (table-level UPDATE must be gone — the explicit negative row pins that a
-- column-level-only UPDATE does not satisfy has_table_privilege). The final
-- row is the complement sweep: a table-level REVOKE ALL does not clear
-- column-level attacl entries, so any api-role column privilege outside the
-- census (and not already covered by a held table-level verb — the fuzz
-- gate's coveredByTable exemption) counts bad.

-- _schema_migrations: zero api-role grants — all three roles revoked.
SELECT 'revoked__schema_migrations_all_roles' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."_schema_migrations"',v.verb) OR has_table_privilege('authenticated','public."_schema_migrations"',v.verb) OR has_table_privilege('service_role','public."_schema_migrations"',v.verb)
UNION ALL

-- api_keys: anon nothing; authenticated SELECT only; service_role full.
SELECT 'revoked_anon_api_keys', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."api_keys"',v.verb)
UNION ALL
SELECT 'revoked_authenticated_api_keys', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('authenticated','public."api_keys"',v.verb)
UNION ALL
SELECT 'kept_authenticated_select_api_keys', CASE WHEN has_table_privilege('authenticated','public."api_keys"','SELECT') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_service_role_api_keys', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."api_keys"',v.verb)
UNION ALL

-- audit_byok_use: same posture.
SELECT 'revoked_anon_audit_byok_use', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."audit_byok_use"',v.verb)
UNION ALL
SELECT 'revoked_authenticated_audit_byok_use', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('authenticated','public."audit_byok_use"',v.verb)
UNION ALL
SELECT 'kept_authenticated_select_audit_byok_use', CASE WHEN has_table_privilege('authenticated','public."audit_byok_use"','SELECT') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_service_role_audit_byok_use', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."audit_byok_use"',v.verb)
UNION ALL

-- audit_github_token_use: same posture.
SELECT 'revoked_anon_audit_github_token_use', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."audit_github_token_use"',v.verb)
UNION ALL
SELECT 'revoked_authenticated_audit_github_token_use', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('authenticated','public."audit_github_token_use"',v.verb)
UNION ALL
SELECT 'kept_authenticated_select_audit_github_token_use', CASE WHEN has_table_privilege('authenticated','public."audit_github_token_use"','SELECT') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_service_role_audit_github_token_use', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."audit_github_token_use"',v.verb)
UNION ALL

-- dsar_export_jobs: same posture (the GDPR portability SELECT is must-keep).
SELECT 'revoked_anon_dsar_export_jobs', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."dsar_export_jobs"',v.verb)
UNION ALL
SELECT 'revoked_authenticated_dsar_export_jobs', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('authenticated','public."dsar_export_jobs"',v.verb)
UNION ALL
SELECT 'kept_authenticated_select_dsar_export_jobs', CASE WHEN has_table_privilege('authenticated','public."dsar_export_jobs"','SELECT') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_service_role_dsar_export_jobs', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."dsar_export_jobs"',v.verb)
UNION ALL

-- flag_flip_audit: no client roles at all; service_role keeps full DML.
SELECT 'revoked_anon_flag_flip_audit', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."flag_flip_audit"',v.verb)
UNION ALL
SELECT 'revoked_authenticated_flag_flip_audit', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('authenticated','public."flag_flip_audit"',v.verb)
UNION ALL
SELECT 'kept_service_role_flag_flip_audit', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."flag_flip_audit"',v.verb)
UNION ALL

-- users: anon nothing; authenticated SELECT + column-level UPDATE census only.
SELECT 'revoked_anon_users', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."users"',v.verb)
UNION ALL
SELECT 'revoked_authenticated_users', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('authenticated','public."users"',v.verb)
UNION ALL
SELECT 'no_table_update_users_authenticated', CASE WHEN has_table_privilege('authenticated','public."users"','UPDATE') THEN 1 ELSE 0 END
UNION ALL
SELECT 'kept_authenticated_select_users', CASE WHEN has_table_privilege('authenticated','public."users"','SELECT') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_service_role_users', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."users"',v.verb)
UNION ALL
SELECT 'kept_users_col_update_email', CASE WHEN has_column_privilege('authenticated','public."users"','email','UPDATE') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_users_col_update_onboarding_completed_at', CASE WHEN has_column_privilege('authenticated','public."users"','onboarding_completed_at','UPDATE') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_users_col_update_pwa_banner_dismissed_at', CASE WHEN has_column_privilege('authenticated','public."users"','pwa_banner_dismissed_at','UPDATE') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_users_col_update_runtime_explainer_dismissed_at', CASE WHEN has_column_privilege('authenticated','public."users"','runtime_explainer_dismissed_at','UPDATE') THEN 0 ELSE 1 END
UNION ALL
SELECT 'kept_users_col_update_nudges_dismissed', CASE WHEN has_column_privilege('authenticated','public."users"','nudges_dismissed','UPDATE') THEN 0 ELSE 1 END
UNION ALL

-- Complement sweep over attacl (review fix, PR #11253): column-level grants
-- survive the table-level REVOKE ALL — assert none exist on the narrowed
-- relations for anon/authenticated beyond the users census columns, and none
-- that a held table-level verb does not already cover (mirrors the fuzz
-- gate's registered-or-covered rule).
SELECT 'no_uncovered_col_grants_narrowed', count(*)::int
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('anon'),('authenticated')) r(role)
CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('REFERENCES')) v(verb)
WHERE n.nspname = 'public'
  AND c.relname IN ('_schema_migrations','api_keys','audit_byok_use','audit_github_token_use','dsar_export_jobs','flag_flip_audit','users')
  AND a.attnum > 0 AND NOT a.attisdropped
  AND NOT (r.role = 'authenticated' AND c.relname = 'users' AND v.verb = 'UPDATE'
           AND a.attname IN ('email','onboarding_completed_at','pwa_banner_dismissed_at','runtime_explainer_dismissed_at','nudges_dismissed'))
  AND has_column_privilege(r.role, c.oid, a.attname, v.verb)
  AND NOT has_table_privilege(r.role, c.oid, v.verb);
