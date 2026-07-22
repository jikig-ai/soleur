-- 132_drop_unused_indexes.down.sql
-- Recreate the 14 unused indexes dropped by 132_drop_unused_indexes.sql.
--
-- Each CREATE INDEX below is the EXACT live pg_indexes.indexdef captured
-- 2026-07-18 (codepoint-for-codepoint), so `apply 132 → apply 132.down`
-- restores pg_indexes.indexdef to the pre-132 state. Recreated
-- non-concurrently (plain) inside the per-file transaction: a rollback is a deliberate
-- maintenance-window operation, so the brief ACCESS EXCLUSIVE locks are
-- acceptable and this keeps the down file inside run-migrations.sh's standard
-- --single-transaction wrapper (a concurrent index build would fail SQLSTATE
-- 25001 there). IF NOT EXISTS guards a partial re-apply.

CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON public.api_keys USING btree (user_id);
CREATE INDEX IF NOT EXISTS conversations_visibility_workspace_idx ON public.conversations USING btree (workspace_id) WHERE (visibility = 'workspace'::text);
CREATE INDEX IF NOT EXISTS idx_conversations_context_path ON public.conversations USING btree (context_path) WHERE (context_path IS NOT NULL);
CREATE INDEX IF NOT EXISTS dsar_export_jobs_pending_idx ON public.dsar_export_jobs USING btree (requested_at) WHERE (status = 'pending'::text);
CREATE INDEX IF NOT EXISTS idx_kb_share_links_content_sha256 ON public.kb_share_links USING btree (content_sha256);
CREATE INDEX IF NOT EXISTS dsar_export_audit_pii_job_idx ON public.dsar_export_audit_pii USING btree (job_id);
CREATE INDEX IF NOT EXISTS audit_byok_use_delegation_ts_idx ON public.audit_byok_use USING btree (delegation_id, ts) WHERE (delegation_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS audit_byok_use_workspace_id_idx ON public.audit_byok_use USING btree (workspace_id);
CREATE INDEX IF NOT EXISTS workspace_member_actions_workspace_created_idx ON public.workspace_member_actions USING btree (workspace_id, created_at DESC);
CREATE INDEX IF NOT EXISTS byok_delegation_acceptances_delegation_idx ON public.byok_delegation_acceptances USING btree (delegation_id);
CREATE INDEX IF NOT EXISTS messages_workspace_id_idx ON public.messages USING btree (workspace_id);
CREATE INDEX IF NOT EXISTS outbound_sends_owner_sent_idx ON public.outbound_sends USING btree (owner_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS kb_files_workspace_idx ON public.kb_files USING btree (workspace_id);
CREATE INDEX IF NOT EXISTS workspaces_installation_repo_idx ON public.workspaces USING btree (github_installation_id, repo_url);
