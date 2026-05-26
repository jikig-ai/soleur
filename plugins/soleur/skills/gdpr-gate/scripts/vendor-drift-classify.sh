#!/usr/bin/env bash
# vendor-drift-classify.sh — severity classifier for an upstream content diff.
#
# Reads a unified diff on stdin. Optional positional args are the SHA pair
# `<old-sha> <new-sha>` (used for rollback detection). Optional flags:
#   --archived   exit 12 (upstream archived; signaled by drift workflow)
#   --renamed    exit 16 (upstream renamed; signaled by drift workflow)
#
# Priority chain (exit-code wins go highest→lowest):
#   15 rollback         new-sha is ancestor of old-sha
#   12 archived         --archived flag set
#   16 renamed          --renamed flag set
#   11 license          diff touches a path containing LICENSE
#   10 security         security-relevant regex hits in diff body
#   13 batched          non-empty diff with no security signal
#    0 no-op            empty / whitespace-only diff
#
# Security regex set (from plan §Phase 1.3 — additions only, hence ^\+):
#   ^\+.*\|.*\|.*$         added markdown table row
#   ^\+.*\[CRITICAL\]      criticality marker
#   ^\+.*\bMUST\b          RFC-2119 normative
#   ^\+.*Art\. [0-9]+      GDPR/CCPA article reference
#   ^\+.*§\s*[0-9]+        section symbol
#   ^\+\+\+ b/.*/layers/   new file under references/layers/
#
# Stdout contract (review #3521 — multi-category fix):
#   For every category that matches, one line is emitted on stdout in the
#   form `category=<name>` where <name> ∈ {rollback,archived,renamed,license,
#   security,batched,no-op}. The workflow consumer accumulates labels from
#   the full set, while routing (auto-PR vs issue) uses the exit code.
#   The single-exit-code contract previously under-labeled co-occurring
#   security + license drift.
#
# On unexpected argument shape the script writes to stderr and exits 2.

set -euo pipefail

ARCHIVED=0
RENAMED=0
OLD_SHA=""
NEW_SHA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archived) ARCHIVED=1; shift ;;
    --renamed)  RENAMED=1;  shift ;;
    --) shift; break ;;
    -*)
      echo "vendor-drift-classify: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$OLD_SHA" ]]; then
        OLD_SHA="$1"
      elif [[ -z "$NEW_SHA" ]]; then
        NEW_SHA="$1"
      else
        echo "vendor-drift-classify: unexpected positional arg: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

DIFF=$(cat)

# Accumulate every matching category to stdout. Exit code retains the
# first-match-wins priority for routing; stdout is used by the consumer for
# label accumulation (review #3521 multi-category contract).
exit_code=0

# 1. Rollback: new-sha is an ancestor of old-sha (and not the same commit).
if [[ -n "$OLD_SHA" && -n "$NEW_SHA" && "$OLD_SHA" != "$NEW_SHA" ]]; then
  if git merge-base --is-ancestor "$NEW_SHA" "$OLD_SHA" 2>/dev/null; then
    echo "category=rollback"
    exit 15
  fi
fi

# 2. Upstream-disambiguation flags (signaled by the workflow's gh-api step).
if (( ARCHIVED )); then
  echo "category=archived"
  exit_code=12
fi
if (( RENAMED )); then
  echo "category=renamed"
  (( exit_code == 0 )) && exit_code=16
fi

# 3. LICENSE diff (basename anchored, optionally with extension). The
# anchor prevents false-positives on paths like docs/LICENSE-DISCUSSION.md
# or src/license_parser.py where `LICENSE` is a substring but the file is
# not a license document.
if printf '%s\n' "$DIFF" | grep -qE '^(\+\+\+|---) [ab]/(.*/)?LICENSE(\.[^/]+)?$'; then
  echo "category=license"
  (( exit_code == 0 )) && exit_code=11
fi

# 4. Security-relevant regex set.
if printf '%s\n' "$DIFF" | grep -qE '^\+.*\|.*\|.*$|^\+.*\[CRITICAL\]|^\+.*\bMUST\b|^\+.*Art\. [0-9]+|^\+.*§[[:space:]]*[0-9]+|^\+\+\+ b/.*/layers/'; then
  echo "category=security"
  (( exit_code == 0 )) && exit_code=10
fi

# If any category fired (archived/renamed/license/security), exit with the
# highest-priority code we accumulated.
if (( exit_code != 0 )); then
  exit "$exit_code"
fi

# 5. Batched (non-empty diff, no security signal).
if [[ -n "$(printf '%s' "$DIFF" | tr -d '[:space:]')" ]]; then
  echo "category=batched"
  exit 13
fi

# 6. No-op.
echo "category=no-op"
exit 0
