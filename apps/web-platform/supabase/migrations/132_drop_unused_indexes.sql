-- 132_drop_unused_indexes.sql
-- perf: drop 14 mature unused secondary indexes to cut write amplification.
--
-- Supabase sent a "Disk IO Budget depleting" warning for prod
-- (ifsccnjhymdmidffkzhl). Live signal (disk_io_pressure_signal RPC,
-- 2026-07-18): cache_hit_pct=100.000 (floor 98), max_wal_pct=15.19 (ceil 40)
-- → the pressure is diffuse WRITE IO (WAL + checkpoints), not reads. The
-- Micro-tier baseline (~87 MB/s) is being outrun by steady writes; the
-- operator chose to OPTIMIZE and keep the tier rather than upgrade.
--
-- Every secondary index is maintained on every INSERT/UPDATE of its table —
-- pure write-amplification when the index is never read. The performance
-- advisor (/advisors/performance, name=unused_index) returned 20 findings.
-- This migration drops the 14 MATURE ones (all idx_scan=0, verified
-- non-UNIQUE / non-PK via pg_index.indisunique/indisprimary=false on
-- 2026-07-18). The 6 remaining findings are beta-CRM indexes created in
-- migrations 126/127 (2026-07-08/09) whose idx_scan=0 reflects ~10-day-old
-- stats too young to trust — they are DEFERRED to a labeled follow-up, NOT
-- dropped here.
--
-- FK-cascade safety: six candidates sit on FK columns (idx_api_keys_user_id,
-- dsar_export_audit_pii_job_idx, audit_byok_use_delegation_ts_idx,
-- audit_byok_use_workspace_id_idx, byok_delegation_acceptances_delegation_idx,
-- and the workspace-keyed ones). FK *integrity* never requires the index;
-- only cascade-delete lookup speed does, and idx_scan=0 means even cascade
-- checks are not using them. All referencing child tables are small/low-write,
-- so the seq-scan-per-parent-delete risk is negligible.
--
-- FORWARD-ONLY, txn-safe (plain DROP INDEX, not the concurrent-build form —
-- runs inside run-migrations.sh's per-file --single-transaction wrapper). The
-- paired .down.sql recreates all 14 with their exact live definitions.
--
-- Plan: knowledge-base/project/plans/2026-07-18-perf-supabase-disk-io-write-reduction-plan.md
-- Prior related remediations: migration 114 (2026-06-30, webhook-dedup WAL
-- retention) and migration 123 (2026-07-07, autovacuum thrash on the same tiny
-- hot tables) — this migration attacks a third, distinct write-IO source.

DROP INDEX IF EXISTS public.idx_api_keys_user_id;
DROP INDEX IF EXISTS public.conversations_visibility_workspace_idx;
DROP INDEX IF EXISTS public.idx_conversations_context_path;
DROP INDEX IF EXISTS public.dsar_export_jobs_pending_idx;
DROP INDEX IF EXISTS public.idx_kb_share_links_content_sha256;
DROP INDEX IF EXISTS public.dsar_export_audit_pii_job_idx;
DROP INDEX IF EXISTS public.audit_byok_use_delegation_ts_idx;
DROP INDEX IF EXISTS public.audit_byok_use_workspace_id_idx;
DROP INDEX IF EXISTS public.workspace_member_actions_workspace_created_idx;
DROP INDEX IF EXISTS public.byok_delegation_acceptances_delegation_idx;
DROP INDEX IF EXISTS public.messages_workspace_id_idx;
DROP INDEX IF EXISTS public.outbound_sends_owner_sent_idx;
DROP INDEX IF EXISTS public.kb_files_workspace_idx;
DROP INDEX IF EXISTS public.workspaces_installation_repo_idx;
