# Tasks: Fix Archiving

## Phase 1: Fix Core Bug (compound-capture slug extraction)

- [x] 1.1 Update branch detection at line 321 to accept both `feat-` and `feat/` prefixes
- [x] 1.2 Update section heading prose at line 323 to mention both conventions
- [x] 1.3 Replace bash code fence at line 330 with prose instructions listing all prefix variants
  - Handle: `feat/`, `feat-`, `feature/`, `fix/`, `fix-`
  - Use angle-bracket placeholders per constitution rule (no shell variable expansion in .md)

## Phase 2: Extend cleanup-merged (worktree-manager.sh)

- [x] 2.1 Add brainstorm archival block after spec archival (line 413)
  - [x] 2.1.1 Derive feature slug from safe_branch by stripping `feat-` prefix
  - [x] 2.1.2 Glob for `*<slug>*` in brainstorms/ excluding archive/
  - [x] 2.1.3 Move matched files to brainstorms/archive/ with timestamp prefix
- [x] 2.2 Add plan archival block after brainstorm archival
  - [x] 2.2.1 Glob for `*<slug>*` in plans/ excluding archive/
  - [x] 2.2.2 Move matched files to plans/archive/ with timestamp prefix

## Phase 3: Update compound skill documentation

- [x] 3.1 Update compound SKILL.md line 198 to reflect corrected slug extraction logic

## Phase 4: One-Time Orphan Cleanup

- [ ] 4.1 Archive all orphaned brainstorms (13 files) with `git mv`
- [ ] 4.2 Archive all orphaned plans (38 files) with `git mv`
- [ ] 4.3 Archive all orphaned spec directories (41 dirs, excluding `external/` and `feat-fix-archiving/`) with `git mv`
- [ ] 4.4 Commit as single atomic operation

## Phase 5: Verification

- [ ] 5.1 Verify no active brainstorms/plans/specs remain without a feature branch (except external/)
- [ ] 5.2 Verify compound-capture branch detection handles `feat/` prefix
- [ ] 5.3 Verify archived artifacts landed in correct archive/ directories with timestamps
