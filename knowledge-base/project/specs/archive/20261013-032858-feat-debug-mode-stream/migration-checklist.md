# Migration checklist — feat-debug-mode-stream (migration 101)

Migration: `apps/web-platform/supabase/migrations/101_workspace_debug_mode.sql`
(+ `.down.sql`, + `supabase/verify/101_workspace_debug_mode.sql`).

## prd apply — pending

Applied post-merge by the existing `web-platform-release.yml#migrate` pipeline
(no SSH, no operator `terraform apply`). Order per plan AC10: **migration before
the Flagsmith flag flip**. The `verify-migrations` CI job runs
`verify/101_workspace_debug_mode.sql` (anon≠EXECUTE, authenticated=EXECUTE for
both RPCs) on deploy and fails the release on grant drift.

Pre-merge preflight Check 1 SKIPs on this documented deferral; post-merge
`/ship` Phase 3.6 re-verifies the `workspaces.debug_mode` column exists in prd
via the Supabase REST probe.

The feature ships fully gated OFF (`debug_mode` column DEFAULT false,
`FLAG_DEBUG_MODE=0`, `isDebugModeAvailable` hard-gates `role === "dev"`), so no
user-facing state depends on the apply landing immediately.
