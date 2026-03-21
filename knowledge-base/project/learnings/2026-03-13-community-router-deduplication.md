# Learning: Community router eliminates triple-duplication of platform detection

## Problem

Community platform detection logic was duplicated across 3 files with no single source of truth:

- `SKILL.md` — inline env var table for platform status display
- `community-manager.md` — 35-line Prerequisites section with per-platform checks
- `scheduled-community-monitor.yml` — inline platform detection in workflow prompt

Adding a 5th platform (Hacker News) required editing all 3 files. A 6th would compound the problem. The YAGNI trigger from issue #470 had been met.

## Solution

Created `community-router.sh` (~93 lines) as a thin dispatch router — single source of truth for platform detection and command dispatch.

**Key design decisions:**

1. **Hardcoded PLATFORMS array** with pipe-delimited records: `name|script|env_vars|auth_command`
2. **Three-case `check_auth()`**: auth command (GitHub's `gh auth status`), env var checks (Discord/X/Bluesky), always-enabled (HN has no credentials)
3. **`exec` dispatch**: transparent pass-through to platform scripts preserving exit codes and stdio
4. **Callers reference `$ROUTER <platform> <command>`** instead of hardcoded script paths

All 3 callers updated to delegate to the router. Zero direct script references remain in caller files.

## Session Errors

1. **`replace_all` clobbered ROUTER assignment** — Bulk-replacing `community-router.sh` → `$ROUTER` also clobbered the line `ROUTER="...community-router.sh"` into `ROUTER="...$ROUTER"`. Fix: do targeted replacements, skip definition lines.
2. **`gh auth status` stdout leak** — `2>/dev/null` only suppresses stderr; `gh auth status` writes to stdout. Fix: use `&>/dev/null` for complete suppression.
3. **Complex shell pipeline for error message** — `printf | tr | sed` produced garbled output. Fix: simple `for` loop with `${entry%%|*}` parameter expansion.
4. **Two residual direct script references missed** — `hn-community.sh` and `x-community.sh` references in community-manager.md survived initial bulk replacement. Fix: always grep for old pattern after bulk replacement.
5. **Worktree branch confusion** — `git branch --show-current` returned `main` in the worktree at least 3 times; required manual `git checkout feat/community-platform-adapters`.
6. **Plan overscoped 3x** — Initial plan had 4 phases, shared library, dynamic discovery. All 3 reviewers flagged it. Radically simplified to just the router + caller updates.

## Key Insight

The "thin router over migration" pattern (from learning `2026-02-22-simplify-workflow-thin-router-over-migration.md`) applies perfectly: add a facade, don't reorganize internals. The router doesn't change how platform scripts work — it just centralizes where they're found and dispatched. Adding platform #6 now requires one array entry and one script file.

`replace_all` is unsafe when the search string appears in its own definition. Always verify: `grep -n '=.*OLD_PATTERN' file` before using `replace_all`. If matches exist, do targeted replacements instead.

## Tags

category: integration-issues
module: plugins/soleur/skills/community
issue: 470
related:

- knowledge-base/project/learnings/2026-02-22-simplify-workflow-thin-router-over-migration.md
- knowledge-base/project/learnings/2026-03-12-plan-review-scope-reduction.md
- knowledge-base/project/learnings/2026-03-13-platform-integration-scope-calibration.md
