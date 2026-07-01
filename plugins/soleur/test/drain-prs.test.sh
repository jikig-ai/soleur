#!/usr/bin/env bash

# Tests for drain-prs helper script (triage-prs.sh).
# Run: bash plugins/soleur/test/drain-prs.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/plugins/soleur/skills/drain-prs/scripts/triage-prs.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/drain-prs"

echo "=== drain-prs triage-prs ==="
echo ""

assert_file_exists "$HELPER" "helper script exists"

# Helper: tier of a PR number in the --format json output.
tier_of() { # $1=json $2=number
  jq -r --argjson n "$2" 'to_entries[] | select(.value[]?.number == $n) | .key' <<<"$1"
}

# ---------------------------------------------------------------------------
# T1 — every tier gets its one synthetic PR (one PR per tier fixture)
# ---------------------------------------------------------------------------
echo ""
echo "--- T1: per-tier classification ---"
json=$(bash "$HELPER" --fixture "$FIXTURE_DIR/all-tiers.json" --format json)

assert_eq "ready-green"                "$(tier_of "$json" 9001)" "9001 → ready-green"
assert_eq "needs-lockfile-fix"         "$(tier_of "$json" 9002)" "9002 → needs-lockfile-fix (deps + failing check)"
assert_eq "needs-conflict-resolution"  "$(tier_of "$json" 9003)" "9003 → needs-conflict-resolution (CONFLICTING)"
assert_eq "needs-review"               "$(tier_of "$json" 9004)" "9004 → needs-review (bot-fix/review-required)"
assert_eq "drafts"                     "$(tier_of "$json" 9005)" "9005 → drafts (isDraft)"
assert_eq "broken"                     "$(tier_of "$json" 9006)" "9006 → broken (CONFLICTING + 3 failing)"

# ---------------------------------------------------------------------------
# T2 — JSON output shape: all six tier keys present, in stable order
# ---------------------------------------------------------------------------
echo ""
echo "--- T2: tier-grouped JSON output shape ---"
keys=$(jq -r 'keys_unsorted | join(",")' <<<"$json")
assert_eq "ready-green,needs-lockfile-fix,needs-conflict-resolution,needs-review,broken,drafts" \
  "$keys" "json keys present in stable order"

# ---------------------------------------------------------------------------
# T3 — drafts are isolated (never co-classified with a mergeable tier)
# ---------------------------------------------------------------------------
echo ""
echo "--- T3: drafts isolated ---"
draft_count=$(jq -r '.drafts | length' <<<"$json")
assert_eq "1" "$draft_count" "exactly one draft, kept out of mergeable tiers"

# ---------------------------------------------------------------------------
# T4 — empty PR list → all tiers empty, exit 0
# ---------------------------------------------------------------------------
echo ""
echo "--- T4: empty list ---"
set +e
empty_json=$(bash "$HELPER" --fixture "$FIXTURE_DIR/empty.json" --format json)
rc=$?
set -e
assert_eq "0" "$rc" "empty: exits 0"
assert_eq "0" "$(jq -r '[.[] | length] | add // 0' <<<"$empty_json")" "empty: zero PRs across all tiers"

# ---------------------------------------------------------------------------
# T5 — text format renders a per-tier header with counts
# ---------------------------------------------------------------------------
echo ""
echo "--- T5: text format ---"
text=$(bash "$HELPER" --fixture "$FIXTURE_DIR/all-tiers.json" --format text)
assert_contains "$text" "Open PRs: 6"          "text: reports total open count"
assert_contains "$text" "## ready-green (1)"   "text: ready-green header with count"
assert_contains "$text" "## drafts (1)"        "text: drafts header with count"
assert_contains "$text" "#9001"                "text: lists a PR number"

# ---------------------------------------------------------------------------
# T6 — missing fixture exits non-zero with a readable error
# ---------------------------------------------------------------------------
echo ""
echo "--- T6: missing fixture fails fast ---"
set +e
err=$(bash "$HELPER" --fixture "$FIXTURE_DIR/does-not-exist.json" 2>&1)
rc=$?
set -e
assert_eq "1" "$rc" "missing fixture: exits 1"
assert_contains "$err" "fixture not found" "missing fixture: prints readable error"

print_results
