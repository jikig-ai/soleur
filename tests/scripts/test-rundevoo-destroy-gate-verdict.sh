#!/usr/bin/env bash
# Tests for scripts/rundevoo-destroy-gate-verdict.sh (#12971). Mirrors
# tests/scripts/test-sentry-destroy-gate-verdict.sh (#6589).
#
# The verdict is an ALLOW-LIST: only (success, success) and (success, skipped)
# pass. Every other result pair — including a future GitHub-added string —
# must exit 1. The matrix below enumerates every value GitHub emits for
# needs.<job>.result (success | failure | cancelled | skipped | "") against
# both slots, so the cell coverage is total, not sampled.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERDICT="$REPO_ROOT/scripts/rundevoo-destroy-gate-verdict.sh"
pass=0; fail=0
EXPECTED_TESTS=30

_report() {
  if [[ "$2" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $1"
  else fail=$((fail + 1)); echo "[FAIL] $1 $3" >&2; fi
}

if [[ ! -f "$VERDICT" ]]; then
  echo "ERROR: $VERDICT does not exist — RED phase expected this." >&2
  exit 1
fi

results=(success failure cancelled skipped "")

# T1..T25: the full 5x5 matrix. Expected pass cells: (success,success) and
# (success,skipped). Everything else must exit 1.
i=0
for d in "${results[@]}"; do
  for p in "${results[@]}"; do
    i=$((i + 1))
    want=1
    if [[ "$d" == "success" && ( "$p" == "success" || "$p" == "skipped" ) ]]; then
      want=0
    fi
    rc=0
    bash "$VERDICT" "$d" "$p" >/dev/null 2>&1 || rc=$?
    label="T$i detect='${d:-<empty>}' plan='${p:-<empty>}'"
    if [[ "$rc" -eq "$want" ]]; then
      _report "$label -> $rc" ok
    else
      _report "$label" fail "rc=$rc want $want — the verdict must be allow-listed, not deny-listed"
    fi
  done
done

# T16: PASS output names both results (operator readability; a silent green is
# not auditable).
out=$(bash "$VERDICT" success skipped)
if [[ "$out" == *"PASS"* && "$out" == *"plan_pr=skipped"* ]]; then
  _report "T16 PASS output names the job results" ok
else
  _report "T16 PASS output names the job results" fail "got '$out'"
fi

# T17: FAIL output goes to stderr as an ::error:: annotation (CI surfaces it).
err=$(bash "$VERDICT" success failure 2>&1 >/dev/null || true)
if [[ "$err" == *"::error::"* && "$err" == *"FAILED closed"* ]]; then
  _report "T17 FAIL emits an ::error:: annotation naming fail-closed" ok
else
  _report "T17 FAIL emits an ::error:: annotation" fail "got '$err'"
fi

# T26-T28: near-miss inputs must NOT pass — a normalization "simplification"
# (case-folding, prefix match, whitespace trim) would green these while GitHub
# emitted something the allow-list never certified.
for near in "Success" "success " " success"; do
  i=$((i + 1))
  rc=0
  bash "$VERDICT" "$near" success >/dev/null 2>&1 || rc=$?
  label="T$i near-miss detect='${near}' plan='success'"
  if [[ "$rc" -eq 1 ]]; then
    _report "$label -> $rc" ok
  else
    _report "$label" fail "rc=$rc want 1 — near-miss inputs must fail the allow-list"
  fi
done

echo "=== $pass passed, $fail failed ==="
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
