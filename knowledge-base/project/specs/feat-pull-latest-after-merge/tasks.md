# Tasks: Pull latest main after PR merge and worktree cleanup

## Phase 1: Core Implementation

- [ ] 1.1 Add pull-latest block to `cleanup_merged_worktrees()` in `worktree-manager.sh`
  - [ ] 1.1.1 Check if any branches were cleaned (`${#cleaned[@]} -gt 0`)
  - [ ] 1.1.2 Check main checkout for uncommitted changes (warn and skip if dirty)
  - [ ] 1.1.3 Checkout main if not already on it
  - [ ] 1.1.4 Pull latest with `|| true` fallback for network failures
  - [ ] 1.1.5 Print status messages respecting verbose mode

## Phase 2: Documentation Updates

- [ ] 2.1 Update `ship/SKILL.md` Phase 8 -- add verification step after cleanup-merged
- [ ] 2.2 Update `merge-pr/SKILL.md` Phase 7.3 -- add verification step after cleanup
- [ ] 2.3 Update `AGENTS.md` Workflow Completion Protocol step 10 -- mention auto-pull

## Phase 3: Validation

- [ ] 3.1 Manual test: merge a test PR and verify main is updated after cleanup
- [ ] 3.2 Manual test: verify no-op when no branches are cleaned
- [ ] 3.3 Verify the script exits 0 even if pull fails
