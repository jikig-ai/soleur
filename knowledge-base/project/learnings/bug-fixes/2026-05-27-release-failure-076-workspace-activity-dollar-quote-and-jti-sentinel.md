---
title: Release failure in 076_workspace_activity.sql — dollar-quote collision and JTI sentinel drift
date: 2026-05-27
category: bug-fixes
tags: [migration, postgresql, dollar-quote, pg_cron, jti-deny, sentinel-drift, release-pipeline]
module: web-platform/supabase/migrations
related: [knowledge-base/project/learnings/2026-05-06-cap-coupling-between-adjacent-prs.md, knowledge-base/project/learnings/integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md]
related_prs: ["#4524", "#4545", "#4547", "#4548"]
severity: medium
---

# Learning: Release failure in 076_workspace_activity.sql — dollar-quote collision and JTI sentinel drift

## Problem

Three consecutive `web-platform-release.yml` pipeline failures on 2026-05-27 between 12:35 and 13:24 UTC. The fourth run succeeded after both root causes were fixed.

| Time (UTC) | Event | Run ID | Result |
|---|---|---|---|
| 12:35:50 | PR #4524 merged (feat: shared KB + team activity feed) | 26511491395 | **FAIL** |
| 12:41:25 | PR #4545 merged (fix: invitee identity check) | 26511778255 | **FAIL** |
| 13:09:12 | PR #4547 merged (fix: pg_cron dollar-quote collision) | 26513081130 | **FAIL** |
| 13:23:57 | PR #4548 merged (fix: bump JTI count 21→23) | 26513875914 | **PASS** |

## Root Cause 1: Dollar-Quote Collision in pg_cron DO Block

Migration `076_workspace_activity.sql` (introduced by PR #4524) used `$$` as both the outer DO block delimiter and the inner `cron.schedule()` SQL string delimiter:

```sql
DO $$
BEGIN
  PERFORM cron.schedule(
    'workspace_activity_purge',
    '0 3 * * *',
    $$DELETE FROM public.workspace_activity WHERE created_at < now() - interval '90 days'$$
  );
END $$;
```

PostgreSQL's parser uses greedy left-to-right matching for `$$` delimiters. The second `$$` (intended as the start of the inner string) is parsed as the close of the outer DO block, producing `ERROR: syntax error at or near "DELETE"`. This is a fundamental parser ambiguity — it fails in every execution mode (`psql -f`, `--single-transaction`, interactive `\i`, direct paste), not just the `--single-transaction` path used by `run-migrations.sh`.

**Codebase precedent:** 6 sibling migrations already use `$cron$` as the inner dollar-quote tag for `cron.schedule()` calls nested inside `DO $$` blocks: `029_plan_tier_and_concurrency_slots.sql`, `038_slow_user_concurrency_slots_sweep.sql`, `041_dsar_export_jobs.sql`, `043_tenant_deploy_audit.sql`, `062_workspace_member_removals_and_remove_rpc_update.sql`, `063_workspace_member_actions.sql`. The 076 migration violated this established convention.

**Fix:** PR #4547 changed the outer block to use `$cron_block$` as a distinct dollar-quote tag.

## Root Cause 2: JTI Deny Policy Count Sentinel Drift

The verify file `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` (line 73-74) contains a sentinel asserting exactly N RESTRICTIVE `*_jti_not_denied` policies exist. Migrations 076 (workspace_activity) and 077 (kb_files) each added 1 new JTI deny policy, bringing the total from 21 to 23. The verify file was not updated in PR #4524.

The sentinel lives in a separate verify SQL file, not in the migration itself. The multi-agent review of PR #4524 (11 agents) did not detect the out-of-band sentinel because verify files are not in the diff and are not typically part of migration review scope unless explicitly grepped.

This is the same failure class as the cap-coupling pattern documented in `knowledge-base/project/learnings/2026-05-06-cap-coupling-between-adjacent-prs.md` — a hardcoded count in one file drifts when a sibling file adds entries.

**Fix:** PR #4548 bumped the sentinel count from 21 to 23.

## Contributing Factor: Migration Number Collision at Prefix 076

PR #4524 introduced `076_workspace_activity.sql`. PR #4545 (merged 6 minutes later) introduced `076_invitation_invitee_identity_check.sql`. Both share prefix `076`.

The migration runner (`run-migrations.sh`) applies files in filename-sorted order, so `076_invitation...` applies before `076_workspace_activity...`. Both migrations are independent (no cross-references), so the collision caused no functional failure. The runner emits a `::warning::` for same-prefix collisions.

21 migration prefixes currently have collisions across the migration history. This is a structural artifact of the filename-keyed runner — it has never caused a functional failure because the runner applies and tracks each file independently.

## Prevention Patterns

1. **Use distinct dollar-quote tags when nesting.** Always use `$cron$` (or another distinct tag) for inner dollar-quoted strings inside `DO $$` blocks. Follow the precedent established by migration 041. Human readers and LLM reviewers parse indentation-implied structure correctly even when the PostgreSQL parser cannot — explicit distinct tags eliminate the ambiguity at the source level.

2. **Grep verify files when adding JTI deny policies.** When adding a new `*_jti_not_denied` RESTRICTIVE policy to any table, run:
   ```bash
   grep -n 'jti_deny_policies_count' apps/web-platform/supabase/verify/*.sql
   ```
   Bump the sentinel in the same PR. There is no automated mechanism to keep the count in sync — each new table with a JTI deny policy requires a manual update.

3. **Migration prefix collisions are informational.** The runner's `::warning::` for same-prefix migrations is informational only. Upgrading to `::error::` would break every release until all 21 historical collisions are renumbered. The runner applies each file independently and records each filename separately in `_schema_migrations`.

## "Sibling PR" Claim Assessment

The claim "release failure in 076_workspace_activity.sql is from a sibling PR — unrelated to this fix" is partially correct but misleading:

- **Correct:** The failures were NOT caused by PR #4545 (invitee identity check). Its migration applied cleanly.
- **Misleading:** The failures were caused by PR #4524's own migration having two bugs (dollar-quote collision + missing JTI sentinel bump). These are bugs in the workspace_activity migration itself, not from a "sibling PR."
- The prefix collision between the two 076 migrations is a pre-existing convention violation that the runner already warns about. It did not cause any failure.
