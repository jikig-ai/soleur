# Tasks: fix test-fix-loop stash to commits

## Phase 1: Core Implementation

- [ ] 1.1 Update SKILL.md frontmatter description
  - [ ] 1.1.1 Replace "git stash isolation" with "checkpoint commit isolation" in description field

- [ ] 1.2 Update Phase 0 clean tree check
  - [ ] 1.2.1 Update rationale text from stash interleaving to checkpoint commit safety

- [ ] 1.3 Replace termination conditions table
  - [ ] 1.3.1 Change "Drop stash" references to commit-based equivalents
  - [ ] 1.3.2 Change "Pop stash (revert)" references to `git reset --hard` to initial SHA
  - [ ] 1.3.3 Add initial SHA capture instruction before the loop starts

- [ ] 1.4 Rewrite "4. Stash and Fix" section
  - [ ] 1.4.1 Rename section to "4. Checkpoint and Fix"
  - [ ] 1.4.2 Add initial SHA capture: `initial_sha=$(git rev-parse HEAD)` before loop
  - [ ] 1.4.3 Replace `git stash push` with `git add -A && git commit -m "test-fix-loop: checkpoint iteration N"`
  - [ ] 1.4.4 Replace success path: `git stash drop` becomes no-op (checkpoint stays in history)
  - [ ] 1.4.5 Replace progress path: `git stash drop` becomes commit progress and continue
  - [ ] 1.4.6 Replace regression path: `git stash pop` becomes `git reset --hard <initial_sha>`

- [ ] 1.5 Update Key Principles section
  - [ ] 1.5.1 Replace "stash before every fix attempt" with "checkpoint commit before every fix attempt"

## Phase 2: Secondary Updates

- [ ] 2.1 Update README.md skill table
  - [ ] 2.1.1 Change test-fix-loop description from "git stash isolation" to "checkpoint commit isolation"

## Phase 3: Verification

- [ ] 3.1 Verify zero `git stash` occurrences in SKILL.md
  - [ ] 3.1.1 Run grep to confirm no stash references remain

- [ ] 3.2 Verify CHANGELOG.md is NOT modified

- [ ] 3.3 Run markdownlint on modified files
