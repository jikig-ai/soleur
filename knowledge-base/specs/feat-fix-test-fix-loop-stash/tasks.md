# Tasks: fix test-fix-loop stash to commits

## Phase 1: Core Implementation

- [x] 1.1 Update SKILL.md frontmatter description
  - [x] 1.1.1 Replace "git stash isolation" with "checkpoint commit isolation" in description field

- [x] 1.2 Update Phase 0 clean tree check
  - [x] 1.2.1 Update rationale text from stash interleaving to checkpoint commit safety

- [x] 1.3 Add initial SHA capture before the loop
  - [x] 1.3.1 Add instruction to record current commit SHA as `<initial-sha>` before entering the loop (use prose placeholders, no `$()`)

- [x] 1.4 Replace termination conditions table
  - [x] 1.4.1 Change "Drop stash" references to no-op (checkpoint commits stay in history)
  - [x] 1.4.2 Change "Pop stash (revert to last good state)" to `git reset --hard HEAD` (discard uncommitted fixes)
  - [x] 1.4.3 Change "Pop stash (revert)" for circular/non-convergence/build-error to `git reset --hard <initial-sha>` (revert all iterations)

- [x] 1.5 Rewrite "4. Stash and Fix" section
  - [x] 1.5.1 Rename section to "4. Checkpoint and Fix"
  - [x] 1.5.2 Replace `git stash push` with checkpoint commit: `git add -A && git commit -m "test-fix-loop: checkpoint iteration N"` (skip on iteration 1 if tree is clean)
  - [x] 1.5.3 Replace success path: fixes remain in working tree as uncommitted changes, stage with `git add -A`
  - [x] 1.5.4 Replace progress path: fixes stay in working tree, next iteration's checkpoint commits them
  - [x] 1.5.5 Replace regression path: `git reset --hard HEAD` discards uncommitted fixes
  - [x] 1.5.6 Ensure no `$()` shell expansion in code blocks (constitution prohibition)

- [x] 1.6 Update Key Principles section
  - [x] 1.6.1 Replace "stash before every fix attempt, revert on regression" with "checkpoint commit before every fix attempt, revert on regression"

## Phase 2: Secondary Updates

- [x] 2.1 Update README.md skill table
  - [x] 2.1.1 Change test-fix-loop description from "git stash isolation" to "checkpoint commit isolation" (line 269)

## Phase 3: Verification

- [x] 3.1 Verify zero `git stash` occurrences in SKILL.md
  - [x] 3.1.1 Run grep to confirm no stash references remain in SKILL.md

- [x] 3.2 Verify zero `$(` occurrences in SKILL.md code blocks
  - [x] 3.2.1 Run grep to confirm no shell variable expansion in code blocks

- [x] 3.3 Verify CHANGELOG.md is NOT modified

- [x] 3.4 Run markdownlint on modified files
