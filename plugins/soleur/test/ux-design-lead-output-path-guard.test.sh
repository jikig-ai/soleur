#!/usr/bin/env bash

# T2.5 — Regression guard: the ux-design-lead agent must not reference the
# deprecated `knowledge-base/design/` path (removed in #566) and must
# reference the canonical `knowledge-base/product/design/` path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AGENT="$REPO_ROOT/plugins/soleur/agents/product/design/ux-design-lead.md"

echo "=== ux-design-lead output-path guard ==="
echo ""

assert_file_exists "$AGENT" "ux-design-lead agent exists"

# The deprecated `knowledge-base/design/` path must not appear. Grep with
# a word boundary after `design/` so we don't match `knowledge-base/product/design/`.
set +e
deprecated=$(grep -E "knowledge-base/design/" "$AGENT" 2>&1)
rc=$?
set -e
assert_eq "1" "$rc" "no reference to deprecated knowledge-base/design/"
if [[ "$rc" == "0" ]]; then
  echo "  Found lines:"
  echo "$deprecated" | sed 's/^/    /'
fi

# Canonical path must appear.
set +e
grep -q "knowledge-base/product/design/" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "references canonical knowledge-base/product/design/"

# Post-save size-verification instruction must appear (T3.5).
set +e
grep -qiE "size > 0|non-empty|stat.*%s|file.*bytes" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "agent verifies saved .pen size before announcing completion"

# Explicit instruction NOT to fabricate a stub/dropped narrative (T3.5).
set +e
grep -qiE "do not fabricate|not.*stub|read.*actual.*error" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "agent told to read actual error, not fabricate stub narrative"

print_results
