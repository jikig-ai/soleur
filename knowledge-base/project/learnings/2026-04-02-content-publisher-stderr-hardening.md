# Learning: Content publisher stderr capture needs hardening for public issues

## Problem

PR #1359 (bot-fix for #1160) added stderr capture to LinkedIn fallback issues in `scripts/content-publisher.sh`. The multi-agent review identified two P2 issues:

1. **Temp file leak under `set -e`:** All `mktemp` calls (X/Twitter + LinkedIn) lacked cleanup on abnormal exits. Under `set -euo pipefail`, any unexpected failure between `mktemp` and `rm -f` leaks the temp file.
2. **Unsanitized stderr in public issues:** Raw stderr content was embedded in public GitHub issues without truncation or safe Markdown formatting. Inline backtick wrapping breaks on multi-line content or content containing backticks.

## Solution

1. Added `_TMPFILES` array + `trap EXIT` + `make_tmp()` helper at file scope. Replaced all 4 bare `mktemp` calls with `make_tmp`. This provides defense-in-depth: explicit `rm -f` in success/error paths for immediate cleanup, plus trap for abnormal exits.
2. Replaced `cat "$stderr_file"` with `head -c 1000 "$stderr_file"` to bound captured content.
3. Switched from inline backticks to fenced code block and added `${error_reason:0:1000}` truncation in `create_linkedin_fallback_issue`.

## Key Insight

When piping external process output into public-facing artifacts (GitHub issues on public repos), always truncate and use safe formatting. The `mktemp` + trap pattern should be standard for any script using `set -e` — the existing X/Twitter code had the same gap and was fixed in the same pass.

## Session Errors

1. **Bare repo worktree git commands fail** — `cd .worktrees/review-1359 && git status` returns `fatal: this operation must be run in a work tree`. Recovery: Used explicit `GIT_DIR`/`GIT_WORK_TREE` env vars. Prevention: Already documented in multiple existing learnings (2026-03-13, 2026-03-14).
2. **Write tool rejected new temp files** — `/tmp/review-finding-001.md` failed because Write requires a prior Read even for new files. Recovery: Used `cat > file << 'EOF'` via Bash. Prevention: Known Claude Code behavior — use Bash for temp files.
3. **FETCH_HEAD stale after branch fetch** — `git show FETCH_HEAD:path` returned pre-PR content. Recovery: Fetched by exact SHA. Prevention: Always verify FETCH_HEAD points to expected commit before using.

## Tags

category: integration-issues
module: content-publisher
