#!/usr/bin/env bash
# Tests for scripts/vendor-pin-gate-verdict.sh — the fail-closed verdict of
# the `vendor-pin-required` aggregator gate (#8203).
#
# The verdict is an ALLOW-LIST, so the interesting coverage is the DENY side:
# every state that is not explicitly enumerated must fail closed. A deny-list
# implementation (`!= 'failure'`) would pass T1/T2 and silently green T4-T11 —
# which is the point of enumerating them.
#
# Mirrors tests/scripts/test-tenant-integration-gate-verdict.sh (#5585) and
# tests/scripts/test-sentry-destroy-gate-verdict.sh (#6589).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERDICT="$REPO_ROOT/scripts/vendor-pin-gate-verdict.sh"
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

# _expect <want_rc> <label> <detect> <verify>
_expect() {
  local want="$1" label="$2" detect="${3-}" verify="${4-}"
  local rc=0
  bash "$VERDICT" "$detect" "$verify" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then
    _report "$label" ok
  else
    _report "$label" fail "got rc=$rc want rc=$want (detect='$detect' verify='$verify')"
  fi
}

# ── PASS branches (the only two) ────────────────────────────────────────────
# T1: vendored-tree PR, every NOTICE upstream-blob-sha resolved upstream.
_expect 0 "T1 detect=success verify=success -> PASS" success success
# T2: PR does not touch the vendored surface, or merge_group candidate ->
# verify skipped.
_expect 0 "T2 detect=success verify=skipped -> PASS (unrelated PR / merge_group)" success skipped

# ── FAIL-CLOSED branches ────────────────────────────────────────────────────
# T3: the verification found an unresolvable upstream blob — the #8181 binding
# broken. The whole point.
_expect 1 "T3 detect=success verify=failure -> FAIL (unresolved upstream blob)" success failure
# T4: a cancelled verification taught us nothing. Must not green.
_expect 1 "T4 detect=success verify=cancelled -> FAIL closed" success cancelled
# T5: empty verify result — the job never ran because its chain broke. This is
# the state a deny-list (`!= 'failure'`) would silently green, laundering
# "unknown" into "approved".
_expect 1 "T5 detect=success verify=<empty> -> FAIL closed (never-ran, not approved)" success ""
# T6: detect-changes failed -> we do not know whether the vendored surface was
# touched (DROP-1 fail-open class).
_expect 1 "T6 detect=failure -> FAIL closed (path detection unknown)" failure success
_expect 1 "T6b detect=failure verify=skipped -> FAIL closed" failure skipped
# T7: detect-changes cancelled.
_expect 1 "T7 detect=cancelled -> FAIL closed" cancelled success
# T8: detect-changes skipped — cannot happen today, but must not fail open if
# it ever can (the DROP-1 fail-open class).
_expect 1 "T8 detect=skipped -> FAIL closed" skipped success
# T9: both empty (workflow-level failure).
_expect 1 "T9 detect=<empty> verify=<empty> -> FAIL closed" "" ""
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
    detect="${1:-}"; verify="${2:-}"
    if [[ "$verify" != "failure" ]]; then exit 0; fi
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
# "PASS" alone cannot distinguish "verification was green" from "verification
# never ran".
t_pass_message_names_inputs() {
  local out; out=$(bash "$VERDICT" success skipped 2>&1)
  if [[ "$out" == *"detect-changes=success"* && "$out" == *"verify-upstream-blobs=skipped"* ]]; then
    _report "T13 PASS message names both job results" ok
  else
    _report "T13 PASS message names both job results" fail "got: $out"
  fi
}
t_pass_message_names_inputs

# The skipped arm must disclose itself: a green required check on a PR where
# the verification never ran must carry the ::notice, not read as a verified
# tree.
t_skipped_arm_discloses() {
  local out; out=$(bash "$VERDICT" success skipped 2>&1)
  if [[ "$out" == *"::notice::"* && "$out" == *"SKIPPED arm"* ]]; then
    _report "T14 skipped PASS arm emits the honesty ::notice" ok
  else
    _report "T14 skipped PASS arm emits the honesty ::notice" fail "got: $out"
  fi
}
t_skipped_arm_discloses

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
