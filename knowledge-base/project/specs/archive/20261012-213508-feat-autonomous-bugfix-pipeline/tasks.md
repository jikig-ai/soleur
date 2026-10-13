# Tasks: Full Autonomous Bug-Fix Pipeline

Ref: `knowledge-base/project/plans/2026-03-05-feat-autonomous-bugfix-pipeline-plan.md`
Issue: #377

## Phase 1: Auto-Merge Eligibility in fix-issue Skill

- [x] 1.1 Read and understand current `plugins/soleur/skills/fix-issue/SKILL.md`
- [x] 1.2 Add Phase 5.5 (Auto-Merge Eligibility Check) to fix-issue skill
  - [x] 1.2.1 After opening PR, evaluate: single file changed, source issue was p3-low, tests passed
  - [x] 1.2.2 If eligible: `gh pr edit <N> --add-label "bot-fix/auto-merge-eligible"`
  - [x] 1.2.3 If not eligible: `gh pr edit <N> --add-label "bot-fix/review-required"`
- [x] 1.3 Update skill description to mention auto-merge labeling

## Phase 2: Auto-Merge Gate in Workflow

- [x] 2.1 Read current `.github/workflows/scheduled-bug-fixer.yml`
- [x] 2.2 Add label pre-creation step for new labels
  - `bot-fix/auto-merge-eligible`, `bot-fix/review-required`, `bot-fix/verified`, `bot-fix/reverted`
- [x] 2.3 Add post-fix step (OUTSIDE claude-code-action): detect newly created bot-fix PR
  - Use `gh pr list --head "bot-fix/" --state open --json number --jq '.[0].number // empty'`
- [x] 2.4 Add auto-merge gate step (runs with GITHUB_TOKEN, not agent token)
  - [x] 2.4.1 Check PR has `bot-fix/auto-merge-eligible` label
  - [x] 2.4.2 Verify single file changed via `gh pr diff --name-only`
  - [x] 2.4.3 Run `gh pr merge <number> --squash --auto` if eligible
- [x] 2.5 Add Discord notification on auto-merge queue
- [ ] 2.6 Test via `workflow_dispatch` with a known p3-low issue

## Phase 3: Post-Merge CI Monitor

- [x] 3.1 Create `.github/workflows/post-merge-monitor.yml`
  - [x] 3.1.1 Use `workflow_run` trigger on CI completion (NOT `push` + polling)
  - [x] 3.1.2 Add `workflow_dispatch` input for dry-run testing (commit SHA)
  - [x] 3.1.3 Job condition: filter to `[bot-fix]`-prefixed commit messages on main
- [x] 3.2 Implement issue number extraction from commit message
  - Fallback to `gh api repos/{owner}/{repo}/commits/{sha}/pulls` for PR body parsing
- [x] 3.3 Implement revert-on-failure path (direct push to main, NOT revert PR)
  - [x] 3.3.1 `git config` user as `github-actions[bot]`
  - [x] 3.3.2 `git revert --no-edit HEAD`
  - [x] 3.3.3 `git push origin main` (direct push, no branch/PR)
  - [x] 3.3.4 Comment on source issue about revert
  - [x] 3.3.5 Add `bot-fix/reverted` label, remove `bot-fix/attempted`
- [x] 3.4 Implement verify-on-success path
  - [x] 3.4.1 Add `bot-fix/verified` label to source issue
  - [x] 3.4.2 Close source issue with comment
- [x] 3.5 Verify infinite-loop guard: revert commit message `Revert "[bot-fix]..."` does NOT match `startsWith('[bot-fix]')`
- [ ] 3.6 Verify GITHUB_TOKEN push is not blocked by any ruleset (Force Push Prevention only blocks deletion and non-fast-forward)

## Phase 4: Monitoring and Alerting

- [x] 4.1 Add Discord webhook step to post-merge-monitor for auto-revert (critical alert)
  - Reuse payload pattern from `version-bump-and-release.yml` (explicit username, avatar_url, allowed_mentions)
- [x] 4.2 Add Discord webhook step for verified success (informational)
- [x] 4.3 Verify `DISCORD_WEBHOOK_URL` secret exists; graceful skip if not configured

## Phase 5: Testing and Validation

- [ ] 5.1 Run SpecFlow analysis on both workflow files
- [ ] 5.2 Merge workflow files to main first (human PR) -- `workflow_run` requires file on default branch
- [ ] 5.3 Test auto-merge path: create test p3-low bug issue, trigger `workflow_dispatch` on scheduled-bug-fixer
- [ ] 5.4 Verify auto-merge queues correctly and CI-then-merge completes
- [ ] 5.5 Test rollback path: introduce deliberate test failure, verify revert via `workflow_dispatch` on post-merge-monitor
- [ ] 5.6 Verify Discord notifications fire for both success and revert cases
- [x] 5.7 Run compound before commit
- [ ] 5.8 Commit and push, create PR with `semver:minor` label
