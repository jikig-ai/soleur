# Tasks: Clean Up Stale Top-Level KB Directories

## Phase 1: Move Files

- [ ] 1.1 Move 8 brainstorm files from `knowledge-base/brainstorms/` to `knowledge-base/project/brainstorms/`
- [ ] 1.2 Move 30 learning files from `knowledge-base/learnings/` (incl. `build-errors/` subdir) to `knowledge-base/project/learnings/`
- [ ] 1.3 Move 39 plan files from `knowledge-base/plans/` (incl. `archive/` subdir) to `knowledge-base/project/plans/`
- [ ] 1.4 Move 56 spec subdirectories (67 files) from `knowledge-base/specs/` to `knowledge-base/project/specs/`
  - [ ] 1.4.1 Special case: merge `fix-playwright-version-mismatch/` -- move `session-state.md` into existing `knowledge-base/project/specs/fix-playwright-version-mismatch/` alongside `tasks.md`

## Phase 2: Fix Internal References

- [ ] 2.1 Run sed to replace `knowledge-base/brainstorms/` with `knowledge-base/project/brainstorms/` in all moved `.md` files (avoid matching existing `project/` prefix)
- [ ] 2.2 Run sed to replace `knowledge-base/learnings/` with `knowledge-base/project/learnings/` in all moved `.md` files
- [ ] 2.3 Run sed to replace `knowledge-base/plans/` with `knowledge-base/project/plans/` in all moved `.md` files
- [ ] 2.4 Run sed to replace `knowledge-base/specs/` with `knowledge-base/project/specs/` in all moved `.md` files
- [ ] 2.5 Fix `spike/agent-sdk-test.ts` stale reference (line 37)

## Phase 3: Remove Empty Directories

- [ ] 3.1 Remove empty `knowledge-base/brainstorms/`
- [ ] 3.2 Remove empty `knowledge-base/learnings/` and `knowledge-base/learnings/build-errors/`
- [ ] 3.3 Remove empty `knowledge-base/plans/` and `knowledge-base/plans/archive/`
- [ ] 3.4 Remove empty `knowledge-base/specs/` and all 56 empty subdirectories

## Phase 4: Add Prevention Guard

- [ ] 4.1 Add `kb-structure-guard` command to `lefthook.yml` with glob `knowledge-base/{brainstorms,learnings,plans,specs}/**`
- [ ] 4.2 Test the guard by staging a dummy file at an old path and verifying commit is blocked
- [ ] 4.3 Remove dummy file after test

## Phase 5: Verification

- [ ] 5.1 Verify zero files at old locations: `find knowledge-base/brainstorms knowledge-base/learnings knowledge-base/plans knowledge-base/specs -type f 2>/dev/null | wc -l` returns 0
- [ ] 5.2 Verify all files moved: total at `knowledge-base/project/` increased by 144
- [ ] 5.3 Verify zero stale references: `grep -r 'knowledge-base/brainstorms\|knowledge-base/learnings\|knowledge-base/plans\|knowledge-base/specs' --include='*.md' knowledge-base/project/ | grep -v 'knowledge-base/project/'` returns empty
- [ ] 5.4 Run `bun test plugins/soleur/test/` and verify all tests pass
- [ ] 5.5 Verify `git log --follow` works on a sample moved file
