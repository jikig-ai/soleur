#!/usr/bin/env bash
# Unit tests for scripts/inngest-restart-age-gate.sh (#6374, Defect 3). The external
# watchdog caps restart churn via an issue-AGE gate (NOT a body counter): a single read
# of the open [ci/inngest-down] issue createdAt, zero writes, no chicken-and-egg (the
# dispatch step runs BEFORE the issue exists on the first failure). The LLM/network is out
# of the assertion path — createdAt + now are injected as seams.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/inngest-restart-age-gate.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

echo "=== inngest-restart-age-gate.sh tests ==="

WINDOW=45
NOW="2026-07-13T02:00:00Z"
NOW_EPOCH=$(date -u -d "$NOW" +%s)

# First failure of the episode — no open issue yet → dispatch once.
assert_eq "no open issue (first failure) → restart_ok=true" "true" \
  "$(restart_ok_from_age "" "$WINDOW" "$NOW_EPOCH")"

# Issue present, age BELOW the window → keep dispatching.
assert_eq "issue age 10 min (< 45) → restart_ok=true" "true" \
  "$(restart_ok_from_age "2026-07-13T01:50:00Z" "$WINDOW" "$NOW_EPOCH")"

# Issue present, age AT the window boundary (exactly 45 min) → give up (>= window).
assert_eq "issue age exactly 45 min → restart_ok=false (give up at boundary)" "false" \
  "$(restart_ok_from_age "2026-07-13T01:15:00Z" "$WINDOW" "$NOW_EPOCH")"

# Issue present, age WELL BEYOND the window → give up.
assert_eq "issue age 3h (>> 45) → restart_ok=false" "false" \
  "$(restart_ok_from_age "2026-07-12T23:00:00Z" "$WINDOW" "$NOW_EPOCH")"

# Unparseable createdAt → fail-OPEN (dispatch) rather than silently suppress recovery.
assert_eq "unparseable createdAt → restart_ok=true (fail-open, never strand a real down)" "true" \
  "$(restart_ok_from_age "not-a-date" "$WINDOW" "$NOW_EPOCH")"

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
