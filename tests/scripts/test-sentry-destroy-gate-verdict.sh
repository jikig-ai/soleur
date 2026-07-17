#!/usr/bin/env bash
# Tests for scripts/sentry-destroy-gate-verdict.sh — the fail-closed verdict of
# the `sentry-destroy-required` aggregator gate (#6589).
#
# The verdict is an ALLOW-LIST, so the interesting coverage is the DENY side:
# every state that is not explicitly enumerated must fail closed. A deny-list
# implementation (`!= 'failure'`) would pass T1/T2 and fail T4-T9 — which is the
# point of enumerating them.
#
# Mirrors tests/scripts/test-tenant-integration-gate-verdict.sh (#5585).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERDICT="$REPO_ROOT/scripts/sentry-destroy-gate-verdict.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

[[ -f "$VERDICT" ]] || { echo "ERROR: $VERDICT does not exist — RED phase expected this." >&2; exit 1; }

# _expect <want_rc> <label> <detect> <plan>
_expect() {
  local want="$1" label="$2" detect="${3-}" plan="${4-}"
  local rc=0
  bash "$VERDICT" "$detect" "$plan" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then
    _report "$label" ok
  else
    _report "$label" fail "got rc=$rc want rc=$want (detect='$detect' plan='$plan')"
  fi
}

# ── PASS branches (the only two) ────────────────────────────────────────────
# T1: relevant PR, full-root plan green (destroys nothing, or ack pre-staged).
_expect 0 "T1 detect=success plan=success -> PASS" success success
# T2: PR does not touch infra/sentry/**, or merge_group candidate -> plan skipped.
_expect 0 "T2 detect=success plan=skipped -> PASS (unrelated PR / merge_group)" success skipped

# ── FAIL-CLOSED branches ────────────────────────────────────────────────────
# T3: the plan job found an unacknowledged destroy. The whole point.
_expect 1 "T3 detect=success plan=failure -> FAIL (unacked destroy)" success failure
# T4: a cancelled plan taught us nothing. Must not green.
_expect 1 "T4 detect=success plan=cancelled -> FAIL closed" success cancelled
# T5: empty plan result — the job never ran because its chain broke. This is the
# state a deny-list (`!= 'failure'`) would silently green, laundering "unknown"
# into "approved".
_expect 1 "T5 detect=success plan=<empty> -> FAIL closed (never-ran, not approved)" success ""
# T6: detect-changes failed -> we do not know whether the surface was touched.
_expect 1 "T6 detect=failure -> FAIL closed (path detection unknown)" failure success
# T7: detect-changes cancelled.
_expect 1 "T7 detect=cancelled -> FAIL closed" cancelled success
# T8: detect-changes skipped — cannot happen today, but must not fail open if it
# ever can (the DROP-1 fail-open class).
_expect 1 "T8 detect=skipped -> FAIL closed" skipped success
# T9: both empty (workflow-level failure).
_expect 1 "T9 detect=<empty> plan=<empty> -> FAIL closed" "" ""
# T10: a future GitHub-added result string must not fail open.
_expect 1 "T10 unknown future result string -> FAIL closed" success "neutral"
# T11: no args at all.
_expect 1 "T11 no arguments -> FAIL closed" "" ""

# ── The deny-list mutation ──────────────────────────────────────────────────
# Proves the allow-list is load-bearing: a `!= failure` implementation passes
# T1/T2/T3 and silently greens T4/T5. If this test ever goes vacuous, the
# guard has been rewritten as a deny-list.
t_allowlist_is_loadbearing() {
  local denylist_rc=0
  # Simulate the deny-list a well-meaning refactor would write.
  bash -c '
    detect="${1:-}"; plan="${2:-}"
    if [[ "$plan" != "failure" ]]; then exit 0; fi
    exit 1
  ' _ success "" >/dev/null 2>&1 || denylist_rc=$?
  local real_rc=0
  bash "$VERDICT" success "" >/dev/null 2>&1 || real_rc=$?
  if [[ "$denylist_rc" -eq 0 && "$real_rc" -eq 1 ]]; then
    _report "T12 allow-list rejects the empty result a deny-list would green (non-vacuity)" ok
  else
    _report "T12 allow-list rejects the empty result a deny-list would green" fail \
      "denylist_rc=$denylist_rc (want 0) real_rc=$real_rc (want 1)"
  fi
}
t_allowlist_is_loadbearing

# The PASS message must name both inputs so a CI reader can tell WHY it passed —
# "PASS" alone cannot distinguish "plan was green" from "plan never ran".
t_pass_message_names_inputs() {
  local out; out=$(bash "$VERDICT" success skipped 2>&1)
  if [[ "$out" == *"detect-changes=success"* && "$out" == *"plan_pr=skipped"* ]]; then
    _report "T13 PASS message names both job results" ok
  else
    _report "T13 PASS message names both job results" fail "got: $out"
  fi
}
t_pass_message_names_inputs

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
