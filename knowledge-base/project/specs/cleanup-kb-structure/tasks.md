# Tasks: Clean Up Stale Top-Level KB Directories

## Phase 1: Move Files

- [ ] 1.0 Enable nullglob to prevent literal-string glob expansion: `shopt -s nullglob`
- [ ] 1.1 Move 8 brainstorm files from `knowledge-base/project/brainstorms/` to `knowledge-base/project/brainstorms/`
- [ ] 1.2 Move 30 learning files from `knowledge-base/project/learnings/` to `knowledge-base/project/learnings/`
  - [ ] 1.2.1 Ensure `knowledge-base/project/learnings/build-errors/` exists before moving nested subdir file
- [ ] 1.3 Move 39 plan files from `knowledge-base/project/plans/` to `knowledge-base/project/plans/`
  - [ ] 1.3.1 Ensure `knowledge-base/project/plans/archive/` exists before moving nested archive file
- [ ] 1.4 Move 56 spec subdirectories (67 files) from `knowledge-base/project/specs/` to `knowledge-base/project/specs/`
  - [ ] 1.4.1 Special case: merge `fix-playwright-version-mismatch/` -- move only `session-state.md` into existing target dir (which already has `tasks.md`)
- [ ] 1.5 Restore nullglob: `shopt -u nullglob`

## Phase 2: Fix Internal References

- [ ] 2.0 Dry-run: grep for old-path references in moved files to confirm scope (expect ~92 matches)
- [ ] 2.1 Run sed to replace all four old-path patterns with `project/` counterparts in all moved `.md` files
- [ ] 2.2 Fix `spike/agent-sdk-test.ts` stale reference (line 37)
- [ ] 2.3 Post-check: re-run grep to confirm zero old-path references remain (excluding references to `project/` paths)

## Phase 3: Remove Empty Directories

- [ ] 3.1 Remove empty `knowledge-base/project/brainstorms/`
- [ ] 3.2 Remove empty `knowledge-base/project/learnings/` and `knowledge-base/project/learnings/build-errors/`
- [ ] 3.3 Remove empty `knowledge-base/project/plans/` and `knowledge-base/project/plans/archive/`
- [ ] 3.4 Remove empty `knowledge-base/project/specs/` and all 56 empty subdirectories

## Phase 4: Add Prevention Guard

- [ ] 4.1 Add `kb-structure-guard` command to `lefthook.yml` with array glob (CRITICAL: use both `*` and `**/*` patterns -- gobwas `**` requires 1+ dirs, so `**` alone misses direct files)
  - Pattern 1: `knowledge-base/{brainstorms,learnings,plans,specs}/*` (direct files)
  - Pattern 2: `knowledge-base/{brainstorms,learnings,plans,specs}/**/*` (nested files)
- [ ] 4.2 Test the guard by staging a dummy file at an old path and verifying commit is blocked
- [ ] 4.3 Remove dummy file after test

## Phase 5: Verification

- [ ] 5.1 Verify zero files at old locations: `find knowledge-base/brainstorms knowledge-base/learnings knowledge-base/plans knowledge-base/specs -type f 2>/dev/null | wc -l` returns 0
- [ ] 5.2 Verify all files moved: total at `knowledge-base/project/` increased by 144
- [ ] 5.3 Verify zero stale references: `grep -r 'knowledge-base/brainstorms\|knowledge-base/learnings\|knowledge-base/plans\|knowledge-base/specs' --include='*.md' knowledge-base/project/ | grep -v 'knowledge-base/project/'` returns empty
- [ ] 5.4 Run `bun test plugins/soleur/test/` and verify all tests pass
- [ ] 5.5 Verify `git log --follow` works on a sample moved file
