#!/usr/bin/env bash

# Tests for plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh.
# Run: bash plugins/soleur/test/vendor-drift-classify.test.sh
#
# The classifier reads a unified diff on stdin and (optionally) takes a SHA
# pair (`<old-sha> <new-sha>`) for rollback detection plus `--archived` /
# `--renamed` flags for the upstream-disambiguation cases routed in by the
# drift workflow's `gh api repos/<o>/<r>` step.
#
# Exit codes (priority order — first match wins):
#   11 LICENSE diff           (path contains LICENSE)
#   15 upstream rollback      (new-sha is ancestor of old-sha)
#   12 upstream archived      (--archived flag)
#   16 upstream renamed       (--renamed flag)
#   10 security-relevant      (regex hit on diff body)
#   13 batched / prose only   (non-empty diff, no security signal)
#    0 no-op                  (empty / whitespace-only diff)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
CLASSIFY="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh"
FIX="$SCRIPT_DIR/fixtures/vendor-drift"

echo "=== vendor-drift-classify tests ==="
echo ""

assert_file_exists "$CLASSIFY" "vendor-drift-classify.sh exists"
assert_file_exists "$FIX/upstream-fields-art9-add.diff" "art9-add fixture exists"
assert_file_exists "$FIX/upstream-prose-typo.diff" "prose-typo fixture exists"
assert_file_exists "$FIX/upstream-rollback.diff" "rollback fixture exists"
assert_file_exists "$FIX/upstream-license-edit.diff" "license-edit fixture exists"
assert_file_exists "$FIX/upstream-empty.diff" "empty fixture exists"

run_classify() {
  set +e
  bash "$CLASSIFY" "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

# --- TS1: empty diff → exit 0 ---
echo "TS1: empty diff → exit 0 (no-op)"
RC=$(run_classify < "$FIX/upstream-empty.diff")
assert_eq "0" "$RC" "exit 0 on empty diff"
echo ""

# --- TS2: whitespace-only diff → exit 0 ---
echo "TS2: whitespace-only diff → exit 0 (no-op)"
RC=$( (printf '   \n\n\t\n') | bash "$CLASSIFY" >/dev/null 2>&1; echo $? || true )
assert_eq "0" "$RC" "exit 0 on whitespace-only diff"
echo ""

# --- TS3: art9-add → exit 10 (security-relevant) ---
echo "TS3: art9-add → exit 10 (security-relevant: Art. 9 row added)"
RC=$(run_classify < "$FIX/upstream-fields-art9-add.diff")
assert_eq "10" "$RC" "exit 10 on Art. 9 row addition"
echo ""

# --- TS4: prose-typo → exit 13 (batched) ---
echo "TS4: prose-typo → exit 13 (no security regex match, but content changed)"
RC=$(run_classify < "$FIX/upstream-prose-typo.diff")
assert_eq "13" "$RC" "exit 13 on prose-only edit"
echo ""

# --- TS5: LICENSE edit → exit 11 ---
echo "TS5: LICENSE edit → exit 11 (license-changed)"
RC=$(run_classify < "$FIX/upstream-license-edit.diff")
assert_eq "11" "$RC" "exit 11 on LICENSE diff"
echo ""

# --- TS6: --archived flag → exit 12 ---
echo "TS6: --archived flag → exit 12"
RC=$( (printf '') | bash "$CLASSIFY" --archived >/dev/null 2>&1; echo $? || true )
assert_eq "12" "$RC" "exit 12 with --archived (overrides empty-diff exit 0)"
echo ""

# --- TS7: --renamed flag → exit 16 ---
echo "TS7: --renamed flag → exit 16"
RC=$( (printf '') | bash "$CLASSIFY" --renamed >/dev/null 2>&1; echo $? || true )
assert_eq "16" "$RC" "exit 16 with --renamed"
echo ""

# --- TS8: rollback (new SHA is ancestor of old SHA) → exit 15 ---
# Use real local commits. HEAD~1 is ancestor of HEAD by definition. Pass
# `<old-sha=HEAD> <new-sha=HEAD~1>` to simulate the upstream rolling back.
echo "TS8: rollback SHA pair → exit 15"
OLD_SHA=$(git rev-parse HEAD)
NEW_SHA=$(git rev-parse HEAD~1)
RC=$(run_classify "$OLD_SHA" "$NEW_SHA" < "$FIX/upstream-rollback.diff")
assert_eq "15" "$RC" "exit 15 when new-sha is ancestor of old-sha (rollback)"
echo ""

# --- TS9: rollback flag takes precedence over security-regex content ---
# Even if the diff body contains an Art. 9 addition, a rollback SHA pair
# should classify as 15. Order matters; tests the priority chain.
echo "TS9: rollback precedence — wins over security-regex content"
RC=$(run_classify "$OLD_SHA" "$NEW_SHA" < "$FIX/upstream-fields-art9-add.diff")
assert_eq "15" "$RC" "exit 15 even when diff body would otherwise be exit 10"
echo ""

# --- TS10: archived flag wins over diff content ---
echo "TS10: --archived precedence — wins over security-regex content"
RC=$( bash "$CLASSIFY" --archived < "$FIX/upstream-fields-art9-add.diff" >/dev/null 2>&1; echo $? || true )
assert_eq "12" "$RC" "exit 12 with --archived even when diff body is security-relevant"
echo ""

# --- TS11: forward-fast (new is descendant, NOT ancestor) → falls through ---
# Pass `<old-sha=HEAD~1> <new-sha=HEAD>` — new is descendant of old, NOT a
# rollback. The classifier must fall through to diff content, not exit 15.
echo "TS11: forward-fast (new is descendant) → falls through to diff classifier"
RC=$(run_classify "$NEW_SHA" "$OLD_SHA" < "$FIX/upstream-fields-art9-add.diff")
assert_eq "10" "$RC" "exit 10 (not 15) when new commit is descendant of pinned"
echo ""

print_results
