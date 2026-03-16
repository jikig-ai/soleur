# Tasks: Content Generator Queue Exhaustion Fallback

**Branch:** feat/content-generator-queue-fallback
**Plan:** [2026-03-16-feat-content-generator-queue-fallback-plan.md](../../plans/2026-03-16-feat-content-generator-queue-fallback-plan.md)
**Issue:** #641

## Phase 1: Implementation

- [ ] 1.1 Read current `scheduled-content-generator.yml` workflow
- [ ] 1.2 Modify STEP 1 prompt to add queue exhaustion fallback branch:
  - [ ] 1.2.1 Add STEP 1b: run `/soleur:growth plan` with brand-aligned topic scope
  - [ ] 1.2.2 Add STEP 1c: extract top P1 topic and keywords from growth plan output
  - [ ] 1.2.3 Add STEP 1d: append discovered topic to `seo-refresh-queue.md` with `generated_date`
  - [ ] 1.2.4 Add fallback: if growth plan fails, create exhaustion issue and stop (preserve current behavior)
  - [ ] 1.2.5 Update STEP 6 audit issue to note whether topic was queue-sourced or auto-discovered

## Phase 2: Validation

- [ ] 2.1 Review the modified workflow for prompt clarity and instruction completeness
- [ ] 2.2 Verify all required tools are in `--allowedTools` (WebSearch needed for growth plan)
- [ ] 2.3 Verify timeout is sufficient (45 min current -- assess if bump needed)
- [ ] 2.4 Run compound

## Phase 3: Ship

- [ ] 3.1 Commit, push, create PR with `Closes #641` in body
- [ ] 3.2 Set `semver:patch` label
- [ ] 3.3 Merge via `gh pr merge --squash --auto`
