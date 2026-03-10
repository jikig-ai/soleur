# Tasks: Fix Stale Screenshot Accumulation

## Phase 1: Setup

- [ ] 1.1 Read current `.gitignore`
- [ ] 1.2 Inventory untracked PNGs in main repo root (`ls *.png` from main repo)
- [ ] 1.3 Inventory `tmp/` contents in main repo root
- [ ] 1.4 Confirm legitimate tracked PNGs in `plugins/soleur/docs/images/` and `plugins/soleur/docs/screenshots/`

## Phase 2: Core Implementation

- [ ] 2.1 Add `*.png` rule to `.gitignore`
- [ ] 2.2 Add `tmp/` rule to `.gitignore`
- [ ] 2.3 Add negation patterns for legitimate assets:
  - [ ] 2.3.1 `!plugins/soleur/docs/images/*.png`
  - [ ] 2.3.2 `!plugins/soleur/docs/screenshots/*.png`
- [ ] 2.4 Add cleanup section (Section 9) to `plugins/soleur/skills/test-browser/SKILL.md`
- [ ] 2.5 Add cleanup phase (Phase 5) to `plugins/soleur/skills/reproduce-bug/SKILL.md`
- [ ] 2.6 Make cleanup unconditional in `plugins/soleur/skills/feature-video/SKILL.md` Section 8
  - [ ] 2.6.1 Remove `if [ "$HAS_FFMPEG" = "true" ]` conditional
  - [ ] 2.6.2 Always delete `tmp/screenshots/` and `tmp/videos/` after PR update
- [ ] 2.7 Delete 29 untracked PNGs from main repo root
- [ ] 2.8 Delete `tmp/` directory from main repo root

## Phase 3: Testing

- [ ] 3.1 Verify `git status` from main repo shows no untracked PNGs or tmp/
- [ ] 3.2 Verify tracked PNGs in `plugins/soleur/docs/` are unaffected
- [ ] 3.3 Create a test PNG in repo root, confirm it is ignored by `git status`
- [ ] 3.4 Create a test PNG in `plugins/soleur/docs/images/`, confirm it IS shown by `git status`
- [ ] 3.5 Clean up test files from 3.3 and 3.4
