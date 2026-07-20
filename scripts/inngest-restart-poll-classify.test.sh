#!/usr/bin/env bash
# Unit tests for scripts/inngest-restart-poll-classify.sh (#6407, code-review Finding B).
# The restart-verify poll loop's decision logic was GHA-inline bash with no unit test;
# these tests cover every classify_restart_frame verdict plus both budget-expiry
# adjudicators. Network + curl I/O stay in the workflow; here inputs are injected values.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/inngest-restart-poll-classify.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

echo "=== inngest-restart-poll-classify.sh tests ==="

# FRESH_FLOOR anchor for the frame tests. FRESH=1000 is at/after the floor; STALE=500 is below.
FLOOR=800
FRESH=1000
STALE=500

echo "--- classify_restart_frame ---"

# exit 0 + inngest + fresh → success (the only exit-0 verdict; RED would be predates if floor compared wrong).
assert_eq "exit0 + inngest + fresh → success" "success" \
  "$(classify_restart_frame 0 inngest "$FRESH" "$FLOOR" completed)"

# exit 0 + inngest + stale → predates (a green PREVIOUS-slot read before our webhook writes running).
assert_eq "exit0 + inngest + stale → predates" "predates" \
  "$(classify_restart_frame 0 inngest "$STALE" "$FLOOR" completed)"

# failure + inngest + stale → predates (a stale FAILED previous slot must not fail our fresh run).
assert_eq "failure + inngest + stale → predates" "predates" \
  "$(classify_restart_frame 1 inngest "$STALE" "$FLOOR" some_error)"

# exit 0 + non-inngest → other_component (a green web/redis frame; keep waiting for inngest).
assert_eq "exit0 + non-inngest → other_component" "other_component" \
  "$(classify_restart_frame 0 web "$FRESH" "$FLOOR" completed)"

# failure + non-inngest → other_component (a failed web frame is not OUR restart; keep waiting).
assert_eq "failure + non-inngest → other_component" "other_component" \
  "$(classify_restart_frame 1 web "$FRESH" "$FLOOR" some_error)"

# exit_code sentinels (component/start_ts irrelevant — RED would be a fresh-floor branch).
assert_eq "exit -1 → still_running" "still_running" \
  "$(classify_restart_frame -1 inngest "$STALE" "$FLOOR" running)"
assert_eq "exit -2 → no_prior" "no_prior" \
  "$(classify_restart_frame -2 unknown "$STALE" "$FLOOR" unknown)"
assert_eq "exit -3 → corrupt" "corrupt" \
  "$(classify_restart_frame -3 unknown "$STALE" "$FLOOR" unknown)"

# failure + inngest + fresh + reason=lock_contention → lock_contention (NON-TERMINAL, keep polling).
assert_eq "failure + inngest + fresh + lock_contention → lock_contention" "lock_contention" \
  "$(classify_restart_frame 1 inngest "$FRESH" "$FLOOR" lock_contention)"

# failure + inngest + fresh + reason!=lock_contention → terminal_fail (exit 1). RED under a wrong
# impl that treated all failures as benign would echo lock_contention here.
assert_eq "failure + inngest + fresh + other reason → terminal_fail" "terminal_fail" \
  "$(classify_restart_frame 1 inngest "$FRESH" "$FLOOR" health_check_failed)"

# The .exit_code // -99 sentinel (no exit_code in the body) falls into the failure `*)` branch.
assert_eq "sentinel -99 + inngest + fresh + other reason → terminal_fail" "terminal_fail" \
  "$(classify_restart_frame -99 inngest "$FRESH" "$FLOOR" health_check_failed)"

echo "--- deploy_status_confirms_fresh_inngest ---"

# 200 + inngest + exit0 + fresh start_ts → yes.
assert_eq "200 + inngest + exit0 + fresh → yes" "yes" \
  "$(deploy_status_confirms_fresh_inngest 200 '{"component":"inngest","exit_code":0,"start_ts":1000}' "$FLOOR")"

# 200 + inngest + exit0 but STALE start_ts (< floor) → no (a superseded op that predates our trigger).
assert_eq "200 + inngest + exit0 + stale start_ts → no" "no" \
  "$(deploy_status_confirms_fresh_inngest 200 '{"component":"inngest","exit_code":0,"start_ts":500}' "$FLOOR")"

# 200 + exit0 + fresh but WRONG component → no.
assert_eq "200 + exit0 + fresh + wrong component → no" "no" \
  "$(deploy_status_confirms_fresh_inngest 200 '{"component":"web","exit_code":0,"start_ts":1000}' "$FLOOR")"

# non-200 (otherwise-confirming body) → no.
assert_eq "non-200 → no" "no" \
  "$(deploy_status_confirms_fresh_inngest 500 '{"component":"inngest","exit_code":0,"start_ts":1000}' "$FLOOR")"

# non-JSON body at 200 → no.
assert_eq "200 + non-JSON body → no" "no" \
  "$(deploy_status_confirms_fresh_inngest 200 'not json' "$FLOOR")"

echo "--- liveness_confirms_healthy ---"

# 200 + non-empty functions array → yes.
assert_eq "200 + non-empty functions → yes" "yes" \
  "$(liveness_confirms_healthy 200 '{"functions":[{"id":"fn-a"}]}')"

# 200 + EMPTY functions array → no (cold-start empty registry MUST NOT confirm — load-bearing).
assert_eq "200 + empty functions (cold start) → no" "no" \
  "$(liveness_confirms_healthy 200 '{"functions":[]}')"

# non-200 (otherwise-healthy body) → no.
assert_eq "non-200 → no" "no" \
  "$(liveness_confirms_healthy 404 '{"functions":[{"id":"fn-a"}]}')"

# 200 + non-object (array) body → no.
assert_eq "200 + non-object body → no" "no" \
  "$(liveness_confirms_healthy 200 '[1,2,3]')"

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
