---
title: "fix: pre-existing test failures, git-worktree sharp edges, migration 021 apply"
type: fix
date: 2026-04-13
deepened: 2026-04-13
issues:
  - 2086
  - 2085
  - 2082
---

# Fix: Pre-Existing Test Failures, Git-Worktree Sharp Edges, Migration 021 Apply

Batch of three housekeeping issues: close resolved test failures, add worktree documentation, verify a production migration.

## Enhancement Summary

**Deepened on:** 2026-04-13
**Sections enhanced:** 3 (all tasks)
**Research sources:** Local codebase analysis, CI workflow inspection, worktree-manager.sh verification, learning file cross-reference

### Key Improvements

1. **Task 3 reclassified:** Migration 021 was already applied by CI (`run-migrations.sh` in the `migrate` job of `web-platform-release.yml`). The task reduces from "apply migration" to "verify and close."
2. **Task 2 validated:** All three proposed sharp edge bullets verified against `worktree-manager.sh` source (lines 188-197, 826-831). The `update_branch_ref()` and `cleanup-merged` functions implement the exact fallback pattern documented.
3. **Related learning identified:** `worktree-manager-silent-creation-failure-20260410.md` documents the same class of issue as Bullet B (worktree creation verification).

### New Considerations Discovered

- CI migration runner (`run-migrations.sh`) handles migrations automatically at merge time -- follow-through items for migrations may be redundant when CI is green
- The learning file referenced by #2085 was never committed to the repo -- it must be created as part of this work, not just referenced

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

### Research Insights

**Root cause analysis:** The test failures were environment-dependent, caused by incomplete mock coverage for the Supabase client's chainable API. Two commits resolved them:

- `f6dbd60a` (refactor: extract shared test mocks) -- centralized mock scaffolding into `test/helpers/agent-runner-mocks.ts`, providing `createSupabaseMockImpl()` and `createQueryMock()` helpers that cover all table chains (`api_keys`, `users`, `conversations`, `messages`)
- `eddc1c89` (fix billing review findings) -- fixed mock patterns for the billing flow

**Pattern for future test stability:** Tests that mock `@supabase/supabase-js` `createClient` must cover the full chainable API surface for every table touched by the SUT. The `createApiKeysMock()` helper in `test/helpers/agent-runner-mocks.ts` shows the canonical pattern -- it returns a thenable chain that supports both `.select().eq().eq().eq().limit().single()` (getUserApiKey) and `await .select().eq().eq()` (getUserServiceTokens).

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

### Research Insights

**Code verification:** All three proposed bullets verified against `worktree-manager.sh`:

- **Bullet A** matches `update_branch_ref()` at lines 188-197 and `cleanup-merged` at lines 826-831. Both use the same `git fetch origin branch:branch` -> `git fetch origin branch` -> `git update-ref` fallback chain.
- **Bullet B** aligns with existing learning `worktree-manager-silent-creation-failure-20260410.md`, which documents the exact scenario (script reports success but directory does not exist). The fix (#1806 post-creation verification) was added but edge cases on bare repos may still produce partial directories (tracked in #1854).
- **Bullet C** is a fundamental git behavior in bare repos -- `git branch --show-current` reads `HEAD` which in a bare repo points to `main` (or nothing), not any worktree branch. This is a common footgun when scripts run from the bare root.

**Learning file status:** The referenced learning file (`origin-main-fallback-stale-ref-worktree-manager-20260413.md`) does not exist on `main` or any branch. It was likely produced during the session that created #2085 but was lost when that session ended without committing. The issue body contains the canonical content.

**YAML frontmatter for the learning file must include:**

```yaml
---
title: "origin/main fallback stale ref in worktree-manager"
date: 2026-04-13
category: integration-issues
tags: [git-worktree, bare-repo, fetch-refspec, update-ref, stale-ref]
synced_to: plugins/soleur/skills/git-worktree/SKILL.md
---
```

### Files to Modify

- `plugins/soleur/skills/git-worktree/SKILL.md` -- append 3 bullets to Sharp Edges section
- `knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md` -- create learning file (YAML frontmatter with title, date, category, tags, synced_to)

## Task 3: Verify Migration 021 on Production (#2082)

### Current State

Migration file exists at `apps/web-platform/supabase/migrations/021_unique_stripe_subscription.sql`. It creates:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_stripe_subscription_id_unique
  ON public.users (stripe_subscription_id)
  WHERE stripe_subscription_id IS NOT NULL;
```

### Research Insights

**CI already applied this migration.** The `web-platform-release.yml` workflow includes a `migrate` job that runs `run-migrations.sh` after every merge to main. The workflow run for #2079 (run ID `24336547928`) completed with `migrate` job status `success`. The migration runner (`apps/web-platform/scripts/run-migrations.sh`) applies all unapplied `.sql` files from `supabase/migrations/` in sorted order, tracking state in a `_schema_migrations` table.

**Implication:** The migration was almost certainly applied automatically. Task 3 reduces from "apply migration" to "verify the index exists and close the issue."

**Edge case:** If the migration runner bootstrapped (empty `_schema_migrations` table) on a run prior to #2079, it only seeds migrations up to `010_tag_and_route.sql`. Migrations 011-021 would still be applied as new files. This is the expected behavior.

### Implementation

1. Authenticate Supabase MCP: call `mcp__plugin_supabase_supabase__authenticate`
2. Verify the index exists (migration was applied by CI):

```sql
SELECT indexname FROM pg_indexes
WHERE tablename = 'users'
  AND indexname = 'idx_users_stripe_subscription_id_unique';
```

3. If the index is confirmed, close the issue: `gh issue close 2082 --comment "Migration 021 verified on production (applied by CI migrate job, run 24336547928). Index idx_users_stripe_subscription_id_unique confirmed present."`
4. If the index is NOT found (unexpected), apply it manually via Supabase MCP `execute_sql`, then re-verify.

**Fallback if Supabase MCP is unavailable:** Run the verification SQL via the Supabase dashboard SQL editor.

### Files to Modify

None -- production database verification only.

## Acceptance Criteria

- [x] All 6 tests from #2086 verified passing; issue closed with evidence
- [x] SKILL.md updated with 3 new sharp edge bullets matching #2085 proposed text
- [x] Learning file created at `knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md`
- [x] Migration 021 verified present on production Supabase (applied by CI); index confirmed via SQL query
- [x] Issue #2082 closed with verification evidence
- [ ] Issue #2085 closed after SKILL.md changes are merged
- [x] All modified `.md` files pass markdownlint

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
