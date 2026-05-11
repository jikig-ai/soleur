#!/usr/bin/env bash
# Local mirror of `.github/workflows/gdpr-gate-self-test.yml` (issue #3536).
#
# Runs `gdpr-gate.sh` against the deliberately-stale fixture NOTICE in
# `plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` and asserts:
#
#   Case A (no token): the operator-attested-mode banner fires + the
#                      standard 30d staleness banner + POSTURE_FAIL line.
#   Case B (stub gh):  the operator-attested-mode banner is SUPPRESSED
#                      (cron-run binding resolved via stubbed gh).
#   Case C:            the gate always exits 0 (advisory contract).
#
# Run: bash plugins/soleur/test/gdpr-gate-self-test.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
GATE="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/gdpr-gate-stale"
FIXTURE_NOTICE="$FIXTURE_DIR/NOTICE"
GH_STUB_DIR="$FIXTURE_DIR/gh-stub"

# Banner literal under test — load-bearing. Any change here must also move
# the printf in `gdpr-gate.sh` lines around the operator-attested-mode
# emit. Asserted in Case A; absence asserted in Case B.
BANNER_LITERAL='ℹ gdpr-gate: operator-attested mode (no GH_TOKEN available — cron-run timestamp unverified, falling back to NOTICE last-verified)'

echo "=== gdpr-gate self-test ==="
echo ""

assert_file_exists "$GATE" "gdpr-gate.sh exists"
assert_file_exists "$FIXTURE_NOTICE" "stale fixture NOTICE exists"
assert_file_exists "$GH_STUB_DIR/gh" "fixture gh stub exists"

# Quick precondition: the fixture must report ≥90 days stale.
FIXTURE_DAYS=$(NOTICE_FILE="$FIXTURE_NOTICE" \
  bash "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh" days-stale)
if (( FIXTURE_DAYS >= 90 )); then
  echo "  PASS: fixture is ≥90 days stale ($FIXTURE_DAYS days)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: fixture not stale enough ($FIXTURE_DAYS days — bump fixture last-verified or refresh threshold)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Case A: token absent → operator-attested banner + staleness + POSTURE_FAIL ---
echo "Case A: no token → operator-attested-mode banner + staleness + POSTURE_FAIL"
# A regulated-data path keeps the gate exercising its full output surface
# without coupling the test to specific path-glob behavior.
CASE_A_PATH="apps/web-platform/lib/auth/foo.ts"
set +e
CASE_A_OUT=$(NOTICE_FILE="$FIXTURE_NOTICE" GH_TOKEN="" GITHUB_TOKEN="" \
  bash "$GATE" "$CASE_A_PATH" 2>/dev/null)
CASE_A_RC=$?
set -e
assert_contains "$CASE_A_OUT" "$BANNER_LITERAL" "Case A: operator-attested-mode banner present"
assert_contains "$CASE_A_OUT" "days stale" "Case A: 30d staleness banner present"
assert_contains "$CASE_A_OUT" "POSTURE_FAIL:" "Case A: >90d POSTURE_FAIL line present"
assert_eq "0" "$CASE_A_RC" "Case A: gate exits 0 (advisory contract)"
echo ""

# --- Case B: stub gh resolves cron-run timestamp → no operator-attested banner ---
echo "Case B: stub gh present → operator-attested-mode banner SUPPRESSED"
set +e
CASE_B_OUT=$(NOTICE_FILE="$FIXTURE_NOTICE" GH_TOKEN="stub-token" GITHUB_TOKEN="" \
  PATH="$GH_STUB_DIR:$PATH" \
  bash "$GATE" "$CASE_A_PATH" 2>/dev/null)
CASE_B_RC=$?
set -e
if [[ "$CASE_B_OUT" != *"$BANNER_LITERAL"* ]]; then
  echo "  PASS: Case B: operator-attested-mode banner suppressed (cron-run binding resolved)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Case B: operator-attested-mode banner unexpectedly present"
  echo "    stdout: $CASE_B_OUT"
  FAIL=$((FAIL + 1))
fi
assert_eq "0" "$CASE_B_RC" "Case B: gate exits 0 (advisory contract)"
echo ""

print_results
