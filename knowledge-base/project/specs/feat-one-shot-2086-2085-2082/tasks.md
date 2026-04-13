# Tasks: Fix Test Failures, Git-Worktree Sharp Edges, Migration 021 Apply

## Phase 1: Setup

- [ ] 1.1 Verify all 6 tests from #2086 pass on current branch (`cd apps/web-platform && npx vitest run`)

## Phase 2: Core Implementation

### Task 2 -- SKILL.md Sharp Edges (#2085)

- [ ] 2.1 Read `plugins/soleur/skills/git-worktree/SKILL.md`
- [ ] 2.2 Append 3 new bullets to `## Sharp Edges` section:
  - [ ] 2.2.1 Bullet A: fetch refspec rejection in bare repos + `git update-ref` fallback
  - [ ] 2.2.2 Bullet B: worktree creation verification via `git worktree list`
  - [ ] 2.2.3 Bullet C: bare repo `git branch --show-current` returns `main` not worktree branch
- [ ] 2.3 Create learning file: `knowledge-base/project/learnings/integration-issues/origin-main-fallback-stale-ref-worktree-manager-20260413.md`
  - [ ] 2.3.1 Include YAML frontmatter: title, date, category, tags, synced_to
  - [ ] 2.3.2 Include problem description, root cause, solution, and cross-reference to SKILL.md
- [ ] 2.4 Run `npx markdownlint-cli2 --fix` on modified `.md` files

### Task 1 -- Close #2086 (Test Failures Resolved)

- [ ] 2.5 Close issue with verification comment: `gh issue close 2086 --comment "..."`

### Task 3 -- Apply Migration 021 (#2082)

- [ ] 2.6 Authenticate Supabase MCP
- [ ] 2.7 Execute migration SQL against production
- [ ] 2.8 Verify index exists via `SELECT indexname FROM pg_indexes ...`
- [ ] 2.9 Close issue with verification comment: `gh issue close 2082 --comment "..."`

## Phase 3: Testing

- [ ] 3.1 Run full web-platform test suite to confirm no regressions
- [ ] 3.2 Run markdownlint on all modified `.md` files
- [ ] 3.3 Verify production index via SQL query

## Phase 4: Ship

- [ ] 4.1 Run compound
- [ ] 4.2 Commit SKILL.md + learning file changes
- [ ] 4.3 Push and create PR (Closes #2085, Ref #2086, Ref #2082)
