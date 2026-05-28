#!/usr/bin/env bash
# Meta-test: every PreToolUse hook that emits a `permissionDecision` MUST also
# emit `hookEventName: "PreToolUse"` in the same output object — otherwise
# Claude Code silently ignores the decision and the tool call proceeds (the
# deny/ask never takes effect).
#
# This guards the bug class fixed in the hook-deny-enforcement PR: 9 hooks
# (including git-commit-secret-scan, guardrails, no-memory-write) shipped deny
# JSON without hookEventName and were silently non-enforcing. The per-file
# count check below makes that class un-shippable going forward — any new or
# edited hook that adds a permissionDecision without the paired hookEventName
# fails this test.
#
# Source: official Claude Code PreToolUse hook contract — hookEventName is a
# required field in hookSpecificOutput for permissionDecision to be honored.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0

for h in "$HOOK_DIR"/*.sh; do
  base="$(basename "$h")"
  # Skip test scripts themselves.
  [[ "$base" == *.test.sh ]] && continue

  # Count non-comment lines that emit a permissionDecision, and lines that
  # emit hookEventName. Comment lines (leading # after optional whitespace)
  # are excluded so the doc-comment describing the shape is not counted.
  # Match the decision FIELD only — `permissionDecision":` / `permissionDecision:`
  # — never `permissionDecisionReason` (which contains "permissionDecision" as a
  # substring and would double-count).
  pd=$(grep -vE '^[[:space:]]*#' "$h" | grep -cE 'permissionDecision"?[[:space:]]*:' || true)
  hen=$(grep -vE '^[[:space:]]*#' "$h" | grep -c 'hookEventName' || true)

  # Per-file count check (count(hookEventName) >= count(permissionDecision)),
  # not per-emission pairing. This catches the realistic regression — a new
  # decision block added without hookEventName bumps `pd` without `hen` and
  # fails. It does NOT catch a contrived case of two hookEventName in one block
  # plus zero in a sibling; that is not reachable today (every block has exactly
  # one) and would require an AST-level parse to detect.
  if [[ "$pd" -gt 0 && "$hen" -lt "$pd" ]]; then
    echo "FAIL: $base emits $pd permissionDecision(s) but only $hen hookEventName(s)."
    echo "      Every permissionDecision output object must include hookEventName: \"PreToolUse\"."
    fail=1
  fi
done

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: all PreToolUse hooks pair permissionDecision with hookEventName."
fi

exit "$fail"
