# Migration checklist — feat-tr3-tool-attempt-telemetry (#5843)

Migration: `apps/web-platform/supabase/migrations/118_tool_attempts.sql` (+ `.down.sql`)

## dev apply — done

Validated live on `soleur-dev` (ref `mlwiodleouzwniehynfz`) via Supabase MCP `execute_sql`
during /work Phase 1, then **reverted** (table dropped, cron unscheduled) so dev returns to
the pristine "118-pending" state CI's `run-migrations.sh --verify` expects. Verified at apply time:

- 3 columns: `id uuid`, `created_at timestamptz`, `counts jsonb` — NO session/user/conversation column (CRITICAL-2 anonymity).
- RLS ENABLED with 0 policies → default-deny for anon/authenticated; `service_role` (BYPASSRLS) is the sole reader/writer.
- pg_cron `tool_attempts_retention` scheduled `0 4 * * *`, command `DELETE ... WHERE created_at < now() - interval '90 days'`.

## prd apply — deferred

Applies to prd automatically on merge via `web-platform-release.yml#migrate` (per plan
§Infrastructure — migration-only, no SSH/dashboard). Every statement is idempotent
(`CREATE TABLE IF NOT EXISTS`, guarded `cron.unschedule`-before-`schedule` + `EXCEPTION
WHEN duplicate_object`), so the CI re-apply is safe. Verified post-merge by ship Phase 7
Step 3.6 (Supabase REST probe for `tool_attempts.counts`) — AC8.
