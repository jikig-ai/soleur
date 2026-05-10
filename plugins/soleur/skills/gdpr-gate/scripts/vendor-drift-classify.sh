#!/usr/bin/env bash
# vendor-drift-classify.sh — severity classifier for an upstream content diff.
#
# Reads a unified diff on stdin. Optional positional args are the SHA pair
# `<old-sha> <new-sha>` (used for rollback detection). Optional flags:
#   --archived   exit 12 (upstream archived; signaled by drift workflow)
#   --renamed    exit 16 (upstream renamed; signaled by drift workflow)
#
# Priority chain (first match wins):
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
# Outputs nothing on stdout in normal use; the exit code IS the result. On
# unexpected argument shape the script writes to stderr and exits 2.

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

# 1. Rollback: new-sha is an ancestor of old-sha (and not the same commit).
if [[ -n "$OLD_SHA" && -n "$NEW_SHA" && "$OLD_SHA" != "$NEW_SHA" ]]; then
  if git merge-base --is-ancestor "$NEW_SHA" "$OLD_SHA" 2>/dev/null; then
    exit 15
  fi
fi

# 2. Upstream-disambiguation flags (signaled by the workflow's gh-api step).
(( ARCHIVED )) && exit 12
(( RENAMED ))  && exit 16

# 3. LICENSE diff (any path containing LICENSE in the file headers).
if printf '%s\n' "$DIFF" | grep -qE '^(\+\+\+|---) [ab]/.*LICENSE'; then
  exit 11
fi

# 4. Security-relevant regex set.
if printf '%s\n' "$DIFF" | grep -qE '^\+.*\|.*\|.*$'; then exit 10; fi
if printf '%s\n' "$DIFF" | grep -qE '^\+.*\[CRITICAL\]'; then exit 10; fi
if printf '%s\n' "$DIFF" | grep -qE '^\+.*\bMUST\b'; then exit 10; fi
if printf '%s\n' "$DIFF" | grep -qE '^\+.*Art\. [0-9]+'; then exit 10; fi
if printf '%s\n' "$DIFF" | grep -qE '^\+.*§[[:space:]]*[0-9]+'; then exit 10; fi
if printf '%s\n' "$DIFF" | grep -qE '^\+\+\+ b/.*/layers/'; then exit 10; fi

# 5. Batched (non-empty diff, no security signal).
if [[ -n "$(printf '%s' "$DIFF" | tr -d '[:space:]')" ]]; then
  exit 13
fi

# 6. No-op.
exit 0
