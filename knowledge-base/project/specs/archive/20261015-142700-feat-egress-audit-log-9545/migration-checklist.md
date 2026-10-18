# Migration checklist — 162_workspace_egress_audit_rollup (#9545 PR1)

## prd apply — deferred

Applied by the `migrate` job of `web-platform-release.yml` on merge (before `deploy`), and verified by the
`verify-migrations` job against `apps/web-platform/supabase/verify/162_workspace_egress_audit_rollup.sql`
(27 sentinel rows, all must return 0). Preflight Check 1 re-verifies post-merge through that job. Nothing is applied
by hand. The app change that calls `erase_egress_audit_rollup` ships in the same PR, so the order (migrate, then
deploy) is what makes the saga step 5.15 safe.
