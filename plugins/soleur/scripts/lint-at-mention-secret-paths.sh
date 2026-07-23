#!/usr/bin/env bash
# lint-at-mention-secret-paths.sh
#
# Fails if any Soleur skill/agent/command markdown BODY contains an `@`-mention
# that Claude Code's `@file` auto-attach would resolve to a REAL home/absolute
# filesystem path. When a skill/agent body loads it is delivered as user-turn
# content, and CC scans that content for `@<path>` tokens and reads the
# referenced file into model context (and into on-disk session transcripts).
# A documentation example that quotes an `@`-prefixed real path — e.g. the curl
# `@file` upload form pointing at `~/.doppler/.doppler.yaml` — therefore leaks
# the operator's live secret on every load. This guard prevents that regression.
#
# NOT flagged (intentional): Next.js `@/`-import-alias examples like
# `@/server/...`, `@/lib/...`. Those resolve to nonexistent absolute paths
# (`/server/...`) and never attach a real file. Package scopes (`@types/…`,
# `@playwright/…`) are `@word/…`, not `@/` or `@~`, and are also ignored.
#
# Exit: 0 = clean, 1 = violation(s) found, 2 = usage/repo error.
# Usage: lint-at-mention-secret-paths.sh [REPO_ROOT]   (defaults to git toplevel)
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "FAIL(usage): could not resolve a repo root (arg 1 or git toplevel)." >&2
  exit 2
fi
cd "$ROOT" || exit 2

# `@` + a home/absolute real directory prefix (home dir, or a real OS root dir).
# `@/server/`, `@/lib/` deliberately excluded — not real absolute paths.
HOME_ABS='@(~|\$\{?HOME|/(home|Users|root|etc|var|opt|tmp|srv|mnt|media|private)/)'
# `@` + any path (path-safe chars only, so a backtick/quote/space ends the token)
# ending in a sensitive dotfile/dir/extension.
SENSITIVE='@[A-Za-z0-9_./~$-]*(\.(doppler|ssh|aws|netrc|pem|kube|git-credentials)|/credentials|\.env)'
ERE="(${HOME_ABS})|(${SENSITIVE})"

mapfile -t files < <(git ls-files plugins/soleur/skills plugins/soleur/agents plugins/soleur/commands 2>/dev/null | grep -E '\.md$' || true)

violations=0
for f in "${files[@]}"; do
  [[ -z "$f" ]] && continue
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    echo "VIOLATION: $f:$hit"
    violations=$((violations + 1))
  done < <(grep -nE "$ERE" "$f" 2>/dev/null || true)
done

if [[ "$violations" -gt 0 ]]; then
  {
    echo ""
    echo "FAIL: $violations @-mention(s) resolving to a real home/absolute path in a skill/agent/command body."
    echo "Claude Code's @file auto-attach reads these into model context when the body loads (secret-leak footgun)."
    echo "Fix: keep the real path in a plain code-span with NO literal @ immediately before it"
    echo "(see plugins/soleur/skills/preflight/SKILL.md Check-10 denylist prose for the accepted phrasing)."
  } >&2
  exit 1
fi

echo "OK: no dangerous @-real-path mentions in skill/agent/command bodies (scanned ${#files[@]} markdown files)."
exit 0
