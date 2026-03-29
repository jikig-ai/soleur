# Tasks: UX Gate Incremental Commits

## Phase 1: Setup

- [ ] 1.1 Read current `/soleur:work` SKILL.md to confirm exact line locations for edits
  - Check 9 at line 81, Design Artifact Gate at line 184, Incremental Commits at lines 207-235

## Phase 2: Core Implementation

- [ ] 2.1 Add post-specialist commit checkpoint to Phase 0.5 check 9 (specialist review checks)
  - Append "UX artifact commit checkpoint" paragraph after check 9 text, before "On FAIL:" line
  - Use `git status --short` to discover output files (not hardcoded paths)
  - Each specialist gets its own commit for partial progress preservation
  - No commit on specialist failure
  - Explicitly exempt from compound ("Do not run compound before these WIP commits")
- [ ] 2.2 Add post-Design-Artifact-Gate commit checkpoint to Phase 2 step 2
  - Append "UX artifact commit checkpoint" paragraph after "Do not write any markup until the brief is received."
  - Commit implementation brief before first UI task begins
  - Explicitly exempt from compound
- [ ] 2.3 Extend incremental commit heuristic table in Phase 2 step 3
  - Add 3 UX-specific rows to existing table: specialist artifacts, review cycle, brand guide alignment
  - Add UX artifact heuristic paragraph after existing heuristic
  - Explain `wip:` prefix override for design artifacts (domain-specific refinement of "no WIP" rule)
  - Note squash merge safety and compound exemption

## Phase 3: Validation

- [ ] 3.1 Run markdownlint on modified SKILL.md
- [ ] 3.2 Re-read SKILL.md to verify all three commit checkpoints are in place
- [ ] 3.3 Verify existing Phase 2.3 table formatting preserved (pipe alignment, column spacing)
- [ ] 3.4 Verify compound exemption text is present in all three insertion points
