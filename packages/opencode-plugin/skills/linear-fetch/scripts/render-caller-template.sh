#!/usr/bin/env bash
# Substitute a placeholder in a template (stdin) with a value (arg 1).
# Used by persist-safe-integration.test.sh to simulate the runtime
# substitution that one-shot Step 0a and brainstorm Phase 0.4 perform
# when threading persist_safe_summary into downstream prompts.
#
# Usage:
#   echo "$template" | bash render-caller-template.sh "$summary"
#
# The placeholder is the literal string __PERSIST_SAFE_SUMMARY__ — chosen
# to be visually distinct from $ARGUMENTS (one-shot template) and {desc}
# (brainstorm template) so test fixtures can mirror either real template
# by writing the placeholder in the right spot.
#
# Implementation note: awk is used (not sed) so the substitution value
# can contain arbitrary characters including /, &, \, and newlines
# without escaping. The placeholder itself is 24 chars of fixed-shape
# alphanumeric + underscore — no regex metacharacters.

set -eu

VALUE="${1:?usage: render-caller-template.sh <value>}"
TEMPLATE=$(cat -)
PLACEHOLDER='__PERSIST_SAFE_SUMMARY__'

# Use awk for arbitrary-content substitution — no sed escaping needed.
printf '%s' "$TEMPLATE" | awk -v val="$VALUE" -v ph="$PLACEHOLDER" '
{
  line = $0
  while ((p = index(line, ph)) > 0) {
    printf "%s%s", substr(line, 1, p-1), val
    line = substr(line, p + length(ph))
  }
  print line
}
'
