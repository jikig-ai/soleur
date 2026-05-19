#!/usr/bin/env bash

# Tests for .github/workflows/scheduled-content-vendor-drift.yml.
# Run: bash plugins/soleur/test/vendor-drift-workflow.test.sh
#
# The drift workflow runs weekly, reads NOTICE frontmatter, fetches upstream
# blob SHAs via `gh api`, classifies any drift, opens a re-vendor PR via the
# bot-pr-with-synthetic-checks composite, and files an issue on cron failure.
#
# This integration test does NOT execute the workflow against real upstream
# (no GH credentials in test env). Instead it asserts structural invariants
# that catch the failure modes the plan calls out, plus an end-to-end
# classifier+parser sanity exercise against the synthetic-diff fixtures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
WORKFLOW="$REPO_ROOT/.github/workflows/scheduled-content-vendor-drift.yml"
PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
CLASSIFY="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh"
FIX="$SCRIPT_DIR/fixtures/vendor-drift"

echo "=== vendor-drift-workflow tests ==="
echo ""

assert_file_exists "$WORKFLOW" "scheduled-content-vendor-drift.yml exists"

WF_CONTENT=$(cat "$WORKFLOW")

# --- Schedule + dispatch ---
echo "TS1: cron schedule '17 11 * * MON' (off-peak / off-cluster, AC4)"
if grep -qE "cron:[[:space:]]*['\"]17 11 \\* \\* MON['\"]" "$WORKFLOW"; then
  echo "  PASS: cron is '17 11 * * MON'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected cron '17 11 * * MON' (off-peak per plan §2.1)"
  FAIL=$((FAIL + 1))
fi
assert_contains "$WF_CONTENT" "workflow_dispatch" "workflow_dispatch trigger present"
echo ""

# --- Concurrency ---
echo "TS2: concurrency group set (cancel-in-progress: false)"
assert_contains "$WF_CONTENT" "concurrency:" "concurrency block present"
assert_contains "$WF_CONTENT" "cancel-in-progress: false" "cancel-in-progress is false"
echo ""

# --- Permissions ---
echo "TS3: permissions block has contents/issues/pull-requests = write"
assert_contains "$WF_CONTENT" "contents: write" "contents: write"
assert_contains "$WF_CONTENT" "issues: write" "issues: write"
assert_contains "$WF_CONTENT" "pull-requests: write" "pull-requests: write"
echo ""

# --- actions/checkout pin (40-char SHA + version comment) ---
echo "TS4: actions/checkout pinned to a 40-char SHA"
if grep -qE "uses: actions/checkout@[0-9a-f]{40}" "$WORKFLOW"; then
  echo "  PASS: actions/checkout pinned to 40-char SHA"
  PASS=$((PASS + 1))
else
  echo "  FAIL: actions/checkout not pinned to 40-char SHA (per AGENTS.md sha-pinning learning)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- 6-label ensure step ---
echo "TS5: 'Ensure labels exist' step creates 6 labels"
for label in compliance/critical vendor/pin-drift vendor/license-changed vendor/upstream-archived vendor/upstream-rollback vendor/cron-failure; do
  assert_contains "$WF_CONTENT" "$label" "label '$label' present in workflow"
done
echo ""

# --- bot-pr-with-synthetic-checks composite invoked with all 7 inputs ---
echo "TS6: bot-pr-with-synthetic-checks composite invoked"
assert_contains "$WF_CONTENT" "bot-pr-with-synthetic-checks" "composite invoked"
for input in add-paths branch-prefix commit-message pr-title-prefix pr-body change-summary gh-token; do
  assert_contains "$WF_CONTENT" "$input:" "composite input '$input' specified"
done
echo ""

# --- Classifier and parser script references ---
echo "TS7: workflow references classifier + parser scripts"
assert_contains "$WF_CONTENT" "vendor-drift-classify.sh" "classifier referenced"
assert_contains "$WF_CONTENT" "notice-frontmatter.sh" "parser referenced"
echo ""

# --- if: failure() cron-failure handler ---
echo "TS8: 'if: failure()' step opens vendor/cron-failure issue (FR3 step 9)"
if grep -qE "if:[[:space:]]*failure\(\)" "$WORKFLOW"; then
  echo "  PASS: failure() handler present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing 'if: failure()' step (cron-failure tracking)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- 3-way merge with --diff3 ---
echo "TS9: inline 3-way merge uses 'git merge-file --diff3'"
assert_contains "$WF_CONTENT" "git merge-file --diff3" "merge-file --diff3 invoked (TR3)"
assert_contains "$WF_CONTENT" "<<<<<<<" "conflict-marker grep gate present"
echo ""

# --- CAP_PER_RUN ---
echo "TS10: CAP_PER_RUN cap on issues filed per run"
if grep -qE "CAP_PER_RUN:[[:space:]]*['\"]?3['\"]?" "$WORKFLOW"; then
  echo "  PASS: CAP_PER_RUN: 3 set"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing CAP_PER_RUN: 3 (issue-storm guard)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- End-to-end exercise: feed each fixture diff through classifier and assert
# the workflow's label-mapping table has an entry for the resulting exit code.
echo "TS11: every fixture diff routes to a documented label set"
declare -A EXIT_TO_LABEL=(
  [10]="vendor/pin-drift"
  [11]="vendor/license-changed"
  [13]="vendor/pin-drift"
  [15]="vendor/upstream-rollback"
)
for fx in upstream-fields-art9-add.diff:10 upstream-prose-typo.diff:13 upstream-license-edit.diff:11; do
  fixture="${fx%%:*}"
  expected="${fx##*:}"
  set +e
  bash "$CLASSIFY" < "$FIX/$fixture" >/dev/null 2>&1
  RC=$?
  set -e
  if [[ "$RC" == "$expected" ]]; then
    label="${EXIT_TO_LABEL[$RC]}"
    if grep -qF "$label" "$WORKFLOW"; then
      echo "  PASS: $fixture → exit $RC → label '$label' is in workflow"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: $fixture → exit $RC but workflow missing label '$label'"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: $fixture classifier exit $RC, expected $expected"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

# --- NOTICE bump step references the parser-emitted blob-sha fields ---
echo "TS12: NOTICE-bump step updates last-verified and local/upstream blob SHAs"
assert_contains "$WF_CONTENT" "last-verified" "workflow bumps last-verified"
assert_contains "$WF_CONTENT" "blob-sha" "workflow bumps blob-sha entries"
echo ""

print_results
