#!/usr/bin/env bash
# Tests for scripts/tenant-integration-gate-verdict.sh — the fail-closed
# verdict for the `tenant-integration-required` aggregator gate job (#5585).
#
# The script takes two args (detect-changes result, tenant-integration result)
# and exits 0 iff the gate should report SUCCESS, 1 otherwise. Allow-list
# semantics: pass ONLY on (detect==success) AND (suite ∈ {success, skipped});
# everything else — including detect-changes failure/cancelled/skipped/empty
# (the DROP-1 fail-open class) and any future GitHub-added result state —
# fails closed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/tenant-integration-gate-verdict.sh"
pass=0; fail=0

# _expect <expected-rc> <detect> <suite> <label>
_expect() {
  local want="$1" detect="$2" suite="$3" label="$4" got
  if bash "$SCRIPT" "$detect" "$suite" >/dev/null 2>&1; then got=0; else got=1; fi
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1)); echo "[ok] $label (detect=$detect suite=$suite -> rc=$got)"
  else
    fail=$((fail + 1)); echo "[FAIL] $label: want rc=$want got rc=$got (detect=$detect suite=$suite)" >&2
  fi
}

# --- PASS branches ---
_expect 0 success success  "relevant PR, suite green"
_expect 0 success skipped  "unrelated PR, suite skipped"

# --- FAIL branches ---
_expect 1 success failure  "relevant PR, suite red"
_expect 1 success cancelled "suite cancelled (not a verified pass)"
# Pins the detect-MUST-be-success axis on the suite=success value (NOT just on
# suite=skipped): a naive `suite==success || (detect==success && suite==skipped)`
# would fail-OPEN here (detect failed yet gate greens). #5585 review (test-design).
_expect 1 failure success   "detect-changes failed but suite green must FAIL closed"
_expect 1 failure skipped   "DROP-1: detect-changes failed -> suite skipped must FAIL closed"
_expect 1 cancelled skipped "detect-changes cancelled must FAIL closed"
_expect 1 skipped  skipped   "detect-changes skipped must FAIL closed"
_expect 1 success ""        "empty suite result fails closed"
_expect 1 ""      ""        "both empty fail closed"
_expect 1 success bogus_future_state "unknown suite state fails closed (allow-list)"
_expect 1 bogus_future_state skipped "unknown detect state fails closed (allow-list)"

# --- fail-closed DIAGNOSTIC (not just exit code): CI surfaces the failure via
# the ::error:: annotation; a regression that drops it would still exit 1 but
# go silent in the checks UI. Assert the annotation on a representative case. ---
# Capture stderr into a var (not a pipe) so the script's expected exit 1 does
# not poison the check under `set -o pipefail`.
err_out=$(bash "$SCRIPT" failure skipped 2>&1 >/dev/null) || true
if printf '%s' "$err_out" | grep -q '::error::'; then
  pass=$((pass + 1)); echo "[ok] fail-closed emits ::error:: diagnostic on stderr"
else
  fail=$((fail + 1)); echo "[FAIL] fail-closed path did not emit ::error:: on stderr" >&2
fi

echo "---"
echo "tenant-integration-gate-verdict: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
