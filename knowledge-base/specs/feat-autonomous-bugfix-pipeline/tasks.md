# Tasks: Full Autonomous Bug-Fix Pipeline

Ref: `knowledge-base/plans/2026-03-05-feat-autonomous-bugfix-pipeline-plan.md`
Issue: #377

## Phase 1: Auto-Merge Eligibility in fix-issue Skill

- [ ] 1.1 Read and understand current `plugins/soleur/skills/fix-issue/SKILL.md`
- [ ] 1.2 Add Phase 5.5 (Auto-Merge Eligibility Check) to fix-issue skill
  - [ ] 1.2.1 After opening PR, evaluate: single file changed, source issue was p3-low, tests passed
  - [ ] 1.2.2 If eligible: `gh pr edit <N> --add-label "bot-fix/auto-merge-eligible"`
  - [ ] 1.2.3 If not eligible: `gh pr edit <N> --add-label "bot-fix/review-required"`
- [ ] 1.3 Update skill description to mention auto-merge labeling

## Phase 2: Auto-Merge Gate in Workflow

- [ ] 2.1 Read current `.github/workflows/scheduled-bug-fixer.yml`
- [ ] 2.2 Add label pre-creation step for new labels
  - `bot-fix/auto-merge-eligible`, `bot-fix/review-required`, `bot-fix/verified`, `bot-fix/reverted`
- [ ] 2.3 Add post-fix step: detect newly created bot-fix PR
  - Parse PR number from open `bot-fix/*` branches created in this run
- [ ] 2.4 Add auto-merge gate step
  - [ ] 2.4.1 Check PR has `bot-fix/auto-merge-eligible` label
  - [ ] 2.4.2 Verify single file changed via `gh pr diff --stat`
  - [ ] 2.4.3 Run `gh pr merge <number> --squash --auto` if eligible
- [ ] 2.5 Add Discord notification on auto-merge queue
- [ ] 2.6 Test via `workflow_dispatch` with a known p3-low issue

## Phase 3: Post-Merge CI Monitor

- [ ] 3.1 Create `.github/workflows/post-merge-monitor.yml`
  - [ ] 3.1.1 Trigger on `push` to `main`
  - [ ] 3.1.2 Job condition: `startsWith(github.event.head_commit.message, '[bot-fix]')`
  - [ ] 3.1.3 Extract source issue number from commit message
- [ ] 3.2 Implement CI wait step
  - Poll `gh run list --commit <sha> --workflow ci.yml` until complete
- [ ] 3.3 Implement revert-on-failure path
  - [ ] 3.3.1 `git revert HEAD --no-edit`
  - [ ] 3.3.2 Push to `revert-bot-fix-<N>` branch
  - [ ] 3.3.3 Create revert PR and auto-merge
  - [ ] 3.3.4 Comment on source issue about revert
  - [ ] 3.3.5 Add `bot-fix/reverted` label, remove `bot-fix/attempted`
- [ ] 3.4 Implement verify-on-success path
  - [ ] 3.4.1 Add `bot-fix/verified` label to source issue
  - [ ] 3.4.2 Close source issue with comment
- [ ] 3.5 Add infinite-loop guard (skip revert commits)
- [ ] 3.6 Add concurrency group to prevent parallel monitor runs

## Phase 4: Monitoring and Alerting

- [ ] 4.1 Add Discord webhook step to post-merge-monitor for auto-revert (critical alert)
- [ ] 4.2 Add Discord webhook step to post-merge-monitor for verified success
- [ ] 4.3 Verify `DISCORD_WEBHOOK_URL` secret exists; graceful skip if not configured

## Phase 5: Testing and Validation

- [ ] 5.1 Run SpecFlow analysis on both workflow files
- [ ] 5.2 Manual end-to-end test: create a test p3-low bug issue, trigger workflow_dispatch
- [ ] 5.3 Verify auto-merge path works (PR auto-merged, CI passes, issue closed)
- [ ] 5.4 Verify rollback path works (introduce deliberate test failure, verify revert)
- [ ] 5.5 Run compound before commit
- [ ] 5.6 Commit and push, create PR with `semver:minor` label
