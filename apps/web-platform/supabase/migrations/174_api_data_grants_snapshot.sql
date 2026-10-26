-- 174_api_data_grants_snapshot.sql
--
-- 2026-10-30 Supabase change: hosted projects stop auto-granting Data API
-- access to NEW `public`-schema tables (changelog 45329). Existing prd tables
-- keep their grants — this file changes NOTHING on prd by construction (every
-- statement below re-declares a privilege that is already effective). What it
-- fixes is every FRESH environment built by replaying this corpus — new
-- projects, preview branches, `supabase db reset`, the rls-authz-fuzz stack —
-- which after the flip would get 42501 permission-denied on all of these.
--
-- GENERATED, not hand-written. Provenance: extracted 2026-10-26 from the live
-- prd catalog via
--   doppler run -p soleur -c prd -- npx tsx scripts/dump-api-grants.ts
-- over aclexplode(pg_class.relacl) + information_schema.column_privileges —
-- the effective privileges for anon/authenticated/service_role on every
-- public relation (relkind r,v,m,S), emitted verbatim. Privileges carried via
-- PUBLIC grants are materialized per-role. Column-level grants are emitted
-- ONLY where table-level was deliberately revoked (workspaces.authenticated
-- SELECT split) — a table-level GRANT would subsume and re-expose the held-back
-- columns. Runtime audit trail: /tmp report seeds
-- test/rls-fuzz/table-grants.ts; the narrowing follow-up issue carries the
-- per-relation classification. Decision: ADR-303.
--
-- KNOWN DELIBERATE SNAPSHOT WARTS (reproduced verbatim, per P1 zero-prd-change):
--   - users carries table-level UPDATE to all api roles on prd TODAY even
--     though migration 006 revoked it to UPDATE(email)-only — a later grant
--     restored the table-level verb; reproducing prd exactly, narrowing is
--     tracked in the follow-up issue.
--   - _schema_migrations is created by run-migrations.sh itself, not by a
--     migration file; it holds default-era full grants and keeps them.
--
-- Per-relation grants sit behind to_regclass preconditions (FK-lint
-- convention): a relation that does not exist on a given replay is skipped
-- rather than aborting the file.

DO $$ BEGIN IF to_regclass('public."_schema_migrations"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."_schema_migrations" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."_schema_migrations" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."_schema_migrations" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."action_sends"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."action_sends" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."action_sends" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."action_sends" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."agent_engine_events"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER ON TABLE public."agent_engine_events" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER ON TABLE public."agent_engine_events" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."agent_engine_events" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."agent_engine_runs"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER ON TABLE public."agent_engine_runs" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER ON TABLE public."agent_engine_runs" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."agent_engine_runs" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."api_keys"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."api_keys" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."api_keys" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."api_keys" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."audit_byok_use"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_byok_use" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_byok_use" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_byok_use" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."audit_github_token_use"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_github_token_use" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_github_token_use" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_github_token_use" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."beta_contact_access_log"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contact_access_log" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contact_access_log" TO authenticated;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contact_access_log" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."beta_contact_stage_transitions"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contact_stage_transitions" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contact_stage_transitions" TO authenticated;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contact_stage_transitions" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."beta_contacts"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contacts" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contacts" TO authenticated;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."beta_contacts" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."byok_delegation_acceptances"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."byok_delegation_acceptances" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."byok_delegation_acceptances" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."byok_delegation_acceptances" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."byok_delegation_withdrawals"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."byok_delegation_withdrawals" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."byok_delegation_withdrawals" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."byok_delegation_withdrawals" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."byok_delegations"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."byok_delegations" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."byok_delegations" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."byok_delegations" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."conversations"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."conversations" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."conversations" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."conversations" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."denied_jti"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."denied_jti" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."denied_jti" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."denied_jti" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."dsar_export_audit_pii"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_audit_pii" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_audit_pii" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_audit_pii" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."dsar_export_jobs"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_jobs" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_jobs" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_jobs" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."email_inbox_routes"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."email_inbox_routes" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."email_suppression"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."email_suppression" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."email_suppression" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."email_suppression" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."email_triage_items"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."email_triage_items" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."email_triage_items" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."email_triage_items" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."flag_flip_audit"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."flag_flip_audit" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."flag_flip_audit" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."flag_flip_audit" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."inbox_item"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."inbox_item" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."inbox_item" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."inbox_item" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."interview_notes"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."interview_notes" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."interview_notes" TO authenticated;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."interview_notes" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."kb_files"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."kb_files" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."kb_files" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."kb_files" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."kb_share_links"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."kb_share_links" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."kb_share_links" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."kb_share_links" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."message_attachments"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."message_attachments" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."message_attachments" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."message_attachments" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."messages"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."messages" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."messages" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."messages" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."mint_rate_window"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."mint_rate_window" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."mint_rate_window" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."mint_rate_window" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."organizations"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."organizations" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."organizations" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."organizations" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."outbound_sends"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."outbound_sends" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."outbound_sends" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."outbound_sends" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."pending_checkout_sessions"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."pending_checkout_sessions" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."pending_checkout_sessions" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."pending_checkout_sessions" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."probe_tokens"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."probe_tokens" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."probe_tokens" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."probe_tokens" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."processed_github_events"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_github_events" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_github_events" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_github_events" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."processed_resend_events"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_resend_events" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_resend_events" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_resend_events" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."processed_stripe_events"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_stripe_events" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_stripe_events" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."processed_stripe_events" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."push_subscriptions"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."push_subscriptions" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."push_subscriptions" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."push_subscriptions" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."routine_run_progress"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."routine_run_progress" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."routine_run_progress" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."routine_run_progress" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."routine_runs"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."routine_runs" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."routine_runs" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."routine_runs" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."runtime_mint_intent"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."runtime_mint_intent" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."scope_grants"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."scope_grants" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."scope_grants" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."scope_grants" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."statutory_repin_send"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."statutory_repin_send" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."tc_acceptances"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tc_acceptances" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tc_acceptances" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tc_acceptances" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."team_names"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."team_names" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."team_names" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."team_names" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."template_authorizations"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."template_authorizations" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."template_authorizations" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."template_authorizations" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."tenant_deploy_audit"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tenant_deploy_audit" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tenant_deploy_audit" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tenant_deploy_audit" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."tool_attempts"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tool_attempts" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tool_attempts" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tool_attempts" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."user_concurrency_slots"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_concurrency_slots" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_concurrency_slots" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_concurrency_slots" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."user_session_state"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_session_state" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_session_state" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_session_state" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."users"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."users" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."users" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."users" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_activity"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_activity" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_activity" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_activity" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_egress_audit_rollup"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_egress_audit_rollup" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_engine_settings"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER ON TABLE public."workspace_engine_settings" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER ON TABLE public."workspace_engine_settings" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_engine_settings" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_invitations"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."workspace_invitations" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."workspace_invitations" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_invitations" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_member_actions"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE public."workspace_member_actions" TO anon;
    GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE public."workspace_member_actions" TO authenticated;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."workspace_member_actions" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_member_attestations"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."workspace_member_attestations" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."workspace_member_attestations" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_member_attestations" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_member_removals"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."workspace_member_removals" TO anon;
    GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE public."workspace_member_removals" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_member_removals" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_members"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_members" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_members" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_members" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspaces"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspaces" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspaces" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspaces" TO service_role;
    GRANT SELECT ("created_at", "id", "name", "organization_id", "repo_error", "repo_last_synced_at", "repo_provider", "repo_status", "repo_url") ON TABLE public."workspaces" TO authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."worktree_write_lease"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."worktree_write_lease" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."worktree_write_lease" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."worktree_write_lease" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."routine_runs_latest"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."routine_runs_latest" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."routine_runs_latest" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."routine_runs_latest" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_cost_aggregate"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_cost_aggregate" TO anon;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_cost_aggregate" TO authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."workspace_cost_aggregate" TO service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."agent_engine_events_id_seq"') IS NOT NULL THEN
    GRANT SELECT, UPDATE, USAGE ON SEQUENCE public."agent_engine_events_id_seq" TO anon;
    GRANT SELECT, UPDATE, USAGE ON SEQUENCE public."agent_engine_events_id_seq" TO authenticated;
    GRANT SELECT, UPDATE, USAGE ON SEQUENCE public."agent_engine_events_id_seq" TO service_role;
END IF; END $$;

