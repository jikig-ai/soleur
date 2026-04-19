#!/usr/bin/env bash

# T2.6 — The pencil-setup skill must not instruct users to run the broken
# `claude mcp list -s user` form. The `-s` flag was dropped from `list`
# in recent Claude Code CLI versions; plain `claude mcp list` is correct.
# Rule: cq-docs-cli-verification.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/soleur/skills/pencil-setup/SKILL.md"

echo "=== pencil-setup SKILL.md CLI form guard ==="
echo ""

assert_file_exists "$SKILL" "pencil-setup SKILL.md exists"

set +e
broken=$(grep -nF "claude mcp list -s user" "$SKILL")
rc=$?
set -e
assert_eq "1" "$rc" "SKILL.md does not reference broken 'claude mcp list -s user'"
if [[ "$rc" == "0" ]]; then
  echo "  Found lines:"
  echo "$broken" | sed 's/^/    /'
fi

# Canonical form must appear.
set +e
grep -q "claude mcp list" "$SKILL"
rc=$?
set -e
assert_eq "0" "$rc" "SKILL.md uses canonical 'claude mcp list'"

# Verification annotation per cq-docs-cli-verification.
set +e
grep -q "verified:" "$SKILL"
rc=$?
set -e
assert_eq "0" "$rc" "SKILL.md includes a <!-- verified: --> annotation"

print_results
