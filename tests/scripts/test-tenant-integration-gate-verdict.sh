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

# --- the TWO PASS arms are distinguishable, not just both green ---
# `success` means the heavy dev-Supabase suite ran against this tree; `skipped`
# means it did not, and its first execution will be the post-merge push to main.
# The required check reports the same green either way, so the disclosure is the
# only thing that separates them — assert it on both arms, in both directions.
_summary_file=$(mktemp)
trap 'rm -f "$_summary_file"' EXIT

skipped_out=$(GITHUB_STEP_SUMMARY="$_summary_file" bash "$SCRIPT" success skipped 2>/dev/null)
if printf '%s' "$skipped_out" | grep -q '::notice::'; then
  pass=$((pass + 1)); echo "[ok] PASS/skipped arm emits a ::notice:: annotation on stdout"
else
  fail=$((fail + 1)); echo "[FAIL] PASS/skipped arm emitted no ::notice:: annotation" >&2
fi
if printf '%s' "$skipped_out" | grep -q 'did NOT execute against this tree'; then
  pass=$((pass + 1)); echo "[ok] PASS/skipped notice states the suite did not execute against this tree"
else
  fail=$((fail + 1)); echo "[FAIL] PASS/skipped notice does not state that the suite did not execute" >&2
fi
if grep -q 'post-merge' "$_summary_file"; then
  pass=$((pass + 1)); echo "[ok] PASS/skipped arm writes the post-merge-first-execution line to \$GITHUB_STEP_SUMMARY"
else
  fail=$((fail + 1)); echo "[FAIL] PASS/skipped arm wrote no post-merge line to \$GITHUB_STEP_SUMMARY" >&2
fi

# The negative half: the arm that DID run the suite must not claim it was
# skipped. Without this, an unconditional notice would pass every check above
# while telling every green PR its suite never ran.
: >"$_summary_file"
ran_out=$(GITHUB_STEP_SUMMARY="$_summary_file" bash "$SCRIPT" success success 2>/dev/null)
if printf '%s' "$ran_out" | grep -q '::notice::'; then
  fail=$((fail + 1)); echo "[FAIL] PASS/success arm emitted the skipped-suite notice" >&2
else
  pass=$((pass + 1)); echo "[ok] PASS/success arm emits no skipped-suite notice"
fi
if [[ -s "$_summary_file" ]]; then
  fail=$((fail + 1)); echo "[FAIL] PASS/success arm wrote to \$GITHUB_STEP_SUMMARY" >&2
else
  pass=$((pass + 1)); echo "[ok] PASS/success arm writes nothing to \$GITHUB_STEP_SUMMARY"
fi

# An unset GITHUB_STEP_SUMMARY (local runs, and this suite's own default) must
# not turn the disclosure into a crash: the annotation still goes out and the
# verdict still exits 0.
if unset_out=$(env -u GITHUB_STEP_SUMMARY bash "$SCRIPT" success skipped 2>/dev/null) &&
  printf '%s' "$unset_out" | grep -q '::notice::'; then
  pass=$((pass + 1)); echo "[ok] PASS/skipped arm still exits 0 and annotates with GITHUB_STEP_SUMMARY unset"
else
  fail=$((fail + 1)); echo "[FAIL] PASS/skipped arm broke with GITHUB_STEP_SUMMARY unset" >&2
fi

# --- eviction arm (#7055). `cancelled` still fails closed (asserted above), but
# the DIAGNOSTIC must name eviction and the remedy, or the author debugs a test
# failure that does not exist. Assert the message, and assert the arm did not
# widen the allow-list on the detect axis. ---
evict_err=$(bash "$SCRIPT" success cancelled 2>&1 >/dev/null) || true
if printf '%s' "$evict_err" | grep -q 'EVICTION'; then
  pass=$((pass + 1)); echo "[ok] suite=cancelled diagnostic names concurrency eviction"
else
  fail=$((fail + 1)); echo "[FAIL] suite=cancelled diagnostic does not name eviction" >&2
fi
if printf '%s' "$evict_err" | grep -q 'Re-run failed jobs'; then
  pass=$((pass + 1)); echo "[ok] suite=cancelled diagnostic names the re-run remedy"
else
  fail=$((fail + 1)); echo "[FAIL] suite=cancelled diagnostic names no remedy" >&2
fi
# The arm must not have widened the allow-list: a FAILED detect with a cancelled
# suite is a different state and must not inherit the eviction explanation.
noevict_err=$(bash "$SCRIPT" failure cancelled 2>&1 >/dev/null) || true
if printf '%s' "$noevict_err" | grep -q 'EVICTION'; then
  fail=$((fail + 1)); echo "[FAIL] detect=failure wrongly inherits the eviction diagnostic" >&2
else
  pass=$((pass + 1)); echo "[ok] detect=failure does not inherit the eviction diagnostic"
fi

# --- anti-vacuity floor (#7898 review). This suite had NO floor: deleting every
# row above left it reporting "0 passed, 0 failed" and exiting 0. Set to the
# measured green count so a silently-dropped row is caught. A FLOOR, not an
# equality -- adding a row must not red the suite; raise it when you add one.
# Emitted with printf + exit rather than through pass()/fail(), because a floor
# dispatched through the helpers it backstops is disarmed by the same one-line
# edit that disarms them.
readonly MIN_ASSERTIONS=22
if [[ "$((pass + fail))" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' \
    "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo "---"
echo "tenant-integration-gate-verdict: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
