# Tasks: Content Generator Queue Exhaustion Fallback

**Branch:** feat/content-generator-queue-fallback
**Plan:** [2026-03-16-feat-content-generator-queue-fallback-plan.md](../../plans/2026-03-16-feat-content-generator-queue-fallback-plan.md)
**Issue:** #641

## Phase 1: Implementation

- [ ] 1.1 Read current `scheduled-content-generator.yml` workflow
- [ ] 1.2 Bump resource limits:
  - [ ] 1.2.1 `timeout-minutes: 45` -> `timeout-minutes: 60`
  - [ ] 1.2.2 `--max-turns 40` -> `--max-turns 50`
- [ ] 1.3 Modify STEP 1 prompt to add queue exhaustion fallback branch:
  - [ ] 1.3.1 Add STEP 1b: run `/soleur:growth plan "Company-as-a-Service content for solo founders building with AI"` (no `--headless`, no `--site`)
  - [ ] 1.3.2 Add instruction to extract top P1 topic and keywords from growth plan output
  - [ ] 1.3.3 Add fallback: if growth plan fails or returns no P1 topic, create exhaustion issue and stop
  - [ ] 1.3.4 Add post-validation step: append discovered topic to `seo-refresh-queue.md` under `## Auto-Discovered Topics` table
- [ ] 1.4 Update STEP 6 audit issue to note topic source (queue-sourced vs. auto-discovered)

## Phase 2: Validation

- [ ] 2.1 Review the modified workflow for prompt clarity and instruction completeness
- [ ] 2.2 Verify all required tools are in `--allowedTools` (WebSearch, Task needed for growth plan)
- [ ] 2.3 Run compound

## Phase 3: Ship

- [ ] 3.1 Commit, push, create PR with `Closes #641` in body
- [ ] 3.2 Set `semver:patch` label
- [ ] 3.3 Merge via `gh pr merge --squash --auto`
