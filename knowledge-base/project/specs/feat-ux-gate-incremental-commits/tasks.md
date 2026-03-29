# Tasks: UX Gate Incremental Commits

## Phase 1: Setup

- [ ] 1.1 Read current `/soleur:work` SKILL.md to confirm exact line locations for edits

## Phase 2: Core Implementation

- [ ] 2.1 Add post-specialist commit checkpoint to Phase 0.5 check 9 (specialist review checks)
  - After each specialist agent completes successfully, stage output and commit with `wip: <specialist-name> artifacts for <feature-name>`
  - Covers both interactive ("Run specialist now") and pipeline (auto-invoke) paths
  - No commit on specialist failure
- [ ] 2.2 Add post-Design-Artifact-Gate commit checkpoint to Phase 2 step 2
  - After `ux-design-lead` produces implementation brief, stage and commit with `wip: UX implementation brief for <feature-name>`
  - Commit before first UI task begins
- [ ] 2.3 Extend incremental commit heuristic table in Phase 2 step 3
  - Add UX-specific rows: specialist artifacts, review cycle completion, brand guide alignment
  - Add UX artifact heuristic explaining `wip:` prefix convention for design artifacts

## Phase 3: Validation

- [ ] 3.1 Run markdownlint on modified SKILL.md
- [ ] 3.2 Re-read SKILL.md to verify all three commit checkpoints are in place
- [ ] 3.3 Verify no existing Phase 2.3 patterns were broken (table formatting, heuristic text)
