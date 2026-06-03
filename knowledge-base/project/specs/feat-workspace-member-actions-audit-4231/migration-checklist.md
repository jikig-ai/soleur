---
feature: feat-workspace-member-actions-audit-4231
date: 2026-05-22
pr: 4287
migration: apps/web-platform/supabase/migrations/063_workspace_member_actions.sql
---

# Migration Apply Checklist — `063_workspace_member_actions.sql`

## prd apply — pending

The migration is **NOT** applied from this worktree pre-merge per learning
`knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`.
Application is owned by the canonical `web-platform-release.yml#migrate` job,
which runs `bunx supabase migration up` against dev THEN prd on push to main.

This deferral is documented and detected by `/soleur:preflight` Check 1
Step 1.1b — the gate skips the unapplied-migration FAIL when this checklist's
`## prd apply` heading reads `pending`.

## Post-merge verification (AC13 / AC14 / AC15)

Re-issue this checklist with `## prd apply — done` after operating the
verification probes below (per `hr-no-dashboard-eyeball-pull-data-yourself`,
all probes route through the Supabase MCP server, never Studio):

1. **AC13** — `web-platform-release.yml#migrate` job completes successfully:
   - Verify via `gh run list --workflow web-platform-release.yml --branch main --status success` for the merge commit.

2. **AC14** — Schema parity probe via MCP:
   ```text
   mcp__plugin_supabase_supabase__execute_sql
     project_id: <prd_project_ref>
     query: |
       SELECT
         (SELECT count(*) FROM public.workspace_member_actions) AS audit_rows,
         (SELECT count(*) FROM public.workspace_members) AS membership_rows,
         (SELECT count(*) FROM cron.job WHERE jobname = 'workspace-member-actions-retention') AS cron_scheduled;
   ```
   Expected: `audit_rows == membership_rows`, `cron_scheduled == 1`.

3. **AC15** — PostgREST schema cache reload:
   - From a service_role client, call `list_workspace_member_actions(<workspace_id>)`.
   - If the call returns PGRST205, wait ≤5 min for the schema cache to refresh
     OR force-reload via the Supabase Management API.
   - Acceptance: the RPC returns either zero rows (no audit yet) or the
     backfilled `added` rows for the given workspace owner.

4. **First daily cron tick** (next 04:00 UTC after merge):
   ```text
   mcp__plugin_supabase_supabase__execute_sql
     project_id: <prd_project_ref>
     query: |
       SELECT start_time, end_time, status, return_message
       FROM cron.job_run_details
       WHERE jobname = 'workspace-member-actions-retention'
       ORDER BY start_time DESC LIMIT 1;
   ```
   Expected: one row with `status='succeeded'` and `return_message='0'`
   (no rows reach the 7-year horizon yet for the first 7 years of operation).

## On-merge follow-ups (deferred-automation)

Filed at PR-ready time per Phase 9.4 of the plan:

- **T-01** (privacy policy update for PA-20) — required before
  `TEAM_WORKSPACE_INVITE_ENABLED` flag-flips ON for any non-jikigai org.
- **T-02** (invite-time data subject notice) — required for external
  workspaces; covered for jikigai (Jean + Harry) via parent #4229 Side Letter.
- **Better Stack monitor provisioning** — runbook
  `knowledge-base/engineering/operations/runbooks/cron-retention-monitor.md` is the
  spec; monitor itself is provisioned at flag-flip-prep time.
