# Tasks: Fix Test Failures, Git-Worktree Sharp Edges, Migration 021 Verify

## Phase 1: Setup

- [x] 1.1 Verify all 6 tests from #2086 pass on current branch (`cd apps/web-platform && npx vitest run`)

## Phase 2: Core Implementation

### Task 2 -- SKILL.md Sharp Edges (#2085)

- [x] 2.1 Read `plugins/soleur/skills/git-worktree/SKILL.md`
- [x] 2.2 Append 3 new bullets to `## Sharp Edges` section (after existing 5 bullets):
  - [x] 2.2.1 Bullet A: fetch refspec rejection in bare repos + `git update-ref` fallback (verified against `worktree-manager.sh` lines 188-197)
  - [x] 2.2.2 Bullet B: worktree creation verification via `git worktree list` (relates to learning `worktree-manager-silent-creation-failure-20260410.md`)
  - [x] 2.2.3 Bullet C: bare repo `git branch --show-current` returns `main` not worktree branch
- [x] 2.3 Create learning file: `knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md`
  - [x] 2.3.1 Include YAML frontmatter: title, date, category, tags, synced_to
  - [x] 2.3.2 Include problem description, root cause, solution, and cross-reference to SKILL.md
- [x] 2.4 Run `npx markdownlint-cli2 --fix` on modified `.md` files

### Task 1 -- Close #2086 (Test Failures Resolved)

- [x] 2.5 Close issue with verification comment: `gh issue close 2086 --comment "All 6 tests pass on main (verified 2026-04-13). Likely fixed by f6dbd60a (shared test mock extraction) and eddc1c89 (billing review findings). Full suite: 108/108 files, 1137/1137 tests."`

### Task 3 -- Verify Migration 021 (#2082)

- [x] 2.6 Authenticate Supabase (used Doppler + Management API instead of MCP)
- [x] 2.7 Verify index exists via `SELECT indexname FROM pg_indexes WHERE tablename = 'users' AND indexname = 'idx_users_stripe_subscription_id_unique'` (CI migrate job already applied it -- run 24336547928 succeeded)
- [x] 2.8 Index found -- no manual apply needed
- [x] 2.9 Close issue with verification comment

## Phase 3: Testing

- [x] 3.1 Run full web-platform test suite to confirm no regressions
- [x] 3.2 Run markdownlint on all modified `.md` files
- [x] 3.3 Verify production index presence confirmed in 2.7

## Phase 4: Ship

- [ ] 4.1 Run compound
- [ ] 4.2 Commit SKILL.md + learning file changes
- [ ] 4.3 Push and create PR (Closes #2085, Ref #2086, Ref #2082)
