---
title: "debug: release failure in 076_workspace_activity.sql root-cause analysis"
type: fix
date: 2026-05-27
lane: single-domain
brand_survival_threshold: none
deepened: 2026-05-27
---

# Debug: Release Failure in 076_workspace_activity.sql

Investigation of the web-platform-release.yml pipeline failures that occurred on 2026-05-27 between 12:35 UTC and 13:24 UTC. Three consecutive release runs failed before the fourth succeeded.

## Enhancement Summary

**Deepened on:** 2026-05-27
**Sections enhanced:** 4
**Research agents used:** repo-research (dollar-quote precedent grep), learnings-researcher (cap-coupling, migration-concurrently), factual-verifier (PR numbers, CI logs, codebase precedent)

### Key Improvements

1. Corrected the "Why it was missed" section for Root Cause 1 -- dollar-quote collision is a fundamental PostgreSQL parser ambiguity, not `--single-transaction`-specific
2. Added codebase precedent evidence: 6 sibling migrations already use `$cron$` as the inner delimiter, establishing the convention 076 violated
3. Added cross-PR sentinel-drift prevention pattern -- the cap-coupling learning (`2026-05-06-cap-coupling-between-adjacent-prs.md`) documents the same class of failure
4. Added quantification: 21 existing prefix collisions across migration history, contextualizing 076 as systemic, not exceptional

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

**Why it was missed:** The dollar-quote collision is a fundamental PostgreSQL parser ambiguity -- when the parser encounters the second `$$`, it cannot distinguish "start of inner string" from "close of outer DO block." This fails in ANY execution mode (`psql -f`, `--single-transaction`, interactive `\i`, direct COPY-paste), not just the `--single-transaction` path used by `run-migrations.sh`. The likely reason it was not caught pre-merge: the migration was authored and reviewed as text, and human readers (and LLM reviewers) parse the indentation-implied structure correctly even though the PostgreSQL parser cannot. The codebase already had an established precedent -- 6 sibling migrations (`041_dsar_export_jobs.sql`, `043_tenant_deploy_audit.sql`, `062_workspace_member_removals_and_remove_rpc_update.sql`, `063_workspace_member_actions.sql`, `038_slow_user_concurrency_slots_sweep.sql`, `029_plan_tier_and_concurrency_slots.sql`) all use `$cron$` as the inner dollar-quote tag for `cron.schedule()` calls nested inside `DO $$` blocks. The 076 migration should have followed this precedent.

### Root Cause 2: JTI Deny Policy Count Sentinel Drift

**Verify file:** `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql`

The sentinel check on line 73-74 expected exactly 21 RESTRICTIVE `*_jti_not_denied` policies. Migrations 076 (workspace_activity) and 077 (kb_files) each added 1 new JTI deny policy, bringing the total to 23. The verify file was not updated in PR #4524.

**Fix:** PR #4548 bumped the sentinel count from 21 to 23 and updated the comment.

**Why it was missed:** The JTI sentinel count is in a separate verify SQL file (`apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql:73`), not in the migration itself. The multi-agent review of PR #4524 (11 agents) did not detect the out-of-band sentinel because verify files are not in the diff and are not typically part of migration review scope unless explicitly grepped. This is the same class as the cap-coupling pattern documented in `knowledge-base/project/learnings/2026-05-06-cap-coupling-between-adjacent-prs.md` -- a hardcoded count in one file drifts when a sibling file adds entries. Prevention: when adding a new `*_jti_not_denied` policy, run `grep -n 'jti_deny_policies_count' apps/web-platform/supabase/verify/*.sql` and bump the sentinel in the same PR.

### Root Cause 3 (Contributing): Migration Number Collision at Prefix 076

PR #4524 introduced `076_workspace_activity.sql`. PR #4545 (merged 6 minutes later) introduced `076_invitation_invitee_identity_check.sql`. Both share prefix `076`.

The migration runner (`run-migrations.sh`) applies files in filename-sorted order, so `076_invitation_invitee_identity_check.sql` applies BEFORE `076_workspace_activity.sql`. This ordering is accidental, not intentional -- but both migrations are independent (no cross-references), so the collision caused no functional failure. The runner emits a `::warning::` for this class.

The collision did NOT cause the release failures -- both Root Causes 1 and 2 are independent of the collision. However, the collision means the second run (26511778255, PR #4545 merge) applied `076_invitation_invitee_identity_check.sql` successfully and then hit the same dollar-quote failure on `076_workspace_activity.sql`.

**Systemic context:** 21 migration prefixes currently have collisions (007, 017, 019, 020, 029, 037, 038, 041, 042, 048, 049, 050, 053, 054, 063, 064, 068, 069, 071, 075, 076). The runner's collision-check (`run-migrations.sh:188-200`) emits `::warning::` for all of them. This is a structural artifact of the runner's filename-keyed tracking -- it is NOT a blocking error because the runner applies each file independently and records each filename separately in `_schema_migrations`.

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
4. **Codebase precedent:** 6 sibling migrations already use `$cron$` for inner cron.schedule strings (`041_dsar_export_jobs.sql`, `043_tenant_deploy_audit.sql`, `062_workspace_member_removals_and_remove_rpc_update.sql`, `063_workspace_member_actions.sql`, `038_slow_user_concurrency_slots_sweep.sql`, `029_plan_tier_and_concurrency_slots.sql`). The 076 migration violated this established pattern.
5. **Prevention patterns:**
   - Always use distinct dollar-quote tags (`$cron$`, `$cron_block$`, etc.) when nesting dollar-quoted strings inside DO blocks -- follow the `$cron$` precedent established by mig 041
   - When adding a new JTI deny RESTRICTIVE policy, run `grep -n 'jti_deny_policies_count' apps/web-platform/supabase/verify/*.sql` and bump the sentinel in the same PR
   - The migration runner's prefix-collision warning is informational only; the runner applies same-prefix migrations in filename-sorted order
6. **Related learnings:** Link to `2026-05-06-cap-coupling-between-adjacent-prs.md` (same failure class -- hardcoded count drifts when sibling adds entries)

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

- The dollar-quote collision IS a general PostgreSQL parser ambiguity -- it manifests in ANY execution mode that sends the full DO block as a single statement (`psql -f`, `--single-transaction`, interactive `\i`, COPY-paste). The PostgreSQL parser uses greedy left-to-right matching for `$$` delimiters; it cannot distinguish "start inner string" from "close outer block" without a distinct tag. The only execution mode that would NOT hit this is splitting the DO block into separate statements, which `psql`'s default semicolon-delimited mode does NOT do for `DO $$...$$;` blocks. The codebase convention is `$cron$` for inner cron.schedule strings (established by mig 041, followed by 043, 062, 063, 038, 029).
- The JTI sentinel count is a hardcoded integer in a verify SQL file (`apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql:73`). There is no automated mechanism to keep it in sync with the number of JTI policies across migrations. Each new table that adds a `*_jti_not_denied` policy must manually update this sentinel. Prevention: `grep -n 'jti_deny_policies_count' apps/web-platform/supabase/verify/*.sql` before adding a JTI policy.
- The migration-number collision pattern (21 existing prefix collisions) is a systemic artifact of the filename-keyed migration runner. It has never caused a functional failure because the runner applies and tracks each file independently. The `::warning::` is informational -- upgrading to `::error::` would break every release run until all 21 historical collisions are renumbered.

## Related Learnings

- `knowledge-base/project/learnings/2026-05-06-cap-coupling-between-adjacent-prs.md` -- same failure class (hardcoded count drifts when sibling adds entries); resolution pattern is single-source-of-truth import + drift-guard test.
- `knowledge-base/project/learnings/integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md` -- sibling migration pattern: runner wraps each file in a transaction, which constrains available DDL. The dollar-quote bug is a different constraint (parser ambiguity, not transaction-mode restriction) but surfaces through the same pipeline.
- `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` -- parallel-branch migration coordination patterns relevant to the prefix-collision context.
