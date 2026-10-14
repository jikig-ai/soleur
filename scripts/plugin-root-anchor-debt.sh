#!/usr/bin/env bash
# plugin-root-anchor-debt.sh — the #7453 discoverability probe (ADR-179 A18).
#
# Prints `anchor-debt-files=<n>`: tracked payload markdown files that still resolve a
# plugin path through any modifier on the token or a git-root code root. Expected 0.
#
# This is a SIGNAL, not the gate. The gate is Guards 1/2 in
# apps/web-platform/test/plugin-root-anchoring.test.ts (required CI context), whose
# predicates are wider; the needles below are literal substrings of the forms those guards
# reject, so a nonzero here is almost always a red guard there (prose quoting e.g.
# "CLAUDE_PLUGIN_ROOT: unbound variable" can trip a needle without tripping a guard).
#
# Exit: 0 when n is 0; 1 when n > 0; 2 when git grep itself failed (not a result).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(git -C "$ROOT" grep -l -F \
  -e 'CLAUDE_PLUGIN_ROOT:' -e 'CLAUDE_PLUGIN_ROOT-' -e '{CLAUDE_PLUGIN_ROOT=' \
  -e '{CLAUDE_PLUGIN_ROOT?' -e '{CLAUDE_PLUGIN_ROOT+' -e '{CLAUDE_PLUGIN_ROOT%' \
  -e '{CLAUDE_PLUGIN_ROOT#' -e 'show-toplevel)/plugins/soleur/' \
  -- ':(glob)plugins/soleur/**/*.md' 2>/dev/null)"
rc=$?
case "$rc" in
  0) n=$(printf '%s\n' "$out" | grep -c .) ;;
  1) n=0 ;;
  *) echo "anchor-debt-files=ERROR rc=$rc"; exit 2 ;;
esac
echo "anchor-debt-files=$n"
[[ "$n" -eq 0 ]]
