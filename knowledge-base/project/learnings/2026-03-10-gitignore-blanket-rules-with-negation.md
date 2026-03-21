---
title: Gitignore blanket rules with negation patterns for artifact types
date: 2026-03-10
category: workflow
tags: [gitignore, screenshots, artifacts, cleanup, prevention]
module: infrastructure
symptoms: [untracked-png-files-accumulating, git-status-cluttered, binary-artifacts-in-repo]
---

# Gitignore Blanket Rules with Negation Patterns for Artifact Types

## Problem

44+ untracked PNG screenshots accumulated in the repo root from four different skills (test-browser, reproduce-bug, feature-video, gemini-imagegen). Each skill produced screenshots in different locations with no cleanup. A careless `git add .` could commit all binary artifacts.

## Solution

Two-layer defense:

1. **Gitignore blanket rule with negation** -- ignore all `*.png` and `tmp/` at the repo level, then negate specific directories containing legitimate assets:

```gitignore
*.png
tmp/
!plugins/soleur/docs/images/*.png
!plugins/soleur/docs/screenshots/*.png
```

2. **Skill-level cleanup sections** -- each screenshot-producing skill now deletes its own artifacts after use, with worktree-aware detection:

```bash
MAIN_REPO=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [[ -n "$MAIN_REPO" ]]; then
  rm -f "$MAIN_REPO"/*.png
fi
```

Also un-tracked 14 stale committed PNGs via `git rm --cached` to avoid the gitignore suppressing modification display for tracked files.

## Key Insight

Gitignore negation patterns only work when the blanket rule targets files (not directories). `*.png` ignores files, so parent directories remain visible to git and `!path/to/dir/*.png` correctly un-ignores specific subdirectories. If the blanket rule ignored a parent directory instead, negation would fail silently. The negation patterns are also single-depth -- a future `plugins/soleur/docs/images/subfolder/img.png` would be ignored.

## Session Errors

1. Ralph loop setup script: first attempt used wrong path, corrected immediately.

## Tags

category: workflow
module: infrastructure
