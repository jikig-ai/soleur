---
title: "debug: release failure in 076_workspace_activity.sql root-cause analysis"
type: fix
date: 2026-05-27
lane: single-domain
brand_survival_threshold: none
---

# Debug: Release Failure in 076_workspace_activity.sql

Investigation of the web-platform-release.yml pipeline failures that occurred on 2026-05-27 between 12:35 UTC and 13:24 UTC. Three consecutive release runs failed before the fourth succeeded.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing impact -- this is a post-incident investigation of already-resolved release failures. All fixes (#4547, #4548) are merged and the pipeline is green.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A -- no user data involved; this is a CI/CD investigation producing a learning document.
- **Brand-survival threshold:** `none`

## Research Insights

### Timeline Reconstruction (from `gh run list` + `git log`)

| Time (UTC) | Event | Run ID | Result |
|---|---|---|---|
| 12:35:50 | PR #4524 merged (`feat(team): shared KB + team activity feed`) | 26511491395 | **FAIL** |
| 12:41:25 | PR #4545 merged (`fix(security): invitee identity check`) | 26511778255 | **FAIL** |
| 13:09:12 | PR #4547 merged (`fix(db): pg_cron dollar-quote collision`) | 26513081130 | **FAIL** |
| 13:23:57 | PR #4548 merged (`fix(verify): bump JTI count 21->23`) | 26513875914 | **PASS** |

### Root Cause 1: Dollar-Quote Collision in pg_cron DO Block

**Migration:** `076_workspace_activity.sql` (introduced by PR #4524)

The pg_cron schedule call used `$$` as both the outer DO block delimiter AND the inner `cron.schedule()` SQL string delimiter:

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

PostgreSQL parsed the first inner `$$` as the close of the outer DO block, causing `ERROR: syntax error at or near "DELETE"`.

**Fix:** PR #4547 changed the outer block to use `$cron_block$` as a distinct dollar-quote tag. This is the fix already merged to main.

**Why it was missed:** The `psql --single-transaction` invocation in `run-migrations.sh` wraps the migration body; the dollar-quote collision is syntactically valid when read standalone but fails when parsed as a single transaction. Local testing that runs statements individually would not catch this.

### Root Cause 2: JTI Deny Policy Count Sentinel Drift

**Verify file:** `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql`

The sentinel check on line 73-74 expected exactly 21 RESTRICTIVE `*_jti_not_denied` policies. Migrations 076 (workspace_activity) and 077 (kb_files) each added 1 new JTI deny policy, bringing the total to 23. The verify file was not updated in PR #4524.

**Fix:** PR #4548 bumped the sentinel count from 21 to 23 and updated the comment.

**Why it was missed:** The JTI sentinel count is in a separate verify SQL file, not in the migration itself. The multi-agent review of PR #4524 (11 agents) did not detect the out-of-band sentinel because verify files are not typically part of migration review scope unless explicitly grepped.

### Root Cause 3 (Contributing): Migration Number Collision at Prefix 076

PR #4524 introduced `076_workspace_activity.sql`. PR #4545 (merged 6 minutes later) introduced `076_invitation_invitee_identity_check.sql`. Both share prefix `076`.

The migration runner (`run-migrations.sh`) applies files in filename-sorted order, so `076_invitation_invitee_identity_check.sql` applies BEFORE `076_workspace_activity.sql`. This ordering is accidental, not intentional -- but both migrations are independent (no cross-references), so the collision caused no functional failure. The runner emits a `::warning::` for this class.

The collision did NOT cause the release failures -- both Root Causes 1 and 2 are independent of the collision. However, the collision means the second run (26511778255, PR #4545 merge) applied `076_invitation_invitee_identity_check.sql` successfully and then hit the same dollar-quote failure on `076_workspace_activity.sql`.

### "Sibling PR" Claim Assessment

The user's statement "Release failure in 076_workspace_activity.sql is from a sibling PR -- unrelated to this fix" is **partially correct but misleading**:

- **Correct:** The release failures were NOT caused by PR #4545 (the invitee identity check, which also used migration number 076). PR #4545's migration applied cleanly in run 26511778255.
- **Misleading:** The release failures were caused by PR #4524's own migration `076_workspace_activity.sql` having two bugs: (1) dollar-quote collision, (2) missing JTI sentinel bump. These are bugs in the workspace_activity migration itself, not from a "sibling PR."
- **The collision between 076_invitation_invitee_identity_check.sql and 076_workspace_activity.sql** is a pre-existing convention violation (prefix collision) that the runner already warns about. It did not cause any failure.

## Research Reconciliation -- Spec vs. Codebase

Not applicable -- no spec exists for this debug investigation. The codebase state matches the merged fixes.

## Open Code-Review Overlap

None -- no files are being edited in this investigation plan.

## Observability

Not applicable -- pure-docs investigation plan. No code/infra changes.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- post-incident investigation producing a learning document.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: Learning document created at `knowledge-base/project/learnings/bug-fixes/2026-05-27-release-failure-076-workspace-activity-dollar-quote-and-jti-sentinel.md` with YAML frontmatter (`title`, `date`, `category: bug-fixes`, `tags`)
- [ ] AC2: Learning captures both root causes (dollar-quote collision + JTI sentinel drift) and the timeline
- [ ] AC3: Learning documents the prevention patterns: (a) use distinct dollar-quote tags in pg_cron DO blocks, (b) grep verify files for sentinel counts when adding new JTI policies
- [ ] AC4: Learning mentions the migration-number collision as a contributing factor (not a root cause) and links to the runner's existing `::warning::` collision detection

### Post-merge (operator)

None -- pure documentation.

## Implementation Phases

### Phase 1: Create Learning Document

Write a structured learning document capturing:

1. **Problem:** Three consecutive web-platform-release failures on 2026-05-27
2. **Root causes:** Dollar-quote collision in pg_cron block + stale JTI sentinel count
3. **Fix:** PR #4547 (dollar-quote) + PR #4548 (JTI count)
4. **Prevention patterns:**
   - Always use distinct dollar-quote tags (`$cron_block$`, `$inner$`, etc.) when nesting dollar-quoted strings inside DO blocks
   - When adding a new JTI deny RESTRICTIVE policy, grep `apps/web-platform/supabase/verify/` for `jti_deny_policies_count` and bump the sentinel
   - The migration runner's prefix-collision warning is informational only; the runner applies same-prefix migrations in filename-sorted order

### Phase 2: Commit and Push

- Commit learning document
- Push to branch

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/2026-05-27-release-failure-076-workspace-activity-dollar-quote-and-jti-sentinel.md`

## Files to Edit

None.

## Test Scenarios

Not applicable -- pure documentation change.

## Sharp Edges

- The dollar-quote collision is NOT a general SQL syntax error -- it only manifests when the migration is applied via `psql --single-transaction`, which concatenates the file content with a trailing INSERT into `_schema_migrations`. Standalone `psql -f` execution would also hit it, but interactive statement-by-statement execution in a SQL editor would not.
- The JTI sentinel count is a hardcoded integer in a verify SQL file. There is no automated mechanism to keep it in sync with the number of JTI policies across migrations. Each new table that adds a `*_jti_not_denied` policy must manually update this sentinel.
