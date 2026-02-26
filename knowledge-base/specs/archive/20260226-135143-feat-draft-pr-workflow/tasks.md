# Tasks: Draft PR Workflow

**Plan:** [2026-02-25-feat-draft-pr-workflow-plan.md](../../plans/2026-02-25-feat-draft-pr-workflow-plan.md)
**Issue:** #304

## Phase 1: Add draft-pr subcommand to worktree-manager.sh

- [ ] 1.1 Add `create_draft_pr()` function to `worktree-manager.sh`
  - [ ] 1.1.1 Branch detection via `git rev-parse --abbrev-ref HEAD`
  - [ ] 1.1.2 Main/master guard (return 1)
  - [ ] 1.1.3 Idempotency check via `gh pr list --head <branch>` with stderr distinction
  - [ ] 1.1.4 Empty commit with `git commit --allow-empty`
  - [ ] 1.1.5 Push with stderr capture and warn-on-failure
  - [ ] 1.1.6 Draft PR creation with warn-on-failure
- [ ] 1.2 Add `draft-pr)` case to `main()` dispatch

## Phase 2: Modify brainstorm SKILL.md

- [ ] 2.1 Phase 3: Add `worktree-manager.sh draft-pr` call after step 3 (Set worktree path)
- [ ] 2.2 Phase 3.6: Add single commit+push for brainstorm doc + spec at end (step 5b)

## Phase 3: Modify workshop references

- [ ] 3.1 `brainstorm-brand-workshop.md`: Add draft-pr call in step 3, add commit+push after step 4
- [ ] 3.2 `brainstorm-validation-workshop.md`: Add draft-pr call in step 3, add commit+push after step 4

## Phase 4: Modify one-shot SKILL.md

- [ ] 4.1 Step 0b: Add `worktree-manager.sh draft-pr` call after branch creation

## Phase 5: Modify plan SKILL.md

- [ ] 5.1 Save Tasks section: Add single commit+push for plan + tasks.md after step 3

## Phase 6: Modify ship SKILL.md

- [ ] 6.1 Phase 7: Add PR detection logic (`gh pr list --head <branch>`)
- [ ] 6.2 Phase 7: Add conditional: if open PR exists → `gh pr edit` + `gh pr ready`
- [ ] 6.3 Phase 7: Preserve fallback → `gh pr create` when no PR exists

## Phase 7: Version bump and docs

- [ ] 7.1 Bump version in `plugin.json` (PATCH)
- [ ] 7.2 Update `CHANGELOG.md`
- [ ] 7.3 Verify `README.md` (no count changes)
- [ ] 7.4 Update root `README.md` badge
- [ ] 7.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
