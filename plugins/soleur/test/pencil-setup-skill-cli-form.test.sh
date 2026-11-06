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

# The re-registration snippet must capture the old --pencil-binary= flag ONLY inside the
# user-scope branch (the same gate as the Node probe): a flag from a project-scoped .mcp.json
# entry must never be appended to the trusted `-s user` registration. Ordering-aware: comments
# are stripped and the extraction line is anchored, so the bare variable name elsewhere (the
# initialiser, the `claude mcp add` line) cannot satisfy it.
flag_state=$(awk '
  /^[[:space:]]*#/ { next }
  { sub(/[[:space:]]+#.*$/, "") }
  /^if \[\[ "\$existing_mode" == "headless_cli" \]\]; then/ { insnip=1; inuser=0; next }
  insnip && /if \[\[ "\$scope" == "Scope: User" \]\]; then/ { inuser=1; next }
  insnip && inuser && /^  else[[:space:]]*$/ { inuser=0; next }
  insnip && /^fi[[:space:]]*$/ { insnip=0 }
  insnip && /^[[:space:]]+pencil_binary_flag=\$\(.*grep -oE -- .--pencil-binary=\[\^ \]\+./ { print (inuser ? "user-branch" : "outside-user-branch") }
' "$SKILL" | paste -sd, -)
assert_eq "user-branch" "$flag_state" "pencil_binary_flag is extracted exactly once, inside the Scope: User branch"

print_results 5
