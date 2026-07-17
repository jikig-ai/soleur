#!/usr/bin/env bash
# Tests for scripts/sentry-destroy-counts.sh (#6589) — the single source of the
# sentry destroy arithmetic, shared by apply-sentry-infra.yml's `plan_pr` and
# `apply` jobs.
#
# T1 is THE regression test. This script exists because the arithmetic was inline
# in both jobs and drifted: `plan_pr` dropped the `destroy_count=$((…))` line and
# then read `$destroy_count`, so under `set -u` the gate died on every run — a
# permanently-red gate whose green path had never executed, shipped inside the PR
# that exists to stop exactly that kind of unchecked claim. T1 asserts the emitted
# contract includes destroy_count, so a future copy-adaptation cannot silently
# drop it again.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/sentry-destroy-counts.sh"
FIXTURES="$REPO_ROOT/tests/scripts/fixtures"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

[[ -f "$SCRIPT" ]] || { echo "ERROR: $SCRIPT does not exist — RED phase expected this." >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

_run() { bash "$SCRIPT" "$1" 2>/dev/null; }

# ── T1: the emitted contract carries ALL FOUR keys, destroy_count included ──
# The shipped bug in one assertion. A consumer does `eval "$(script …)"` and then
# reads $destroy_count under `set -u`; if the script stops emitting it, every
# consumer dies at its first read.
t_emits_full_contract() {
  local out; out=$(_run "$FIXTURES/tfplan-sentry-resource-delete.json")
  local missing=()
  for k in resource_deletes resource_creates nested_deletes destroy_count; do
    grep -qE "^${k}=[0-9]+$" <<<"$out" || missing+=("$k")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _report "T1 emits all four keys incl. destroy_count (the shipped-bug regression)" ok
  else
    _report "T1 emits all four keys incl. destroy_count" fail "missing: ${missing[*]}; got: $out"
  fi
}

# ── T2: eval-ing the output under `set -u` binds every variable a caller reads ──
# Models the consumer exactly. This is the assertion the workflow needed and
# didn't have: it fails if ANY key a caller reads is unbound.
t_eval_binds_all_caller_vars() {
  local rc=0
  ( set -euo pipefail
    eval "$(_run "$FIXTURES/tfplan-sentry-resource-delete.json")"
    : "$resource_deletes" "$resource_creates" "$nested_deletes" "$destroy_count"
  ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    _report "T2 eval under set -u binds every var the workflow reads (unbound-variable regression)" ok
  else
    _report "T2 eval under set -u binds every var the workflow reads" fail \
      "rc=$rc — a consumer would die on an unbound variable, exactly as plan_pr did"
  fi
}

# ── T3: destroy_count is the SUM, not a copy of one term ───────────────────
# A nested-only delete (rdel=0, ndel=1) distinguishes sum from `=$resource_deletes`.
t_destroy_count_is_the_sum() {
  local out; out=$(_run "$FIXTURES/tfplan-sentry-issue-alert-nested-delete.json")
  local rd nd dc
  rd=$(grep -oP '^resource_deletes=\K.*' <<<"$out")
  nd=$(grep -oP '^nested_deletes=\K.*' <<<"$out")
  dc=$(grep -oP '^destroy_count=\K.*' <<<"$out")
  if [[ "$rd" == "0" && "$nd" == "1" && "$dc" == "1" ]]; then
    _report "T3 destroy_count sums resource+nested (nested-only delete is counted)" ok
  else
    _report "T3 destroy_count sums resource+nested" fail "rd=$rd nd=$nd dc=$dc want 0/1/1"
  fi
}

t_no_changes_is_zero() {
  local out; out=$(_run "$FIXTURES/tfplan-sentry-no-changes.json")
  if grep -qx 'destroy_count=0' <<<"$out" && grep -qx 'resource_creates=0' <<<"$out"; then
    _report "T4 a no-changes plan yields destroy_count=0 / resource_creates=0" ok
  else
    _report "T4 a no-changes plan yields zeros" fail "got: $out"
  fi
}

# ── T5: fail-closed on a malformed plan ────────────────────────────────────
t_malformed_plan_fails() {
  printf 'not json {' > "$TMP/bad.json"
  local rc=0; bash "$SCRIPT" "$TMP/bad.json" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _report "T5 malformed plan JSON fails closed" ok
  else
    _report "T5 malformed plan JSON fails closed" fail "rc=$rc want non-zero"
  fi
}

t_missing_file_fails() {
  local rc=0; bash "$SCRIPT" "$TMP/nope.json" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _report "T6 missing plan file fails closed" ok
  else
    _report "T6 missing plan file fails closed" fail "rc=$rc want non-zero"
  fi
}

t_no_args_fails() {
  local rc=0; bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _report "T7 no arguments fails closed" ok
  else
    _report "T7 no arguments fails closed" fail "rc=$rc want non-zero"
  fi
}

# ── T8: the two callers use the SAME script (no second copy) ───────────────
# The structural guarantee. If a future edit re-inlines the arithmetic in either
# job, this reds — which is the whole reason the script exists rather than a
# parity test over two copies.
t_both_jobs_call_the_script() {
  local wf="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"
  local calls; calls=$(grep -cE 'sentry-destroy-counts\.sh' "$wf")
  local inline; inline=$(grep -cE '^\s*destroy_count=\$\(\(' "$wf" || true)
  if [[ "$calls" -ge 2 && "$inline" -eq 0 ]]; then
    _report "T8 both workflow jobs call the shared script; zero inline destroy_count arithmetic" ok
  else
    _report "T8 both workflow jobs call the shared script; zero inline arithmetic" fail \
      "script calls=$calls (want >=2), inline destroy_count assignments=$inline (want 0) — the arithmetic has been re-duplicated, which is how it drifted the first time"
  fi
}

t_emits_full_contract
t_eval_binds_all_caller_vars
t_destroy_count_is_the_sum
t_no_changes_is_zero
t_malformed_plan_fails
t_missing_file_fails
t_no_args_fails
t_both_jobs_call_the_script

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
