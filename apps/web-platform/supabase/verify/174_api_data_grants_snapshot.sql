-- Verify 174_api_data_grants_snapshot.sql — contract: every row returns check_name + bad (run-verify.sh).
-- Asserts the SNAPSHOT's own declared grant set is effective post-apply: for each
-- (relation, role) pair the migration grants, every verb must hold via
-- has_table_privilege / has_sequence_privilege; column-level grants assert
-- has_column_privilege. Idempotent by construction (pure catalog reads).

SELECT 'grants__schema_migrations_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."_schema_migrations"',v.verb)
UNION ALL
SELECT 'grants__schema_migrations_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."_schema_migrations"',v.verb)
UNION ALL
SELECT 'grants__schema_migrations_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."_schema_migrations"',v.verb)
UNION ALL
SELECT 'grants_action_sends_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."action_sends"',v.verb)
UNION ALL
SELECT 'grants_action_sends_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."action_sends"',v.verb)
UNION ALL
SELECT 'grants_action_sends_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."action_sends"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_events_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER')) v(verb) WHERE NOT has_table_privilege('anon','public."agent_engine_events"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_events_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER')) v(verb) WHERE NOT has_table_privilege('authenticated','public."agent_engine_events"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_events_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."agent_engine_events"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_runs_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER')) v(verb) WHERE NOT has_table_privilege('anon','public."agent_engine_runs"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_runs_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER')) v(verb) WHERE NOT has_table_privilege('authenticated','public."agent_engine_runs"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_runs_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."agent_engine_runs"',v.verb)
UNION ALL
SELECT 'grants_api_keys_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."api_keys"',v.verb)
UNION ALL
SELECT 'grants_api_keys_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."api_keys"',v.verb)
UNION ALL
SELECT 'grants_api_keys_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."api_keys"',v.verb)
UNION ALL
SELECT 'grants_audit_byok_use_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."audit_byok_use"',v.verb)
UNION ALL
SELECT 'grants_audit_byok_use_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."audit_byok_use"',v.verb)
UNION ALL
SELECT 'grants_audit_byok_use_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."audit_byok_use"',v.verb)
UNION ALL
SELECT 'grants_audit_github_token_use_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."audit_github_token_use"',v.verb)
UNION ALL
SELECT 'grants_audit_github_token_use_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."audit_github_token_use"',v.verb)
UNION ALL
SELECT 'grants_audit_github_token_use_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."audit_github_token_use"',v.verb)
UNION ALL
SELECT 'grants_beta_contact_access_log_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."beta_contact_access_log"',v.verb)
UNION ALL
SELECT 'grants_beta_contact_access_log_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."beta_contact_access_log"',v.verb)
UNION ALL
SELECT 'grants_beta_contact_access_log_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."beta_contact_access_log"',v.verb)
UNION ALL
SELECT 'grants_beta_contact_stage_transitions_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."beta_contact_stage_transitions"',v.verb)
UNION ALL
SELECT 'grants_beta_contact_stage_transitions_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."beta_contact_stage_transitions"',v.verb)
UNION ALL
SELECT 'grants_beta_contact_stage_transitions_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."beta_contact_stage_transitions"',v.verb)
UNION ALL
SELECT 'grants_beta_contacts_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."beta_contacts"',v.verb)
UNION ALL
SELECT 'grants_beta_contacts_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."beta_contacts"',v.verb)
UNION ALL
SELECT 'grants_beta_contacts_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."beta_contacts"',v.verb)
UNION ALL
SELECT 'grants_byok_delegation_acceptances_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."byok_delegation_acceptances"',v.verb)
UNION ALL
SELECT 'grants_byok_delegation_acceptances_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."byok_delegation_acceptances"',v.verb)
UNION ALL
SELECT 'grants_byok_delegation_acceptances_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."byok_delegation_acceptances"',v.verb)
UNION ALL
SELECT 'grants_byok_delegation_withdrawals_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."byok_delegation_withdrawals"',v.verb)
UNION ALL
SELECT 'grants_byok_delegation_withdrawals_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."byok_delegation_withdrawals"',v.verb)
UNION ALL
SELECT 'grants_byok_delegation_withdrawals_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."byok_delegation_withdrawals"',v.verb)
UNION ALL
SELECT 'grants_byok_delegations_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."byok_delegations"',v.verb)
UNION ALL
SELECT 'grants_byok_delegations_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."byok_delegations"',v.verb)
UNION ALL
SELECT 'grants_byok_delegations_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."byok_delegations"',v.verb)
UNION ALL
SELECT 'grants_conversations_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."conversations"',v.verb)
UNION ALL
SELECT 'grants_conversations_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."conversations"',v.verb)
UNION ALL
SELECT 'grants_conversations_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."conversations"',v.verb)
UNION ALL
SELECT 'grants_denied_jti_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."denied_jti"',v.verb)
UNION ALL
SELECT 'grants_denied_jti_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."denied_jti"',v.verb)
UNION ALL
SELECT 'grants_denied_jti_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."denied_jti"',v.verb)
UNION ALL
SELECT 'grants_dsar_export_audit_pii_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."dsar_export_audit_pii"',v.verb)
UNION ALL
SELECT 'grants_dsar_export_audit_pii_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."dsar_export_audit_pii"',v.verb)
UNION ALL
SELECT 'grants_dsar_export_audit_pii_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."dsar_export_audit_pii"',v.verb)
UNION ALL
SELECT 'grants_dsar_export_jobs_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."dsar_export_jobs"',v.verb)
UNION ALL
SELECT 'grants_dsar_export_jobs_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."dsar_export_jobs"',v.verb)
UNION ALL
SELECT 'grants_dsar_export_jobs_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."dsar_export_jobs"',v.verb)
UNION ALL
SELECT 'grants_email_inbox_routes_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."email_inbox_routes"',v.verb)
UNION ALL
SELECT 'grants_email_suppression_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."email_suppression"',v.verb)
UNION ALL
SELECT 'grants_email_suppression_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."email_suppression"',v.verb)
UNION ALL
SELECT 'grants_email_suppression_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."email_suppression"',v.verb)
UNION ALL
SELECT 'grants_email_triage_items_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."email_triage_items"',v.verb)
UNION ALL
SELECT 'grants_email_triage_items_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."email_triage_items"',v.verb)
UNION ALL
SELECT 'grants_email_triage_items_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."email_triage_items"',v.verb)
UNION ALL
SELECT 'grants_flag_flip_audit_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."flag_flip_audit"',v.verb)
UNION ALL
SELECT 'grants_flag_flip_audit_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."flag_flip_audit"',v.verb)
UNION ALL
SELECT 'grants_flag_flip_audit_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."flag_flip_audit"',v.verb)
UNION ALL
SELECT 'grants_inbox_item_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."inbox_item"',v.verb)
UNION ALL
SELECT 'grants_inbox_item_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."inbox_item"',v.verb)
UNION ALL
SELECT 'grants_inbox_item_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."inbox_item"',v.verb)
UNION ALL
SELECT 'grants_interview_notes_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."interview_notes"',v.verb)
UNION ALL
SELECT 'grants_interview_notes_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."interview_notes"',v.verb)
UNION ALL
SELECT 'grants_interview_notes_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."interview_notes"',v.verb)
UNION ALL
SELECT 'grants_kb_files_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."kb_files"',v.verb)
UNION ALL
SELECT 'grants_kb_files_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."kb_files"',v.verb)
UNION ALL
SELECT 'grants_kb_files_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."kb_files"',v.verb)
UNION ALL
SELECT 'grants_kb_share_links_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."kb_share_links"',v.verb)
UNION ALL
SELECT 'grants_kb_share_links_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."kb_share_links"',v.verb)
UNION ALL
SELECT 'grants_kb_share_links_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."kb_share_links"',v.verb)
UNION ALL
SELECT 'grants_message_attachments_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."message_attachments"',v.verb)
UNION ALL
SELECT 'grants_message_attachments_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."message_attachments"',v.verb)
UNION ALL
SELECT 'grants_message_attachments_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."message_attachments"',v.verb)
UNION ALL
SELECT 'grants_messages_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."messages"',v.verb)
UNION ALL
SELECT 'grants_messages_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."messages"',v.verb)
UNION ALL
SELECT 'grants_messages_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."messages"',v.verb)
UNION ALL
SELECT 'grants_mint_rate_window_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."mint_rate_window"',v.verb)
UNION ALL
SELECT 'grants_mint_rate_window_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."mint_rate_window"',v.verb)
UNION ALL
SELECT 'grants_mint_rate_window_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."mint_rate_window"',v.verb)
UNION ALL
SELECT 'grants_organizations_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."organizations"',v.verb)
UNION ALL
SELECT 'grants_organizations_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."organizations"',v.verb)
UNION ALL
SELECT 'grants_organizations_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."organizations"',v.verb)
UNION ALL
SELECT 'grants_outbound_sends_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."outbound_sends"',v.verb)
UNION ALL
SELECT 'grants_outbound_sends_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."outbound_sends"',v.verb)
UNION ALL
SELECT 'grants_outbound_sends_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."outbound_sends"',v.verb)
UNION ALL
SELECT 'grants_pending_checkout_sessions_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."pending_checkout_sessions"',v.verb)
UNION ALL
SELECT 'grants_pending_checkout_sessions_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."pending_checkout_sessions"',v.verb)
UNION ALL
SELECT 'grants_pending_checkout_sessions_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."pending_checkout_sessions"',v.verb)
UNION ALL
SELECT 'grants_probe_tokens_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."probe_tokens"',v.verb)
UNION ALL
SELECT 'grants_probe_tokens_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."probe_tokens"',v.verb)
UNION ALL
SELECT 'grants_probe_tokens_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."probe_tokens"',v.verb)
UNION ALL
SELECT 'grants_processed_github_events_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."processed_github_events"',v.verb)
UNION ALL
SELECT 'grants_processed_github_events_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."processed_github_events"',v.verb)
UNION ALL
SELECT 'grants_processed_github_events_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."processed_github_events"',v.verb)
UNION ALL
SELECT 'grants_processed_resend_events_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."processed_resend_events"',v.verb)
UNION ALL
SELECT 'grants_processed_resend_events_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."processed_resend_events"',v.verb)
UNION ALL
SELECT 'grants_processed_resend_events_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."processed_resend_events"',v.verb)
UNION ALL
SELECT 'grants_processed_stripe_events_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."processed_stripe_events"',v.verb)
UNION ALL
SELECT 'grants_processed_stripe_events_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."processed_stripe_events"',v.verb)
UNION ALL
SELECT 'grants_processed_stripe_events_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."processed_stripe_events"',v.verb)
UNION ALL
SELECT 'grants_push_subscriptions_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."push_subscriptions"',v.verb)
UNION ALL
SELECT 'grants_push_subscriptions_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."push_subscriptions"',v.verb)
UNION ALL
SELECT 'grants_push_subscriptions_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."push_subscriptions"',v.verb)
UNION ALL
SELECT 'grants_routine_run_progress_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."routine_run_progress"',v.verb)
UNION ALL
SELECT 'grants_routine_run_progress_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."routine_run_progress"',v.verb)
UNION ALL
SELECT 'grants_routine_run_progress_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."routine_run_progress"',v.verb)
UNION ALL
SELECT 'grants_routine_runs_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."routine_runs"',v.verb)
UNION ALL
SELECT 'grants_routine_runs_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."routine_runs"',v.verb)
UNION ALL
SELECT 'grants_routine_runs_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."routine_runs"',v.verb)
UNION ALL
SELECT 'grants_runtime_mint_intent_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."runtime_mint_intent"',v.verb)
UNION ALL
SELECT 'grants_scope_grants_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."scope_grants"',v.verb)
UNION ALL
SELECT 'grants_scope_grants_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."scope_grants"',v.verb)
UNION ALL
SELECT 'grants_scope_grants_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."scope_grants"',v.verb)
UNION ALL
SELECT 'grants_statutory_repin_send_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."statutory_repin_send"',v.verb)
UNION ALL
SELECT 'grants_tc_acceptances_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."tc_acceptances"',v.verb)
UNION ALL
SELECT 'grants_tc_acceptances_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."tc_acceptances"',v.verb)
UNION ALL
SELECT 'grants_tc_acceptances_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."tc_acceptances"',v.verb)
UNION ALL
SELECT 'grants_team_names_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."team_names"',v.verb)
UNION ALL
SELECT 'grants_team_names_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."team_names"',v.verb)
UNION ALL
SELECT 'grants_team_names_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."team_names"',v.verb)
UNION ALL
SELECT 'grants_template_authorizations_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."template_authorizations"',v.verb)
UNION ALL
SELECT 'grants_template_authorizations_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."template_authorizations"',v.verb)
UNION ALL
SELECT 'grants_template_authorizations_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."template_authorizations"',v.verb)
UNION ALL
SELECT 'grants_tenant_deploy_audit_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."tenant_deploy_audit"',v.verb)
UNION ALL
SELECT 'grants_tenant_deploy_audit_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."tenant_deploy_audit"',v.verb)
UNION ALL
SELECT 'grants_tenant_deploy_audit_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."tenant_deploy_audit"',v.verb)
UNION ALL
SELECT 'grants_tool_attempts_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."tool_attempts"',v.verb)
UNION ALL
SELECT 'grants_tool_attempts_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."tool_attempts"',v.verb)
UNION ALL
SELECT 'grants_tool_attempts_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."tool_attempts"',v.verb)
UNION ALL
SELECT 'grants_user_concurrency_slots_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."user_concurrency_slots"',v.verb)
UNION ALL
SELECT 'grants_user_concurrency_slots_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."user_concurrency_slots"',v.verb)
UNION ALL
SELECT 'grants_user_concurrency_slots_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."user_concurrency_slots"',v.verb)
UNION ALL
SELECT 'grants_user_session_state_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."user_session_state"',v.verb)
UNION ALL
SELECT 'grants_user_session_state_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."user_session_state"',v.verb)
UNION ALL
SELECT 'grants_user_session_state_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."user_session_state"',v.verb)
UNION ALL
SELECT 'grants_users_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."users"',v.verb)
UNION ALL
SELECT 'grants_users_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."users"',v.verb)
UNION ALL
SELECT 'grants_users_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."users"',v.verb)
UNION ALL
SELECT 'grants_workspace_activity_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_activity"',v.verb)
UNION ALL
SELECT 'grants_workspace_activity_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_activity"',v.verb)
UNION ALL
SELECT 'grants_workspace_activity_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_activity"',v.verb)
UNION ALL
SELECT 'grants_workspace_egress_audit_rollup_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_egress_audit_rollup"',v.verb)
UNION ALL
SELECT 'grants_workspace_engine_settings_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_engine_settings"',v.verb)
UNION ALL
SELECT 'grants_workspace_engine_settings_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_engine_settings"',v.verb)
UNION ALL
SELECT 'grants_workspace_engine_settings_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_engine_settings"',v.verb)
UNION ALL
SELECT 'grants_workspace_invitations_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_invitations"',v.verb)
UNION ALL
SELECT 'grants_workspace_invitations_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_invitations"',v.verb)
UNION ALL
SELECT 'grants_workspace_invitations_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_invitations"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_actions_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_member_actions"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_actions_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_member_actions"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_actions_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_member_actions"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_attestations_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_member_attestations"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_attestations_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_member_attestations"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_attestations_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_member_attestations"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_removals_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_member_removals"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_removals_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_member_removals"',v.verb)
UNION ALL
SELECT 'grants_workspace_member_removals_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_member_removals"',v.verb)
UNION ALL
SELECT 'grants_workspace_members_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_members"',v.verb)
UNION ALL
SELECT 'grants_workspace_members_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_members"',v.verb)
UNION ALL
SELECT 'grants_workspace_members_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_members"',v.verb)
UNION ALL
SELECT 'grants_workspaces_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspaces"',v.verb)
UNION ALL
SELECT 'grants_workspaces_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspaces"',v.verb)
UNION ALL
SELECT 'grants_workspaces_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspaces"',v.verb)
UNION ALL
SELECT 'grants_worktree_write_lease_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."worktree_write_lease"',v.verb)
UNION ALL
SELECT 'grants_worktree_write_lease_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."worktree_write_lease"',v.verb)
UNION ALL
SELECT 'grants_worktree_write_lease_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."worktree_write_lease"',v.verb)
UNION ALL
SELECT 'grants_routine_runs_latest_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."routine_runs_latest"',v.verb)
UNION ALL
SELECT 'grants_routine_runs_latest_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."routine_runs_latest"',v.verb)
UNION ALL
SELECT 'grants_routine_runs_latest_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."routine_runs_latest"',v.verb)
UNION ALL
SELECT 'grants_workspace_cost_aggregate_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('anon','public."workspace_cost_aggregate"',v.verb)
UNION ALL
SELECT 'grants_workspace_cost_aggregate_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('authenticated','public."workspace_cost_aggregate"',v.verb)
UNION ALL
SELECT 'grants_workspace_cost_aggregate_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('DELETE'),('INSERT'),('MAINTAIN'),('REFERENCES'),('SELECT'),('TRIGGER'),('TRUNCATE'),('UPDATE')) v(verb) WHERE NOT has_table_privilege('service_role','public."workspace_cost_aggregate"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_events_id_seq_anon' AS check_name, count(*)::int AS bad FROM (VALUES ('SELECT'),('UPDATE'),('USAGE')) v(verb) WHERE NOT has_sequence_privilege('anon','public."agent_engine_events_id_seq"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_events_id_seq_authenticated' AS check_name, count(*)::int AS bad FROM (VALUES ('SELECT'),('UPDATE'),('USAGE')) v(verb) WHERE NOT has_sequence_privilege('authenticated','public."agent_engine_events_id_seq"',v.verb)
UNION ALL
SELECT 'grants_agent_engine_events_id_seq_service_role' AS check_name, count(*)::int AS bad FROM (VALUES ('SELECT'),('UPDATE'),('USAGE')) v(verb) WHERE NOT has_sequence_privilege('service_role','public."agent_engine_events_id_seq"',v.verb)
UNION ALL
SELECT 'colgrants_workspaces_authenticated_select' AS check_name, count(*)::int AS bad FROM (VALUES ('created_at'),('id'),('name'),('organization_id'),('repo_error'),('repo_last_synced_at'),('repo_provider'),('repo_status'),('repo_url')) c(col) WHERE NOT has_column_privilege('authenticated','public."workspaces"',c.col,'SELECT');
