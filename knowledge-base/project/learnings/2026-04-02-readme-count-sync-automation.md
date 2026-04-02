# Learning: README count sync automation

## Problem

README files had hardcoded component counts (agents, skills, commands) that drifted from the actual filesystem. The website was immune because `docs/_data/stats.js` counts dynamically at build time, but both `README.md` and `plugins/soleur/README.md` used static numbers. The `/ship` skill checked plugin README counts but not root README. The `release-docs` skill required manual counting. No CI validation existed to catch drift.

## Solution

Created `scripts/sync-readme-counts.sh` that counts components from the filesystem and patches both READMEs. Supports `--check` mode for CI validation (exit 1 on drift). Integrated into:

- `/ship` Phase 3: runs script automatically when components change
- `/release-docs` Step 1: replaced manual counting instructions
- CI: new `readme-counts` job in `ci.yml` validates on every PR

## Key Insight

When the same data exists in multiple places (filesystem, website, two READMEs), the website solved this correctly (dynamic counting at build time) while the READMEs relied on human discipline. The fix mirrors the website's approach: count from the source of truth (filesystem) and propagate automatically. The pattern is: if a value is derivable, derive it — don't maintain it manually.

## Session Errors

1. **Worktree manager script created worktree but directory not found afterward** — The `worktree-manager.sh feature` script reported success but the resulting directory wasn't accessible. Recovery: used raw `git worktree add` directly. Prevention: investigate why the manager script's output path didn't match expectations in bare repo contexts.

2. **Bare repo git commands fail in worktrees** — Standard `git diff`, `git status`, `git commit` all fail with "this operation must be run in a work tree" even when CWD is inside a worktree. The bare repo's `core.bare=true` config propagates through the worktree's `.git` pointer. Recovery: used `GIT_WORK_TREE=<path>` env var prefix. Prevention: this is a known constraint of the bare repo setup — other worktrees use the manager script which handles this internally.

3. **sed delimiter collision with pipe characters** — Initial script used `|` as sed delimiter but the markdown table content also contains `|`, causing `sed: unknown option to 's'`. Recovery: switched to `#` delimiter for table row replacements. Prevention: always use a delimiter that doesn't appear in the replacement content (`#` or `%` for markdown).

## Tags

category: workflow-automation
module: scripts, ci, ship-skill, release-docs-skill
