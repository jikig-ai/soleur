-- Verify 175_tom4_shape_iv_client_grant_revokes.sql — contract: check_name + bad (run-verify.sh).
-- For each shape-(iv) table, every client-reachable verb must be HELD by
-- neither anon nor authenticated post-apply; count held privileges -> 0.

SELECT 'revoked_denied_jti' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."denied_jti"',v.verb) OR has_table_privilege('authenticated','public."denied_jti"',v.verb)
UNION ALL
SELECT 'revoked_dsar_export_audit_pii', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."dsar_export_audit_pii"',v.verb) OR has_table_privilege('authenticated','public."dsar_export_audit_pii"',v.verb)
UNION ALL
SELECT 'revoked_mint_rate_window', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."mint_rate_window"',v.verb) OR has_table_privilege('authenticated','public."mint_rate_window"',v.verb)
UNION ALL
SELECT 'revoked_pending_checkout_sessions', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."pending_checkout_sessions"',v.verb) OR has_table_privilege('authenticated','public."pending_checkout_sessions"',v.verb)
UNION ALL
SELECT 'revoked_tc_acceptances', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."tc_acceptances"',v.verb) OR has_table_privilege('authenticated','public."tc_acceptances"',v.verb)
UNION ALL
SELECT 'revoked_tenant_deploy_audit', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."tenant_deploy_audit"',v.verb) OR has_table_privilege('authenticated','public."tenant_deploy_audit"',v.verb)
UNION ALL
SELECT 'revoked_workspace_member_actions', count(*)::int FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE has_table_privilege('anon','public."workspace_member_actions"',v.verb) OR has_table_privilege('authenticated','public."workspace_member_actions"',v.verb)
UNION ALL
SELECT 'service_role_retained_workspace_member_actions', count(*)::int FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_member_actions"',v.verb);
