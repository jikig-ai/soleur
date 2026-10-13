# Tasks: Fix Stale Screenshot Accumulation

## Phase 1: Setup

- [ ] 1.1 Read current `.gitignore`
- [ ] 1.2 Inventory untracked PNGs in main repo root (`ls *.png` from main repo)
- [ ] 1.3 Inventory `tmp/` contents in main repo root
- [ ] 1.4 Confirm legitimate tracked PNGs in `plugins/soleur/docs/images/` and `plugins/soleur/docs/screenshots/`
- [ ] 1.5 List tracked PNGs outside docs/ (`git ls-files '*.png'`) to identify `git rm --cached` candidates

## Phase 2: Core Implementation

- [ ] 2.1 Add `*.png` and `tmp/` rules to `.gitignore` with negation patterns for `plugins/soleur/docs/`
  - [ ] 2.1.1 `*.png` rule
  - [ ] 2.1.2 `tmp/` rule
  - [ ] 2.1.3 `!plugins/soleur/docs/images/*.png` negation
  - [ ] 2.1.4 `!plugins/soleur/docs/screenshots/*.png` negation
- [ ] 2.2 Add cleanup section (Section 9) to `plugins/soleur/skills/test-browser/SKILL.md`
  - Include `<cleanup>` tag, bash commands for CWD and main repo root cleanup
  - Use `git rev-parse --show-superproject-working-tree` for worktree detection
- [ ] 2.3 Add cleanup phase (Phase 5) to `plugins/soleur/skills/reproduce-bug/SKILL.md`
  - Target `bug-*.png` glob specifically
  - Include worktree-aware main repo root cleanup
- [ ] 2.4 Make cleanup unconditional in `plugins/soleur/skills/feature-video/SKILL.md` Section 8
  - [ ] 2.4.1 Remove `if [ "$HAS_FFMPEG" = "true" ]` conditional
  - [ ] 2.4.2 Always delete both `tmp/screenshots/` and `tmp/videos/`

## Phase 3: One-Time Cleanup (from main repo root)

- [ ] 3.1 Delete 29 untracked PNGs from main repo root (`rm -f *.png`)
- [ ] 3.2 Delete `tmp/` directory from main repo root (`rm -rf tmp/`)
- [ ] 3.3 (Optional) Un-track stale committed PNGs: `git rm --cached feature-video/*.png screenshots/*.png vision-master-plan-*.png`

## Phase 4: Testing

- [ ] 4.1 Verify `git status` from main repo shows no untracked PNGs or tmp/
- [ ] 4.2 Verify tracked PNGs in `plugins/soleur/docs/` are unaffected
- [ ] 4.3 Create a test PNG in repo root, confirm it is ignored by `git status`
- [ ] 4.4 Create a test PNG in `plugins/soleur/docs/images/`, confirm it IS shown by `git status`
- [ ] 4.5 Create a test PNG in `plugins/soleur/docs/screenshots/`, confirm it IS shown by `git status`
- [ ] 4.6 Clean up test files from 4.3-4.5
