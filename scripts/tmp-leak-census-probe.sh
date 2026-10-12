#!/usr/bin/env bash
# tmp-leak-census-probe.sh — ratchet probe for the trap-ownership census
# (#10017).
#
# Exists as a file because the preflight Check-10 command parser rejects
# shell metacharacters in an inlined comparison — the probe IS the inline
# check, wrapped so the parser sees a plain script call.
#
# Contract: prints `ratchet-ok` iff the class-b census count is at or below
# `scripts/lint-trap-tempfile-ownership.highwater`. Also cross-checks that
# `--census-files` emits exactly that many `shell`-class member lines (the
# listing and the count derive from the same census_all pass — a divergence
# would mean a forked predicate).
#
# Exit: 0 ratchet-ok · 1 over-highwater, diverged listing, or linter error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/lint-trap-tempfile-ownership.py"
HW_FILE="$SCRIPT_DIR/lint-trap-tempfile-ownership.highwater"

count="$(python3 "$LINT" --census)" || {
  echo "tmp-leak-census-probe: FAIL — --census exited non-zero" >&2; exit 1; }
highwater="$(awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }' "$HW_FILE")"
[[ -n "$highwater" ]] || {
  echo "tmp-leak-census-probe: FAIL — no integer on a highwater line in $HW_FILE" >&2; exit 1; }

listed="$(python3 "$LINT" --census-files)" || {
  echo "tmp-leak-census-probe: FAIL — --census-files exited non-zero" >&2; exit 1; }
shell_lines="$(printf '%s\n' "$listed" | grep -c $'^shell\t' || true)"

if [[ "$shell_lines" != "$count" ]]; then
  echo "tmp-leak-census-probe: FAIL — --census=$count but --census-files emitted $shell_lines shell lines" >&2
  exit 1
fi
if (( count <= highwater )); then
  echo "ratchet-ok census=$count highwater=$highwater"
  exit 0
fi
echo "tmp-leak-census-probe: FAIL — census $count exceeds highwater $highwater" >&2
exit 1
