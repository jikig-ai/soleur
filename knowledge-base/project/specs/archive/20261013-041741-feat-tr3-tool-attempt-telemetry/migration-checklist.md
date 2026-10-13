# Migration checklist — feat-tr3-tool-attempt-telemetry (#5843)

Migration: `apps/web-platform/supabase/migrations/118_tool_attempts.sql` (+ `.down.sql`)

## dev apply — done (schema + ledger consistent)

Applied on `soleur-dev` (ref `mlwiodleouzwniehynfz`) and recorded in the
`public._schema_migrations` ledger (`content_sha fed11540…` matches
`git hash-object 118_tool_attempts.sql`). CI's tenant-integration suite runs
`run-migrations.sh` against dev, so 118 is applied+ledgered there as part of every
branch CI run; this checklist reflects that consistent state. Verified live:

- 3 columns: `id uuid`, `created_at timestamptz`, `counts jsonb` — NO session/user/conversation column (CRITICAL-2 anonymity).
- RLS ENABLED with 0 policies → default-deny for anon/authenticated; `service_role` (BYPASSRLS) is the sole reader/writer.
- pg_cron `tool_attempts_retention` scheduled `0 4 * * *`, command `DELETE ... WHERE created_at < now() - interval '90 days'`.
- `to_regclass('public.tool_attempts')` non-null AND ledger row present AND `content_sha` matches → the schema-vs-ledger consistency gate passes.

**Do NOT drop the dev table to "keep dev pristine"** — once CI has ledgered 118,
dropping the table without deleting the ledger row creates schema-vs-ledger drift
(the tenant-integration `Preflight schema-vs-ledger consistency check` fails
"ledger claims applied, but table is missing"). Leave the applied state as-is.

## prd apply — deferred

Applies to prd automatically on merge via `web-platform-release.yml#migrate` (per plan
§Infrastructure — migration-only, no SSH/dashboard). Every statement is idempotent
(`CREATE TABLE IF NOT EXISTS`, guarded `cron.unschedule`-before-`schedule` + `EXCEPTION
WHEN duplicate_object`), so the CI re-apply is safe. Verified post-merge by ship Phase 7
Step 3.6 (Supabase REST probe for `tool_attempts.counts`) — AC8.
