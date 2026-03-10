---
title: "fix: prevent stale screenshot accumulation and clean up existing files"
type: fix
date: 2026-03-10
semver: patch
---

# Fix Stale Screenshot Accumulation

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 5
**Research conducted:** gitignore negation patterns, full skill audit for screenshot producers, tracked-vs-untracked PNG inventory, cleanup safety analysis

### Key Improvements
1. Identified `gemini-imagegen` as a fifth screenshot-producing skill (writes `output.png` to CWD) -- covered by the blanket `*.png` rule
2. Discovered cleanup command `rm -f *.png` in repo root is safe -- tracked PNGs (`vision-master-plan-*.png`) survive because `rm -f` only deletes working tree files while git retains them; however, the .gitignore will then hide them from future `git status` unless negated or `git rm --cached`
3. Added concrete bash commands to skill cleanup sections instead of prose-only instructions
4. Flagged that `feature-video/` and `screenshots/` directories (tracked PNGs) should be cleaned up via `git rm --cached` in a follow-up issue to avoid gitignore hiding modifications

### New Considerations Discovered
- The blanket `*.png` gitignore will suppress `git status` output for modifications to tracked root-level PNGs (`vision-master-plan-*.png`) -- these should be `git rm --cached` in this PR or the next
- `gemini-imagegen` skill also produces PNGs in CWD (`output.png`) -- no cleanup phase exists, but covered by gitignore
- The `review/references/review-e2e-testing.md` reference routes to `/test-browser` which then produces screenshots -- cleanup at the test-browser level is the correct fix point

## Overview

29 untracked PNG files have accumulated in the main repo root and 16 more in `tmp/` from Playwright MCP screenshots, browser-test sessions, and feature-video recordings. These are test artifacts that should never be committed. The root causes are: (1) no .gitignore rules for PNGs or tmp/, (2) skills that produce screenshots lack cleanup steps, (3) feature-video cleanup is conditional on ffmpeg, so screenshots persist when ffmpeg is absent.

## Problem Statement

Playwright MCP resolves relative filenames from the main repo root (not the shell CWD or worktree). This is documented in learning `2026-02-17-playwright-screenshots-land-in-main-repo.md`. Combined with missing .gitignore rules, every browser-test, reproduce-bug, and feature-video session leaves orphan PNGs that accumulate silently. A careless `git add .` from main would commit 45+ binary files.

### Screenshot-Producing Skills (Full Audit)

| Skill | Tool | Output Location | Has Cleanup? |
|-------|------|----------------|--------------|
| `test-browser` | agent-browser CLI | CWD (e.g., `page-name.png`) | No |
| `reproduce-bug` | Playwright MCP | Main repo root (`bug-*.png`) | No |
| `feature-video` | agent-browser CLI | `tmp/screenshots/`, `tmp/videos/` | Conditional (ffmpeg only) |
| `gemini-imagegen` | Pillow/Python | CWD (`output.png`) | No |
| `agent-browser` | agent-browser CLI | CWD (utility skill, not orchestrator) | N/A |

### Current State

- **29 untracked PNGs** in repo root (e.g., `agents-page.png`, `homepage-test.png`, `x-developer-console.png`)
- **16 files in `tmp/`** (screenshots/, videos/, and loose PNGs from X signup flow)
- **14 tracked PNGs** in committed directories:
  - `plugins/soleur/docs/images/` (4 files: favicon, logo, og-image, x-banner) -- legitimate assets
  - `plugins/soleur/docs/screenshots/` (3 files: docs site screenshots) -- legitimate assets
  - `feature-video/` (3 files) -- stale demo artifacts, candidates for removal
  - `screenshots/` (8 files) -- stale screenshots, candidates for removal
  - `vision-master-plan-desktop.png`, `vision-master-plan-mobile.png` -- stale, candidates for removal
- **.gitignore** has `.playwright-mcp/` (covers auto-named MCP screenshots) but no `*.png` rule and no `tmp/` rule
- **test-browser** SKILL.md has no cleanup phase
- **reproduce-bug** SKILL.md has no cleanup phase
- **feature-video** SKILL.md cleanup is conditional: only deletes screenshots when `HAS_FFMPEG=true`

## Proposed Solution

Four changes, all low-risk and independently testable:

### 1. Add .gitignore rules for PNGs and tmp/

Add `*.png` and `tmp/` to `.gitignore` with negation patterns to preserve legitimate tracked assets.

#### Exact .gitignore additions (append after existing rules)

```gitignore
# Screenshot and video artifacts (browser tests, feature demos, image generation)
*.png
tmp/

# Legitimate image assets (negate the blanket *.png rule)
!plugins/soleur/docs/images/*.png
!plugins/soleur/docs/screenshots/*.png
```

#### Research Insights

**Negation pattern mechanics:**
- Negation (`!path`) only works when the pattern negates a file, not a directory. Since `*.png` ignores files (not directories), the `!plugins/soleur/docs/images/*.png` negation works correctly.
- Negation patterns MUST appear AFTER the rule they negate. Git processes `.gitignore` top-to-bottom; the last matching rule wins.
- Negation cannot un-ignore a file inside an ignored directory. Since we ignore `*.png` (a file glob) and not `plugins/` (a directory), intermediate directories are not ignored and negation works.

**Edge case -- tracked files and the blanket rule:**
- `.gitignore` does not affect files already tracked by git. The 14 committed PNGs remain in the index.
- However, the blanket `*.png` rule means `git status` will suppress display of these files even when modified. This is a subtle UX issue: if someone modifies `vision-master-plan-desktop.png`, `git status` won't show the change.
- **Recommendation:** Run `git rm --cached` on the 13 tracked PNGs outside `plugins/soleur/docs/` in this PR. This un-tracks them without deleting the working tree copies (which are already gitignored after the rule is added). This cleanly separates "legitimate docs images" from "stale artifacts that should never have been tracked."

**Files to `git rm --cached` (optional but recommended):**
```bash
git rm --cached feature-video/01-homepage-stats.png feature-video/02-agents-nav-with-finance.png feature-video/03-finance-section.png screenshots/docs-404.png screenshots/docs-agents.png screenshots/docs-index-styled.png screenshots/docs-index.png screenshots/final-desktop-1200.png screenshots/final-mobile-375.png screenshots/video-desktop.png screenshots/video-mobile.png screenshots/video-tablet.png vision-master-plan-desktop.png vision-master-plan-mobile.png
```

### 2. Add cleanup phase to test-browser skill

Add a "Cleanup" section after the existing "Test Summary" (Section 8) in `plugins/soleur/skills/test-browser/SKILL.md`.

#### Concrete addition (after line 294, the `</test_summary>` closing tag)

```markdown
### 9. Cleanup

<cleanup>

After all tests complete, remove screenshot artifacts produced during the session. Playwright MCP writes screenshots to the main repo root when invoked from a worktree, so check both locations.

```bash
# Remove session screenshots from current working directory
rm -f *.png

# If in a worktree, also clean the main repo root
MAIN_REPO=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [[ -n "$MAIN_REPO" ]]; then
  rm -f "$MAIN_REPO"/*.png
fi
```

**Do NOT delete** files under `plugins/soleur/docs/` -- those are legitimate assets.

</cleanup>
```

### 3. Add cleanup phase to reproduce-bug skill

Add a cleanup phase to `plugins/soleur/skills/reproduce-bug/SKILL.md` after Phase 4.

#### Concrete addition (after the Phase 4: Report Back section)

```markdown
## Phase 5: Cleanup

After uploading screenshots to the issue comment, remove local screenshot artifacts. Playwright MCP writes to the main repo root when invoked from a worktree.

```bash
# Remove bug reproduction screenshots from current working directory
rm -f bug-*.png

# If in a worktree, also clean the main repo root
MAIN_REPO=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [[ -n "$MAIN_REPO" ]]; then
  rm -f "$MAIN_REPO"/bug-*.png
fi
```
```

#### Research Insights

- The reproduce-bug skill uses Playwright MCP (`mcp__plugin_soleur_pw__browser_take_screenshot`) with filenames like `bug-[issue]-step-1.png` and `bug-[issue]-reproduced.png`. These always land in the main repo root.
- The `bug-*.png` glob is safe because no legitimate files match this pattern.
- The `git rev-parse --show-superproject-working-tree` check reliably detects worktrees -- it returns the main repo path when in a worktree, empty otherwise.

### 4. Make feature-video cleanup unconditional

In `plugins/soleur/skills/feature-video/SKILL.md`, Section 8 (Cleanup), replace the conditional logic.

#### Current code (lines 311-317)

```bash
if [ "$HAS_FFMPEG" = "true" ]; then
  rm -rf tmp/screenshots
  echo "Screenshots cleaned up (video retained at tmp/videos/)"
else
  echo "Screenshots retained at tmp/screenshots/ (no video conversion)"
fi
```

#### Replacement

```bash
# Always clean up tmp artifacts after PR description is updated
rm -rf tmp/screenshots tmp/videos
echo "Cleaned up tmp/screenshots/ and tmp/videos/"
```

#### Research Insights

- The original conditional preserved screenshots when ffmpeg was absent, reasoning they were the "final output." But the screenshots are also embedded/linked in the PR description (Case C in Section 7), so keeping them locally is redundant.
- Also clean `tmp/videos/` -- video files are either uploaded (rclone) or linked locally in the PR description. No reason to retain them.
- `rm -rf` on `tmp/screenshots` and `tmp/videos` is safe per constitution: "tmp/screenshots/ is a dedicated artifact directory, not user data."

## Non-goals

- Adding a pre-commit hook to block PNG commits (the .gitignore rule is sufficient prevention)
- Changing Playwright MCP behavior (upstream issue; absolute paths are the documented workaround)
- Adding `.gif` or `.mp4` to .gitignore (no evidence of accumulation; feature-video retains GIFs intentionally for PR embeds)
- Adding cleanup to `gemini-imagegen` (low-frequency skill; covered by the blanket gitignore rule)
- Adding cleanup to `agent-browser` (utility skill, not an orchestrator; callers handle cleanup)

## Acceptance Criteria

- [ ] `.gitignore` contains `*.png` rule with negation for `plugins/soleur/docs/images/*.png` and `plugins/soleur/docs/screenshots/*.png`
- [ ] `.gitignore` contains `tmp/` rule
- [ ] `test-browser/SKILL.md` includes a cleanup section (Section 9) with concrete bash commands
- [ ] `reproduce-bug/SKILL.md` includes a cleanup phase (Phase 5) with concrete bash commands
- [ ] `feature-video/SKILL.md` cleanup step removes `tmp/screenshots/` and `tmp/videos/` unconditionally (not gated on `HAS_FFMPEG`)
- [ ] All 29 untracked PNGs in repo root are deleted from the main repo working tree
- [ ] All files in `tmp/` are deleted from the main repo working tree
- [ ] `git status` from main repo root shows no `*.png` or `tmp/` untracked files after cleanup
- [ ] Legitimate tracked PNGs in `plugins/soleur/docs/` remain unaffected
- [ ] (Optional) Stale tracked PNGs outside docs/ are un-tracked via `git rm --cached`

## Test Scenarios

- Given `.gitignore` has `*.png` and `tmp/` rules, when a Playwright screenshot lands in repo root, then `git status` does not show it as untracked
- Given `.gitignore` has `!plugins/soleur/docs/images/*.png`, when a new image is added to `plugins/soleur/docs/images/`, then `git status` shows it as untracked (can be committed)
- Given `.gitignore` has `!plugins/soleur/docs/screenshots/*.png`, when a new screenshot is added to `plugins/soleur/docs/screenshots/`, then `git status` shows it as untracked
- Given feature-video runs without ffmpeg, when the skill reaches the cleanup phase, then `tmp/screenshots/` is still deleted
- Given test-browser completes a session in a worktree, when cleanup runs, then no orphan PNGs remain in either the worktree CWD or the main repo root
- Given reproduce-bug runs via Playwright MCP in a worktree, when cleanup runs, then `bug-*.png` files are removed from the main repo root
- Given a `touch test.png` is run in the repo root, when `git status` is checked, then `test.png` does not appear (ignored)
- Given a `touch plugins/soleur/docs/images/new-asset.png` is run, when `git status` is checked, then `new-asset.png` appears as untracked (negation works)

## Technical Considerations

- **Tracked files immune to .gitignore**: The 14 already-committed PNGs remain in the index. `.gitignore` only prevents NEW untracked PNGs from showing in status. However, it also suppresses display of modifications to tracked files matching the pattern -- use `git rm --cached` to clean up stale tracked PNGs.
- **Negation pattern ordering**: In `.gitignore`, negation patterns (`!path`) must come AFTER the blanket rule (`*.png`). Order matters -- git processes rules top-to-bottom.
- **Negation with intermediate directories**: Works correctly here because we ignore `*.png` (a file pattern), not the parent directories. Negation fails only when a parent directory is ignored.
- **Worktree vs main repo**: The untracked PNGs live in the main repo root, not in worktrees. Cleanup must target the main repo. The `.gitignore` change applies to both (shared `.gitignore`). The cleanup sections in skills use `git rev-parse --show-superproject-working-tree` to detect and clean both locations.
- **feature-video `rm -rf tmp/screenshots`**: Safe because `tmp/screenshots/` is a dedicated artifact directory, not user data.
- **`rm -f *.png` safety in repo root**: Only deletes working tree copies. Tracked files remain in git's object database and can be recovered with `git checkout -- <file>`. After `.gitignore` is updated, these recovered files would again be ignored.

## Files to Modify

| File | Change |
|------|--------|
| `.gitignore` | Add `*.png`, `tmp/`, and negation patterns for `plugins/soleur/docs/` |
| `plugins/soleur/skills/test-browser/SKILL.md` | Add Section 9: Cleanup with bash commands |
| `plugins/soleur/skills/reproduce-bug/SKILL.md` | Add Phase 5: Cleanup with bash commands |
| `plugins/soleur/skills/feature-video/SKILL.md` | Make cleanup unconditional in Section 8, also clean tmp/videos/ |

## Cleanup (one-time, from main repo root)

```bash
# Delete untracked PNGs from repo root (29 files)
rm -f *.png

# Delete tmp/ directory (16 files)
rm -rf tmp/

# Optional: un-track stale committed PNGs outside docs/
git rm --cached feature-video/*.png screenshots/*.png vision-master-plan-*.png 2>/dev/null || true

# Verify
git status --short | grep -E '\.png$' || echo "No untracked PNGs"
ls tmp/ 2>/dev/null || echo "tmp/ removed"
```

## References

- Learning: `knowledge-base/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`
- Learning: `knowledge-base/learnings/2026-02-27-feature-video-graceful-degradation.md`
- Constitution: "Add test/temp build output directories to .gitignore when introducing new build commands"
- AGENTS.md: "MCP tools resolve paths from the repo root, not the shell CWD"
- `.gitignore` already has `.playwright-mcp/` rule (covers auto-named MCP screenshots)
