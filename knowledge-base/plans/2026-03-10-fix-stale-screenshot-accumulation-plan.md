---
title: "fix: prevent stale screenshot accumulation and clean up existing files"
type: fix
date: 2026-03-10
semver: patch
---

# Fix Stale Screenshot Accumulation

## Overview

29 untracked PNG files have accumulated in the main repo root and 16 more in `tmp/` from Playwright MCP screenshots, browser-test sessions, and feature-video recordings. These are test artifacts that should never be committed. The root causes are: (1) no .gitignore rules for PNGs or tmp/, (2) skills that produce screenshots lack cleanup steps, (3) feature-video cleanup is conditional on ffmpeg, so screenshots persist when ffmpeg is absent.

## Problem Statement

Playwright MCP resolves relative filenames from the main repo root (not the shell CWD or worktree). This is documented in learning `2026-02-17-playwright-screenshots-land-in-main-repo.md`. Combined with missing .gitignore rules, every browser-test, reproduce-bug, and feature-video session leaves orphan PNGs that accumulate silently. A careless `git add .` from main would commit 45+ binary files.

### Current State

- **29 untracked PNGs** in repo root (e.g., `agents-page.png`, `homepage-test.png`, `x-developer-console.png`)
- **16 files in `tmp/`** (screenshots/, videos/, and loose PNGs from X signup flow)
- **14 tracked PNGs** in committed directories (`feature-video/`, `screenshots/`, `vision-master-plan-*.png`, `plugins/soleur/docs/images/`, `plugins/soleur/docs/screenshots/`)
- **.gitignore** has no `*.png` rule and no `tmp/` rule
- **test-browser** SKILL.md has no cleanup phase
- **reproduce-bug** SKILL.md has no cleanup phase
- **feature-video** SKILL.md cleanup is conditional: only deletes screenshots when `HAS_FFMPEG=true`

## Proposed Solution

Four changes, all low-risk and independently testable:

### 1. Add .gitignore rules for PNGs and tmp/

Add `*.png` and `tmp/` to `.gitignore` with negation patterns to preserve legitimate tracked assets:

```gitignore
# Screenshot and video artifacts (browser tests, feature demos)
*.png
tmp/

# Legitimate image assets (negate the blanket *.png rule)
!plugins/soleur/docs/images/*.png
!plugins/soleur/docs/screenshots/*.png
```

**Edge case: already-tracked PNGs.** `.gitignore` does not affect files already tracked by git. The 14 committed PNGs (`feature-video/`, `screenshots/`, `vision-master-plan-*.png`) will remain tracked. To fully clean them, they would need `git rm --cached` -- but that is a separate concern and should be handled in a follow-up issue if desired, not in this PR.

### 2. Add cleanup phase to test-browser skill

Add a "Cleanup" section after the existing "Test Summary" (Section 8) in `plugins/soleur/skills/test-browser/SKILL.md`:

```markdown
### 9. Cleanup

After tests complete, remove screenshot artifacts produced during the session:

- Delete any `.png` files created by this session in the current working directory
- Delete any `.png` files that landed in the main repo root (Playwright MCP writes there when in a worktree)
- Do NOT delete files under `plugins/soleur/docs/` (legitimate assets)
```

### 3. Add cleanup phase to reproduce-bug skill

Add a cleanup note to `plugins/soleur/skills/reproduce-bug/SKILL.md` after Phase 4:

```markdown
## Phase 5: Cleanup

After reporting findings, remove screenshot artifacts:

- Delete `bug-*.png` files created during reproduction
- If working in a worktree, also check the main repo root for misplaced screenshots
```

### 4. Make feature-video cleanup unconditional

In `plugins/soleur/skills/feature-video/SKILL.md`, Section 8 (Cleanup), the current logic:

```bash
if [ "$HAS_FFMPEG" = "true" ]; then
  rm -rf tmp/screenshots
fi
```

Should become unconditional -- always clean up `tmp/screenshots/` and `tmp/videos/` after the PR description is updated. The screenshots are embedded/linked in the PR at that point; keeping them locally serves no purpose.

## Non-goals

- Removing already-tracked PNGs from git history (would require `git filter-repo` or `git rm --cached`; separate concern)
- Adding a pre-commit hook to block PNG commits (the .gitignore rule is sufficient prevention)
- Changing Playwright MCP behavior (upstream issue; absolute paths are the documented workaround)
- Adding `.gif` or `.mp4` to .gitignore (no evidence of accumulation; feature-video retains these intentionally)

## Acceptance Criteria

- [ ] `.gitignore` contains `*.png` rule with negation for `plugins/soleur/docs/images/*.png` and `plugins/soleur/docs/screenshots/*.png`
- [ ] `.gitignore` contains `tmp/` rule
- [ ] `test-browser/SKILL.md` includes a cleanup section (Section 9)
- [ ] `reproduce-bug/SKILL.md` includes a cleanup phase (Phase 5)
- [ ] `feature-video/SKILL.md` cleanup step removes `tmp/screenshots/` unconditionally (not gated on `HAS_FFMPEG`)
- [ ] All 29 untracked PNGs in repo root are deleted from the main repo working tree
- [ ] All files in `tmp/` are deleted from the main repo working tree
- [ ] `git status` from main repo root shows no `*.png` or `tmp/` untracked files after cleanup
- [ ] Legitimate tracked PNGs in `plugins/soleur/docs/` remain unaffected

## Test Scenarios

- Given `.gitignore` has `*.png` and `tmp/` rules, when a Playwright screenshot lands in repo root, then `git status` does not show it as untracked
- Given `.gitignore` has `!plugins/soleur/docs/images/*.png`, when a new image is added to `plugins/soleur/docs/images/`, then `git status` shows it as untracked (can be committed)
- Given feature-video runs without ffmpeg, when the skill reaches the cleanup phase, then `tmp/screenshots/` is still deleted
- Given test-browser completes a session, when cleanup runs, then no orphan PNGs remain in the working directory or main repo root

## Technical Considerations

- **Tracked files immune to .gitignore**: The 14 already-committed PNGs (`feature-video/*.png`, `screenshots/*.png`, `vision-master-plan-*.png`) remain tracked. `.gitignore` only prevents NEW untracked PNGs from showing in status.
- **Negation pattern ordering**: In `.gitignore`, negation patterns (`!path`) must come AFTER the blanket rule (`*.png`). Order matters.
- **Worktree vs main repo**: The untracked PNGs live in the main repo root, not in worktrees. Cleanup must target the main repo. The .gitignore change applies to both (shared `.gitignore`).
- **feature-video `rm -rf tmp/screenshots`**: Safe because `tmp/screenshots/` is a dedicated artifact directory, not user data.

## Files to Modify

| File | Change |
|------|--------|
| `.gitignore` | Add `*.png`, `tmp/`, and negation patterns |
| `plugins/soleur/skills/test-browser/SKILL.md` | Add Section 9: Cleanup |
| `plugins/soleur/skills/reproduce-bug/SKILL.md` | Add Phase 5: Cleanup |
| `plugins/soleur/skills/feature-video/SKILL.md` | Make cleanup unconditional in Section 8 |

## Cleanup (one-time, from main repo root)

```bash
# Delete untracked PNGs from repo root
rm -f *.png

# Delete tmp/ directory
rm -rf tmp/

# Verify
git status --short | grep -E '\.(png|tmp)' || echo "Clean"
```

## References

- Learning: `knowledge-base/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`
- Learning: `knowledge-base/learnings/2026-02-27-feature-video-graceful-degradation.md`
- Constitution: "Add test/temp build output directories to .gitignore when introducing new build commands"
- AGENTS.md: "MCP tools resolve paths from the repo root, not the shell CWD"
