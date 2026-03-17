# Tasks: KB Directory Duplication Cleanup

## Phase 0: Pre-flight Verification

- [ ] 0.1 Run `comm` to verify no filename collisions between `project/brainstorms/` and root `brainstorms/`
- [ ] 0.2 Run `comm` to verify no filename collisions between `project/plans/` and root `plans/`
- [ ] 0.3 Run `comm` to verify no filename collisions between `project/learnings/` flat files and root `learnings/`
- [ ] 0.4 Compare contents of overlapping spec dirs: `feat-plausible-goals` and `feat-weekly-analytics-improvements` in both `project/specs/` and root `specs/`
- [ ] 0.5 Compare archive directories for collisions between `project/*/archive/` and root `*/archive/`

## Phase 1: Merge features/specs/ into specs/

- [ ] 1.1 Move `knowledge-base/features/specs/feat-linkedin-presence/` to `knowledge-base/specs/feat-linkedin-presence/`
- [ ] 1.2 Move `knowledge-base/features/specs/feat-ralph-loop-idle-detection/` to `knowledge-base/specs/feat-ralph-loop-idle-detection/`
- [ ] 1.3 Merge `knowledge-base/features/specs/archive/` contents into `knowledge-base/specs/archive/`
- [ ] 1.4 Remove empty `knowledge-base/features/` directory tree

## Phase 2: Merge project/brainstorms/ into brainstorms/

- [ ] 2.1 Move all `knowledge-base/project/brainstorms/*.md` files to `knowledge-base/brainstorms/`
- [ ] 2.2 Merge `knowledge-base/project/brainstorms/archive/` contents into `knowledge-base/brainstorms/archive/`
- [ ] 2.3 Verify `knowledge-base/project/brainstorms/` is empty and remove

## Phase 3: Merge project/learnings/ into learnings/

- [ ] 3.1 Move all flat `knowledge-base/project/learnings/*.md` files to `knowledge-base/learnings/`
- [ ] 3.2 Move all 12 category subdirectories from `project/learnings/` to `knowledge-base/learnings/` (`bug-fixes/`, `build-errors/`, `docs-site/`, `implementation-patterns/`, `integration-issues/`, `logic-errors/`, `performance-issues/`, `runtime-errors/`, `technical-debt/`, `ui-bugs/`, `workflow-issues/`, `workflow-patterns/`)
- [ ] 3.3 Verify `knowledge-base/project/learnings/` is empty and remove

## Phase 4: Merge project/plans/ into plans/

- [ ] 4.1 Move all `knowledge-base/project/plans/*.md` files to `knowledge-base/plans/`
- [ ] 4.2 Merge `knowledge-base/project/plans/archive/` contents into `knowledge-base/plans/archive/`
- [ ] 4.3 Verify `knowledge-base/project/plans/` is empty and remove

## Phase 5: Merge project/specs/ into specs/

- [ ] 5.1 Move all non-overlapping `feat-*` directories from `project/specs/` to `knowledge-base/specs/`
- [ ] 5.2 Merge overlapping `feat-plausible-goals` contents (keep newest versions of each file)
- [ ] 5.3 Merge overlapping `feat-weekly-analytics-improvements` contents (keep newest versions of each file)
- [ ] 5.4 Merge `knowledge-base/project/specs/archive/` contents into `knowledge-base/specs/archive/`
- [ ] 5.5 Move `knowledge-base/project/specs/external/` to `knowledge-base/specs/external/` (if not already present)
- [ ] 5.6 Verify `knowledge-base/project/specs/` is empty and remove

## Phase 6: Update Documentation

- [ ] 6.1 Update `knowledge-base/project/components/knowledge-base.md` directory tree to reflect consolidated structure
- [ ] 6.2 Verify `knowledge-base/project/` only contains `constitution.md`, `README.md`, `components/`

## Phase 7: Verification

- [ ] 7.1 Verify `knowledge-base/features/` does not exist
- [ ] 7.2 Verify `knowledge-base/project/` only has `constitution.md`, `README.md`, `components/`
- [ ] 7.3 Verify `knowledge-base/brainstorms/` has all 33+ brainstorm files
- [ ] 7.4 Verify `knowledge-base/learnings/` has all 198+ learning files including 12 category subdirs
- [ ] 7.5 Verify `knowledge-base/plans/` has all 100+ plan files
- [ ] 7.6 Verify `knowledge-base/specs/` has all 102+ spec directories
- [ ] 7.7 Run `git status` to confirm all changes are tracked via `git mv`
- [ ] 7.8 Run `/soleur:compound` before committing
