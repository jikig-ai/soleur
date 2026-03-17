# Tasks: KB Directory Duplication Cleanup

## Phase 0: Pre-flight Verification (DONE during deepening)

- [x] 0.1 Verified zero filename collisions between `project/brainstorms/` and root `brainstorms/` (different date ranges)
- [x] 0.2 Verified zero filename collisions between `project/plans/` and root `plans/` (different date ranges)
- [x] 0.3 Verified zero filename collisions between `project/learnings/` flat files and root `learnings/`
- [x] 0.4 Verified overlapping spec dirs have complementary files: project/ has `tasks.md`, root has `session-state.md`
- [x] 0.5 Verified zero archive directory collisions across all three pairs (brainstorms, plans, specs)
- [x] 0.6 Verified `features/specs/archive/` has no collisions with root `specs/archive/`

## Phase 1: Merge features/specs/ into specs/

- [ ] 1.1 `git add knowledge-base/features/specs/` then `git mv knowledge-base/features/specs/feat-linkedin-presence knowledge-base/specs/`
- [ ] 1.2 `git mv knowledge-base/features/specs/feat-ralph-loop-idle-detection knowledge-base/specs/`
- [ ] 1.3 `git mv knowledge-base/features/specs/archive/20260313-130805-feat-utm-conventions knowledge-base/specs/archive/`
- [ ] 1.4 Verify `knowledge-base/features/` is empty (will be cleaned up by git automatically)

## Phase 2: Merge project/brainstorms/ into brainstorms/

- [ ] 2.1 `git add knowledge-base/project/brainstorms/` then move all 28 `*.md` files to `knowledge-base/brainstorms/`
- [ ] 2.2 Move all archive contents from `project/brainstorms/archive/` to `knowledge-base/brainstorms/archive/`
- [ ] 2.3 Verify `knowledge-base/project/brainstorms/` is empty

## Phase 3: Merge project/learnings/ into learnings/

- [ ] 3.1 `git add knowledge-base/project/learnings/` then move all flat `*.md` files to `knowledge-base/learnings/`
- [ ] 3.2 Move all 12 category subdirectories intact: `bug-fixes/`, `build-errors/`, `docs-site/`, `implementation-patterns/`, `integration-issues/`, `logic-errors/`, `performance-issues/`, `runtime-errors/`, `technical-debt/`, `ui-bugs/`, `workflow-issues/`, `workflow-patterns/`
- [ ] 3.3 Verify `knowledge-base/project/learnings/` is empty

## Phase 4: Merge project/plans/ into plans/

- [ ] 4.1 `git add knowledge-base/project/plans/` then move all `*.md` files to `knowledge-base/plans/`
- [ ] 4.2 Move all archive contents from `project/plans/archive/` to `knowledge-base/plans/archive/`
- [ ] 4.3 Verify `knowledge-base/project/plans/` is empty

## Phase 5: Merge project/specs/ into specs/

- [ ] 5.1 Move all non-overlapping `feat-*` directories from `project/specs/` to `knowledge-base/specs/` (82 dirs)
- [ ] 5.2 Move `knowledge-base/project/specs/feat-plausible-goals/tasks.md` into `knowledge-base/specs/feat-plausible-goals/`
- [ ] 5.3 Move `knowledge-base/project/specs/feat-weekly-analytics-improvements/tasks.md` into `knowledge-base/specs/feat-weekly-analytics-improvements/`
- [ ] 5.4 Move all archive contents from `project/specs/archive/` to `knowledge-base/specs/archive/`
- [ ] 5.5 Move `knowledge-base/project/specs/external/` to `knowledge-base/specs/external/` (if not already present)
- [ ] 5.6 Verify `knowledge-base/project/specs/` is empty

## Phase 6: Update Documentation

- [ ] 6.1 Update `knowledge-base/project/components/knowledge-base.md` directory tree (lines 29-43) to show brainstorms/, learnings/, plans/, specs/ as direct children of knowledge-base/, not project/
- [ ] 6.2 Update `knowledge-base/project/components/knowledge-base.md` examples and Related Files sections
- [ ] 6.3 Update `knowledge-base/project/README.md` directory structure (lines 132-137) to remove brainstorms/, learnings/, plans/, specs/ from under project/
- [ ] 6.4 Verify `knowledge-base/project/` only contains `constitution.md`, `README.md`, `components/`

## Phase 7: Verification

- [ ] 7.1 Verify `knowledge-base/features/` does not exist: `test ! -d knowledge-base/features/`
- [ ] 7.2 Verify `knowledge-base/project/` only has `constitution.md`, `README.md`, `components/`
- [ ] 7.3 Verify `knowledge-base/brainstorms/` has all 33+ brainstorm files
- [ ] 7.4 Verify `knowledge-base/learnings/` has all 198+ learning files including 12 category subdirs
- [ ] 7.5 Verify `knowledge-base/plans/` has all 100+ plan files
- [ ] 7.6 Verify `knowledge-base/specs/` has all 104+ spec directories
- [ ] 7.7 Verify `feat-plausible-goals` has both `tasks.md` and `session-state.md`
- [ ] 7.8 Verify `feat-weekly-analytics-improvements` has both `tasks.md` and `session-state.md`
- [ ] 7.9 Run post-move cross-reference sweep: `grep -rn 'knowledge-base/project/' knowledge-base/ --include='*.md' | grep -v '/archive/' | grep -v '/project/constitution.md' | grep -v '/project/README.md' | grep -v '/project/components/'`
- [ ] 7.10 Run `git status` to confirm all changes are tracked via `git mv`
- [ ] 7.11 Run `/soleur:compound` before committing
- [ ] 7.12 Commit as single atomic commit
