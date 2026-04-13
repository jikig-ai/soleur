---
title: "fix: pre-existing test failures, git-worktree sharp edges, migration 021 apply"
type: fix
date: 2026-04-13
issues:
  - 2086
  - 2085
  - 2082
---

# Fix: Pre-Existing Test Failures, Git-Worktree Sharp Edges, Migration 021 Apply

Batch of three housekeeping issues: close resolved test failures, add worktree documentation, apply a production migration.

## Background

Three issues tracked in Post-MVP / Later and Phase 3 milestones require resolution:

1. **#2086** -- 6 web-platform tests were failing at the time the issue was filed (during #2080 ship). Testing on current `main` shows **all 6 tests now pass** (108/108 test files, 1137/1137 tests). The failures were likely resolved by `f6dbd60a` (refactor: extract shared test mocks) and `eddc1c89` (fix billing review findings). The issue can be closed with verification.

2. **#2085** -- The `/compound` skill identified three sharp edges from a worktree session that should be documented in `plugins/soleur/skills/git-worktree/SKILL.md`. The source learning file (`knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md`) does not exist in the repo -- it was referenced but never committed. The proposed text in the issue body is the canonical source.

3. **#2082** -- Migration 021 (`021_unique_stripe_subscription.sql`) creates a partial unique index on `users.stripe_subscription_id`. It was committed in #2079 but needs to be applied to production Supabase. This is a follow-through item from `/ship` Phase 7.

## Task 1: Close #2086 (Test Failures Resolved)

### Current State

All 6 tests pass on current `main`:

- `abort-all-sessions.test.ts` -- 3 tests pass
- `agent-runner-cost.test.ts` -- 4 tests pass
- `agent-runner-tools.test.ts` -- 20 tests pass
- `canusertool-tiered-gating.test.ts` -- 11 tests pass
- `session-resume-fallback.test.ts` -- 6 tests pass
- `ws-deferred-creation.test.ts` -- 4 tests pass

Full suite: 108 passed, 1 skipped, 0 failed.

### Implementation

1. Run `cd apps/web-platform && npx vitest run` to confirm all tests pass
2. Close the issue with a comment documenting the verification: `gh issue close 2086 --comment "All 6 tests pass on main (verified 2026-04-13). Likely fixed by f6dbd60a (shared test mock extraction) and eddc1c89 (billing review findings). Full suite: 108/108 files, 1137/1137 tests."`

### Files to Modify

None -- verification only.

## Task 2: Document Sharp Edges in SKILL.md (#2085)

### Current State

`plugins/soleur/skills/git-worktree/SKILL.md` has a Sharp Edges section with 5 existing bullets. Three new bullets need to be added based on the issue's proposed text.

### Implementation

1. Read `plugins/soleur/skills/git-worktree/SKILL.md`
2. Append three new bullets to the `## Sharp Edges` section (after the existing 5 bullets):

**Bullet A -- fetch refspec rejection in bare repos:**

```markdown
- In bare repos with multiple worktrees, `git fetch origin branch:branch` fails when the target branch is checked out in any worktree -- git rejects the refspec update. The fallback `git fetch origin branch` only updates `origin/branch`, NOT the local ref. Use `git update-ref refs/heads/branch origin/branch` to force-sync when the fetch refspec is rejected.
```

**Bullet B -- worktree creation verification:**

```markdown
- After creating a worktree via the script, always verify it exists in `git worktree list` before attempting to `cd` into it -- the script may report success for names that silently fail (e.g., excessively long names).
```

**Bullet C -- bare repo branch detection:**

```markdown
- In bare repos, `git branch --show-current` from the bare root returns `main` (or empty), not the worktree's branch. Always ensure CWD is inside the target worktree before running branch-detecting git commands.
```

3. Create the source learning file referenced by the issue: `knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md` with YAML frontmatter pointing back to the SKILL.md as `synced_to`.
4. Run `npx markdownlint-cli2 --fix` on modified `.md` files.

### Files to Modify

- `plugins/soleur/skills/git-worktree/SKILL.md` -- append 3 bullets to Sharp Edges section
- `knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md` -- create learning file (YAML frontmatter with title, date, category, tags, synced_to)

## Task 3: Apply Migration 021 to Production (#2082)

### Current State

Migration file exists at `apps/web-platform/supabase/migrations/021_unique_stripe_subscription.sql`. It creates:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_stripe_subscription_id_unique
  ON public.users (stripe_subscription_id)
  WHERE stripe_subscription_id IS NOT NULL;
```

This is a non-destructive `CREATE ... IF NOT EXISTS` operation -- safe to run on production.

### Implementation

1. Authenticate Supabase MCP: call `mcp__plugin_supabase_supabase__authenticate`
2. Execute the migration SQL against production via Supabase MCP `execute_sql` tool
3. Verify the index exists:

```sql
SELECT indexname FROM pg_indexes
WHERE tablename = 'users'
  AND indexname = 'idx_users_stripe_subscription_id_unique';
```

4. If the index is confirmed, close the issue: `gh issue close 2082 --comment "Migration 021 applied and verified. Index idx_users_stripe_subscription_id_unique confirmed present on production."`

**Fallback if Supabase MCP is unavailable:** Run the SQL via the Supabase dashboard SQL editor (manual step -- provide the user with the exact SQL to copy-paste).

### Files to Modify

None -- production database operation only.

## Acceptance Criteria

- [ ] All 6 tests from #2086 verified passing; issue closed with evidence
- [ ] SKILL.md updated with 3 new sharp edge bullets matching #2085 proposed text
- [ ] Learning file created at `knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md`
- [ ] Migration 021 applied to production Supabase; index verified via SQL query
- [ ] Issue #2082 closed with verification evidence
- [ ] Issue #2085 closed after SKILL.md changes are merged
- [ ] All modified `.md` files pass markdownlint

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Test Scenarios

- Given the current `main` branch, when running `cd apps/web-platform && npx vitest run`, then all 108 test files pass with 0 failures
- Given the SKILL.md edit, when running `npx markdownlint-cli2 plugins/soleur/skills/git-worktree/SKILL.md`, then no lint errors are reported
- Given the migration has been applied, when running `SELECT indexname FROM pg_indexes WHERE tablename = 'users' AND indexname = 'idx_users_stripe_subscription_id_unique'`, then exactly 1 row is returned

## Execution Order

1. Task 2 first (SKILL.md edits + learning file -- produces a commit)
2. Task 1 next (close #2086 -- no commit, just `gh issue close`)
3. Task 3 last (migration apply -- requires Supabase MCP auth, no commit)

## References

- #2086 -- pre-existing web-platform test failures
- #2085 -- route-to-definition proposal for SKILL.md
- #2082 -- follow-through: apply migration 021 to production
- #2079 -- source PR for migration 021
- #2080 -- PR where test failures were discovered
- `f6dbd60a` -- refactor: extract shared test mocks (likely fix for test failures)
