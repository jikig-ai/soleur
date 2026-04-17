#!/usr/bin/env bash

# Tests for cleanup-scope-outs helper script (group-by-area.sh).
# Run: bash plugins/soleur/test/cleanup-scope-outs.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/cleanup-scope-outs"

echo "=== cleanup-scope-outs group-by-area ==="
echo ""

assert_file_exists "$HELPER" "helper script exists"

# ---------------------------------------------------------------------------
# T6 — clustered: 3 issues share apps/web-platform top-level directory
# ---------------------------------------------------------------------------
echo ""
echo "--- T6: clustered cluster selection ---"
out=$(bash "$HELPER" --fixture "$FIXTURE_DIR/clustered.json" --top-n 1 --min-cluster-size 3)
assert_contains "$out" "apps/web-platform" "clustered: top cluster is apps/web-platform"
assert_contains "$out" "2474" "clustered: cluster lists issue #2474"
assert_contains "$out" "2473" "clustered: cluster lists issue #2473"
assert_contains "$out" "2472" "clustered: cluster lists issue #2472"

# Helper must output ALL clusters, not just the top one
out_all=$(bash "$HELPER" --fixture "$FIXTURE_DIR/clustered.json" --min-cluster-size 1)
assert_contains "$out_all" "plugins/soleur" "clustered: also reports plugins/soleur cluster"

# ---------------------------------------------------------------------------
# T7 — dispersed: no cluster meets min-cluster-size=3 → exit 0 with clear message
# ---------------------------------------------------------------------------
echo ""
echo "--- T7: dispersed exits cleanly when no cluster ---"
set +e
out=$(bash "$HELPER" --fixture "$FIXTURE_DIR/dispersed.json" --top-n 1 --min-cluster-size 3)
rc=$?
set -e
assert_eq "0" "$rc" "dispersed: exits 0"
assert_contains "$out" "No cleanup cluster available" "dispersed: prints no-cluster message"

# ---------------------------------------------------------------------------
# Empty: no issues at all → exit 0, no-cluster message
# ---------------------------------------------------------------------------
echo ""
echo "--- Empty: handles zero issues ---"
set +e
out=$(bash "$HELPER" --fixture "$FIXTURE_DIR/empty.json" --top-n 1 --min-cluster-size 3)
rc=$?
set -e
assert_eq "0" "$rc" "empty: exits 0"
assert_contains "$out" "No cleanup cluster available" "empty: prints no-cluster message"

# ---------------------------------------------------------------------------
# Contract: JSON output lists clusters sorted by count desc
# ---------------------------------------------------------------------------
echo ""
echo "--- Contract: JSON cluster output is sorted ---"
json_out=$(bash "$HELPER" --fixture "$FIXTURE_DIR/clustered.json" --min-cluster-size 1 --format json)
first_area=$(echo "$json_out" | jq -r '.[0].area')
assert_eq "apps/web-platform" "$first_area" "json: first cluster (largest) is apps/web-platform"
first_count=$(echo "$json_out" | jq -r '.[0].count')
assert_eq "3" "$first_count" "json: largest cluster has 3 issues"

# ---------------------------------------------------------------------------
# T8 — shorthand refs: qualified paths must outrank bare filename shorthand
# when picking the per-issue "top path" for area derivation.
# Regression: before the fix, `chat-input.tsx` (4x shorthand) beat
# `apps/web-platform/components/chat/chat-input.tsx` (1x qualified),
# producing 3 singleton clusters keyed by bare filename.
# ---------------------------------------------------------------------------
echo ""
echo "--- T8: qualified paths outrank shorthand filename refs ---"
out=$(bash "$HELPER" --fixture "$FIXTURE_DIR/shorthand-refs.json" --top-n 1 --min-cluster-size 3)
assert_contains "$out" "apps/web-platform" "shorthand: cluster area is apps/web-platform, not bare filename"
assert_contains "$out" "3001" "shorthand: cluster lists issue #3001"
assert_contains "$out" "3002" "shorthand: cluster lists issue #3002"
assert_contains "$out" "3003" "shorthand: cluster lists issue #3003"

json_out=$(bash "$HELPER" --fixture "$FIXTURE_DIR/shorthand-refs.json" --min-cluster-size 1 --format json)
first_area=$(echo "$json_out" | jq -r '.[0].area')
assert_eq "apps/web-platform" "$first_area" "shorthand: json first cluster area is apps/web-platform"
first_count=$(echo "$json_out" | jq -r '.[0].count')
assert_eq "3" "$first_count" "shorthand: all 3 issues fold into one cluster"

# ---------------------------------------------------------------------------
# T9 — mixed depth: when an issue body has both a deep qualified path
# (apps/web-platform/server/rate-limiter.ts) and a shallow qualified path
# (server/ws-handler.ts), area must come from the deepest path. Authors
# typically give one fully-qualified citation and shorthand the rest.
# ---------------------------------------------------------------------------
echo ""
echo "--- T9: deepest qualified path wins area ---"
json_out=$(bash "$HELPER" --fixture "$FIXTURE_DIR/mixed-depth.json" --min-cluster-size 1 --format json)
first_area=$(echo "$json_out" | jq -r '.[0].area')
assert_eq "apps/web-platform" "$first_area" "mixed-depth: deepest qualified path establishes area"
first_count=$(echo "$json_out" | jq -r '.[0].count')
assert_eq "3" "$first_count" "mixed-depth: all 3 issues fold into apps/web-platform"

print_results
