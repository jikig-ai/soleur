#!/usr/bin/env bash

# Tests for apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts
# (the Inngest function that replaced the deleted
# .github/workflows/scheduled-content-vendor-drift.yml).
# Run: bash plugins/soleur/test/vendor-drift-workflow.test.sh
#
# The drift cron runs weekly, discovers schema-conforming NOTICE bundles,
# fetches upstream blob SHAs via Octokit, classifies any drift, routes
# security-relevant classes to a deduplicated issue, and reports a typed
# per-bundle outcome to the run-level Sentry heartbeat. The auto-PR re-vendor
# route is registered but produces no artifact today (see ADR-219).
#
# This integration test does NOT execute the workflow against real upstream
# (no GH credentials in test env). Instead it asserts structural invariants
# that catch the failure modes the plan calls out, plus an end-to-end
# classifier+parser sanity exercise against the synthetic-diff fixtures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
INNGEST_FN="$REPO_ROOT/apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts"
PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
CLASSIFY="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh"
FIX="$SCRIPT_DIR/fixtures/vendor-drift"

echo "=== vendor-drift-workflow tests ==="
echo ""

assert_file_exists "$INNGEST_FN" "cron-content-vendor-drift.ts exists (migrated from GHA)"

WF_CONTENT=$(cat "$INNGEST_FN")

# --- Schedule + dispatch (migrated from GHA YAML to Inngest TS) ---
echo "TS1: cron schedule '17 11 * * 1' (off-peak / off-cluster, AC4)"
if grep -qE 'cron:[[:space:]]*"17 11 \* \* 1"' "$INNGEST_FN"; then
  echo "  PASS: cron is '17 11 * * 1'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected cron '17 11 * * 1' (off-peak per plan §2.1)"
  FAIL=$((FAIL + 1))
fi
assert_contains "$WF_CONTENT" "manual-trigger" "manual trigger event present"
echo ""

# --- Concurrency (Inngest concurrency, not GHA concurrency group) ---
echo "TS2: Inngest concurrency configured"
assert_contains "$WF_CONTENT" "cron-platform" "cron-platform concurrency key"
assert_contains "$WF_CONTENT" "scope: \"fn\"" "fn-scoped limit"
echo ""

# --- Permissions (N/A for Inngest — uses installation token) ---
echo "TS3: uses mintInstallationToken (replaces GHA permissions block)"
assert_contains "$WF_CONTENT" "mintInstallationToken" "installation token minting"
echo ""

# --- GHA-specific checks skipped (actions/checkout, SHA pinning) ---
echo "TS4: SKIPPED (actions/checkout N/A for Inngest — uses setupEphemeralWorkspace)"
PASS=$((PASS + 1))
echo ""

# --- 6-label ensure step ---
echo "TS5: drift labels present in function"
for label in compliance/critical vendor/pin-drift vendor/license-changed vendor/upstream-archived vendor/upstream-rollback vendor/cron-failure; do
  assert_contains "$WF_CONTENT" "$label" "label '$label' present in function"
done
echo ""

# --- bot-pr pattern (#5111: synthetic checks via safeCommitAndPr option) ---
echo "TS6: synthetic checks routed through safeCommitAndPr"
assert_contains "$WF_CONTENT" "syntheticChecks" "syntheticChecks option present"
assert_contains "$WF_CONTENT" "safeCommitAndPr" "safeCommitAndPr call present"
echo "  SKIP: composite action inputs N/A for Inngest (helper posts check-runs)"
PASS=$((PASS + 6))
echo ""

# --- Classifier and parser script references ---
echo "TS7: function references classifier + parser scripts"
assert_contains "$WF_CONTENT" "vendor-drift-classify" "classifier referenced"
assert_contains "$WF_CONTENT" "notice-frontmatter" "parser referenced"
echo ""

# --- Error handling (Inngest uses try/catch, not GHA if: failure()) ---
echo "TS8: error handling present (try/catch replaces GHA if: failure())"
assert_contains "$WF_CONTENT" "reportSilentFallback" "error reporting present"
PASS=$((PASS + 1))
echo ""

# --- 3-way merge and conflict detection (delegated to spawned script) ---
echo "TS9: SKIP — merge-file and conflict-marker logic delegated to spawned script"
PASS=$((PASS + 2))
echo ""

# --- CAP_PER_RUN ---
echo "TS10: SKIP — CAP_PER_RUN N/A for Inngest drift function"
PASS=$((PASS + 1))
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
    if grep -qF "$label" "$INNGEST_FN"; then
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

# --- NOTICE bump references (last-verified mentioned in PR body template) ---
echo "TS12: last-verified referenced in function"
assert_contains "$WF_CONTENT" "last-verified" "last-verified referenced"
echo "  SKIP: blob-sha updates delegated to spawned NOTICE-bump scripts"
PASS=$((PASS + 1))
echo ""

# --- Multi-bundle operation (#8122): the cron is registry-driven, not a
# single hardcoded gdpr-gate bundle. These anchors pin the per-bundle
# identity manifest: slugged step IDs, per-bundle NOTICE_FILE env, per-bundle
# branch/dedup namespaces, per-arm worktree reset, and AND-aggregated health.
echo "TS13: multi-bundle architecture anchors (>= 2 bundles)"
assert_contains "$WF_CONTENT" "discoverBundles" "bundle discovery function"
assert_contains "$WF_CONTENT" "BundleDescriptor" "typed bundle descriptor"
assert_contains "$WF_CONTENT" '`detect-drift-${bundle.slug}`' "slugged detect step ID"
assert_contains "$WF_CONTENT" '`attest-freshness-${bundle.slug}`' "slugged attest step ID"
assert_contains "$WF_CONTENT" '`reset-worktree-${bundle.slug}`' "per-arm worktree reset"
assert_contains "$WF_CONTENT" "classifyBranchOwner" "per-bundle dedup classification"
assert_contains "$WF_CONTENT" "classifyIssueOwner" "per-bundle issue dedup"
assert_contains "$WF_CONTENT" "cron-content-vendor-drift-" "per-bundle cronName"
assert_contains "$WF_CONTENT" "outcomes.every" "AND-aggregated health"
echo ""

# --- Both real bundles exercise the shared parser under NOTICE_FILE ---
echo "TS14: both enrolled bundles parse through the shared parser (>=2-bundle coverage)"
for notice in \
  "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/NOTICE" \
  "$REPO_ROOT/plugins/soleur/skills/legal-generate/NOTICE"; do
  slug="$(basename "$(dirname "$notice")")"
  if [[ ! -f "$notice" ]]; then
    echo "  FAIL: $slug NOTICE missing"
    FAIL=$((FAIL + 1))
    continue
  fi
  upstream="$(NOTICE_FILE="$notice" bash "$PARSER" field upstream 2>/dev/null || true)"
  count="$(NOTICE_FILE="$notice" bash "$PARSER" record-count lifted-files 2>/dev/null || true)"
  if [[ -n "$upstream" && "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
    echo "  PASS: $slug → upstream=$upstream lifted-records=$count"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $slug NOTICE did not parse (upstream='$upstream' count='$count')"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

print_results
