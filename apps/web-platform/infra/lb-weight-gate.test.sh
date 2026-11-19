#!/usr/bin/env bash
# Tests for lb-weight-gate.sh — the rebuilt fail-closed, SHAPE-ONLY ADR-068 §(c) / ADR-143 D3
# anti-pooling gate (#6575 rebuild, #6459). Asserts on EXIT CODES **and** the structured
# `gate_fail sub_condition=…` stderr line (the machine-readable contract a future orchestrator
# parses), accumulate-then-exit. Asserting the sub_condition — not just a non-zero rc — makes a
# refactor that rejects for the WRONG reason go RED.
#
# The gate is pure over injected env; these tests run it under `env -i PATH=…` so a "missing" var
# is genuinely absent (not inherited). Timestamps are computed RELATIVE TO A COMPUTED `now` — never
# date-faked / hard-coded.
#
# SECTIONS:
#   §0 TOP-GUARD (ADR-143 D3): the standby PASS branch (weight==0 & web-2 ∉ rotation) + the
#      fail-closed weight/rotation cases + AC7 (weight>0 pre-flip with unmet A/B → FAIL).
#   §1-8 Condition A + B flip-authorization shape (run only when web-2 is being pooled), incl. the
#      §6459 WORKSPACES_LUKS precondition (coupling #2).
#   §C Condition C — STATIC committed-HCL anti-pooling assertions over the real .tf tree (the CI
#      regression guard: catches an accidental COMMIT that pools web-2; CTO ruling 2b). Fail-closed
#      on parse failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${SCRIPT_DIR}/lb-weight-gate.sh"

PASS=0
FAIL=0
TOTAL=0

# --- Computed-now timestamps (NO date-faking) --------------------------------
NOW=$(date -u +%s)
ISO() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
ELAPSED_CUTOVER=$(ISO "$(( NOW - 4 * 86400 ))")   # 4d ago > default 3d soak → elapsed
FRESH_CUTOVER=$(ISO "$(( NOW - 1 * 86400 ))")     # 1d ago < 3d soak → not elapsed
FUTURE_CUTOVER=$(ISO "$(( NOW + 2 * 86400 ))")    # future → reject
BOUNDARY_CUTOVER=$(ISO "$(( NOW - 3 * 86400 ))")  # exactly 3d ago → delta >= soak → passes
NOW_CUTOVER=$(ISO "$NOW")                          # marker == now → future-check ok, soak fails
TZOFFSET_CUTOVER="$(date -u -d "@$(( NOW - 4 * 86400 + 2 * 3600 ))" +%Y-%m-%dT%H:%M:%S)+02:00"

# --- Default injected config: web-2 IS being pooled (weight=1) so Conditions A+B evaluate, AND
#     both flip-authorization conditions hold → the "authorized flip" exit-0 baseline. Individual
#     tests below mutate one field to assert its sub_condition. -------------------------------
declare -A DEF
reset_def() {
  DEF=(
    [SOLEUR_WEB2_SERVING_WEIGHT]='1'
    [SOLEUR_GATED_HOST]='web-2'
    [SOLEUR_SERVING_ROTATION]='web-1,web-2'
    [SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.11'
    [SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11"}'
    [GIT_DATA_STORE_ENABLED]='true'
    [GIT_DATA_LUKS_CUTOVER_AT]="$ELAPSED_CUTOVER"
    [GIT_DATA_LUKS_SOAK_DAYS]='3'
    [WORKSPACES_LUKS_CUTOVER_AT]="$ELAPSED_CUTOVER"
    [WORKSPACES_LUKS_MARKER_HOST]='web-2'
    [WORKSPACES_LUKS_SOAK_DAYS]='3'
  )
}

GATE_OUT=""
GATE_ERR=""
GATE_RC=0
run_with_def() {
  local -a args=()
  local k
  for k in "${!DEF[@]}"; do args+=("${k}=${DEF[$k]}"); done
  local out errfile
  errfile=$(mktemp)
  trap 'rm -f "$errfile"; trap - RETURN' RETURN  # (self-clearing: a RETURN trap is global, so an outer function returning later would otherwise re-fire it with $errfile out of scope) owning trap (ADR-129): errfile cleaned on every function return, even if `cat` fails
  out=$(env -i PATH="$PATH" "${args[@]}" bash "$GATE" 2>"$errfile") && GATE_RC=0 || GATE_RC=$?
  GATE_OUT="$out"
  GATE_ERR="$(cat "$errfile")"
}

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1 (rc=${GATE_RC})"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }

assert_zero()    { if [[ "$GATE_RC" -eq 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_nonzero() { if [[ "$GATE_RC" -ne 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_stdout_contains() {
  if [[ "$GATE_OUT" == *"$2"* ]]; then pass "$1"; else fail "$1 — stdout missing '$2'"; fi
}
# has_gate_fail <stderr-text> <id> — 0 iff a WHOLE line of the text is `gate_fail sub_condition=<id>` (#12849). The
# SOLEUR_SOAK_EVIDENCE line also carries `sub_condition=<id>`, so a substring check could pass on the evidence line
# alone; `^gate_fail sub_condition=` is the only refusal contract (the evidence line is non-authoritative).
has_gate_fail() { [[ $'\n'"$1"$'\n' == *$'\n'"gate_fail sub_condition=$2"$'\n'* ]]; }
assert_stderr_contains() {
  if has_gate_fail "$GATE_ERR" "$2"; then pass "$1"
  else fail "$1 — stderr has no whole line 'gate_fail sub_condition=$2' (got: ${GATE_ERR})"; fi
}
assert_rejects_with() {
  assert_nonzero "$1"
  assert_stderr_contains "$1 [sub_condition]" "$2"
}

echo "=== lb-weight-gate.sh test suite (rebuilt #6575 / ADR-143 D3) ==="

# =============================================================================
# §0 — TOP-GUARD (ADR-143 D3): the serving-weight polarity fix.
# =============================================================================

# 0a. THE #6575-FLAW FIX: the correct out-of-band standby state — web-2 weight==0, NOT in the
#     serving rotation — PASSES, even with NO valid flip-time roster/relay env at all (proving the
#     short-circuit runs BEFORE Condition A/B). A correct pre-flip config CAN pass this gate.
reset_def
DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'
DEF[SOLEUR_SERVING_ROTATION]=''            # explicit empty = "no rotation" (a SET, valid state)
unset 'DEF[SOLEUR_PROXY_PEER_ALLOWLIST]' 'DEF[SOLEUR_HOST_ROSTER]'
unset 'DEF[GIT_DATA_STORE_ENABLED]' 'DEF[GIT_DATA_LUKS_CUTOVER_AT]' 'DEF[WORKSPACES_LUKS_CUTOVER_AT]'
run_with_def
assert_zero "standby (weight=0, empty rotation, NO flip env) → exit 0 (fixes #6575 flaw)"
assert_stdout_contains "standby prints web2_standby=true" "web2_standby=true"

# 0b. Standby with a non-empty rotation that does NOT contain web-2 → still standby PASS.
reset_def
DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'
DEF[SOLEUR_SERVING_ROTATION]='web-1'
run_with_def
assert_zero "weight=0 + rotation without web-2 → standby exit 0"

# 0c. FAIL-CLOSED: absent serving-weight → FAIL (never default-0-PASS; CTO 2c.1).
reset_def; unset 'DEF[SOLEUR_WEB2_SERVING_WEIGHT]'; run_with_def
assert_rejects_with "absent SOLEUR_WEB2_SERVING_WEIGHT" "TOP_web2_weight_absent"
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]=''; run_with_def
assert_rejects_with "empty SOLEUR_WEB2_SERVING_WEIGHT" "TOP_web2_weight_absent"
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='   '; run_with_def
assert_rejects_with "whitespace-only weight (trims empty)" "TOP_web2_weight_absent"

# 0d. FAIL-CLOSED: non-integer weight must not coerce to 0 (CTO 2c.3 — pin the regex).
for badw in "0.0" "0x0" "false" "abc" "1.5" "1e0" "+"; do
  reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]="$badw"; run_with_def
  assert_rejects_with "non-integer weight '$badw' rejected" "TOP_web2_weight_not_integer"
done

# 0e. FAIL-CLOSED: negative weight → FAIL.
# #9421 Part 2a: the gate names no host; the gated key is an input, fail-closed when absent or malformed.
reset_def; unset 'DEF[SOLEUR_GATED_HOST]'; run_with_def
assert_rejects_with "absent SOLEUR_GATED_HOST" "TOP_gated_host_absent"
reset_def; DEF[SOLEUR_GATED_HOST]=''; run_with_def
assert_rejects_with "empty SOLEUR_GATED_HOST" "TOP_gated_host_absent"
for badh in 'Web-2' 'web 2' 'web-2;x' '-web' '.'; do
  reset_def; DEF[SOLEUR_GATED_HOST]="$badh"; run_with_def
  assert_rejects_with "malformed SOLEUR_GATED_HOST '$badh'" "TOP_gated_host_malformed"
done
# Third key: web-3 at weight 0 and out of rotation is the standby branch, whatever web-2 is doing.
reset_def; DEF[SOLEUR_GATED_HOST]='web-3'; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'; run_with_def
assert_zero "third key: web-3 at weight 0, not in rotation -> standby pass"
assert_stdout_contains "third key: standby branch prints SHAPE-ONLY" "SHAPE-ONLY"
# web-3 in rotation at weight 0 is pooling -> Conditions A+B, and the roster lacks web-3 -> refused.
reset_def; DEF[SOLEUR_GATED_HOST]='web-3'; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'; DEF[SOLEUR_SERVING_ROTATION]='web-1,web-2,web-3'; run_with_def
assert_rejects_with "third key: web-3 in rotation, absent from roster -> refused" "A_web2_not_in_roster"
# web-3 pooled with a roster + allowlist naming it -> the authorized-flip pass, keyed on web-3 not web-2.
# The workspaces LUKS marker is unkeyed and attests only its writer's host (web-2): web-3 cannot inherit it.
R13='{"web-1":"10.0.1.10","web-3":"10.0.1.12"}'
reset_def; DEF[SOLEUR_GATED_HOST]='web-3'; DEF[SOLEUR_SERVING_ROTATION]='web-1,web-3'; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.12'; DEF[SOLEUR_HOST_ROSTER]="$R13"; run_with_def
assert_rejects_with "third key: web-3 pooled on web-2's LUKS marker -> refused" "B_workspaces_luks_marker_other_host"
reset_def; unset 'DEF[WORKSPACES_LUKS_MARKER_HOST]'; run_with_def
assert_rejects_with "marker host unset (marker present) -> refused, never assumed" "B_workspaces_luks_marker_other_host"
# Same web-3 config with a marker that attests web-3 -> the authorized-flip pass, keyed on web-3 not web-2.
reset_def; DEF[SOLEUR_GATED_HOST]='web-3'; DEF[WORKSPACES_LUKS_MARKER_HOST]='web-3'; DEF[SOLEUR_SERVING_ROTATION]='web-1,web-3'; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.12'; DEF[SOLEUR_HOST_ROSTER]="$R13"; run_with_def
assert_zero "third key: web-3 pooled, in roster, addr allowlisted, marker attests web-3 -> authorized"
assert_stdout_contains "third key: authorized branch prints the flip marker" "requires_runtime_bind_probe=true"
# web-3 pooled, roster has it but its address is not allowlisted (web-2's is) -> refused on web-3's address.
reset_def; DEF[SOLEUR_GATED_HOST]='web-3'; DEF[SOLEUR_SERVING_ROTATION]='web-1,web-3'; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11","web-3":"10.0.1.12"}'; run_with_def
assert_rejects_with "third key: web-3 address not in the allowlist -> refused" "A_web2_addr_not_in_allowlist"
# The gate's code lines name no host key (comments may cite history).
TOTAL=$((TOTAL + 1))
if [[ "$(grep -vE '^[[:space:]]*#' "$GATE" | grep -cE 'web-[0-9]' || true)" -eq 0 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no code line of lb-weight-gate.sh names a web-N key"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: a code line of lb-weight-gate.sh names a web-N key literally"
fi
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='-1'; run_with_def
assert_rejects_with "negative weight" "TOP_web2_weight_negative"

# 0f. FAIL-CLOSED: UNSET rotation → FAIL (absent ≠ assume-empty→PASS; CTO 2c.2). An explicit empty
#     string is a valid "no rotation" (tested in 0a); only genuinely-unset reddens here.
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'; unset 'DEF[SOLEUR_SERVING_ROTATION]'; run_with_def
assert_rejects_with "unset SOLEUR_SERVING_ROTATION (weight=0)" "TOP_serving_rotation_absent"

# 0g. web-2 in the rotation set even at weight 0 = still POOLED → runs A/B (not standby). With a
#     valid A/B config → authorized-flip exit 0; the point is it did NOT short-circuit to standby.
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'; DEF[SOLEUR_SERVING_ROTATION]='web-1,web-2'; run_with_def
assert_zero "weight=0 but web-2 IN rotation + valid A/B → authorized-flip exit 0 (not standby)"
assert_stdout_contains "in-rotation path prints requires_runtime_bind_probe" "requires_runtime_bind_probe=true"

# 0h. AC7 (plan 3.5): web-2 serving-weight > 0 PRE-FLIP with unmet A/B → FAIL. THE regression case.
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='1'; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
assert_rejects_with "AC7: weight>0 pre-flip, git-data not cut over → FAIL" "B_git_data_store_disabled"
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='5'; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10"}'; run_with_def
assert_rejects_with "AC7: weight>0 pre-flip, roster omits web-2 → FAIL" "A_web2_not_in_roster"

# 0i. WEIGHT-TERM ISOLATION (mutation-vacuity fix): the standby short-circuit is `weight==0 &&
#     web-2∉rotation`. Every §0h/§1-8 pooling case has web-2 IN the rotation, so the WEIGHT half of
#     the AND was never isolated — dropping it (making the short-circuit `web-2∉rotation` alone)
#     stayed green while `weight=5, rotation=web-1` passed as "standby" (web-2 pooled at weight 5).
#     These two cases pin the weight term: web-2 weight>0 but NOT in the rotation set MUST still take
#     the pooling branch (run A/B), never the standby short-circuit.
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='3'; DEF[SOLEUR_SERVING_ROTATION]='web-1'; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
assert_rejects_with "0i: weight>0 + web-2 NOT in rotation + unmet A/B → FAIL (weight term isolated)" "B_git_data_store_disabled"
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='3'; DEF[SOLEUR_SERVING_ROTATION]='web-1'; run_with_def
assert_zero "0i: weight>0 + web-2 NOT in rotation + valid A/B → authorized-flip (NOT standby)"
assert_stdout_contains "0i: weight>0 path prints requires_runtime_bind_probe (not web2_standby)" "requires_runtime_bind_probe=true"

# =============================================================================
# §1 — Both conditions hold (web-2 being pooled) → authorized-flip exit 0 + SHAPE-ONLY marker.
# =============================================================================
reset_def; run_with_def
assert_zero "pooled + both conditions hold → exit 0"
assert_stdout_contains "success prints requires_runtime_bind_probe=true" "requires_runtime_bind_probe=true"
assert_stdout_contains "success prints SHAPE-ONLY banner" "SHAPE-ONLY"

# =============================================================================
# §2-5 — Condition A (owner-side relay config-shape). Reached because DEF pools web-2.
# =============================================================================
# A.1 (SOLEUR_PROXY_BIND non-empty) was DELETED (CTO ruling, #12167 / #8211, run 42418102446): the bind is
# not a Doppler value (the app container binds 0.0.0.0 via a literal in ci-deploy.sh, pinned by
# docker-run-tuple.py), so a Doppler "declared intent" proved nothing and refused a correctly configured
# fleet. The real bind proof is the relay_probe / relay_peer_probe evidence, not this shape gate. These rows
# pin that the gate neither reads nor refuses on it.
reset_def; run_with_def
assert_zero "SOLEUR_PROXY_BIND absent (the shipped relay design) does not refuse the pooled flip"
assert_stdout_contains "SOLEUR_PROXY_BIND absent: the pooled-flip path reaches the SHAPE-ONLY marker" "requires_runtime_bind_probe=true"
reset_def; DEF[SOLEUR_PROXY_BIND]=''; run_with_def
assert_zero "SOLEUR_PROXY_BIND set-but-empty does not refuse the pooled flip"
assert_stdout_contains "SOLEUR_PROXY_BIND set-but-empty: the pooled-flip path reaches the SHAPE-ONLY marker" "requires_runtime_bind_probe=true"
reset_def; DEF[SOLEUR_PROXY_BIND]='   '; run_with_def
assert_zero "SOLEUR_PROXY_BIND whitespace-only does not refuse the pooled flip"
assert_stdout_contains "SOLEUR_PROXY_BIND whitespace-only: the pooled-flip path reaches the SHAPE-ONLY marker" "requires_runtime_bind_probe=true"
reset_def; DEF[SOLEUR_PROXY_BIND]='10.0.1.10'; run_with_def
assert_zero "SOLEUR_PROXY_BIND set to a value is ignored (exit 0, same as absent)"
assert_stdout_contains "SOLEUR_PROXY_BIND set to a value: the pooled-flip path reaches the SHAPE-ONLY marker" "requires_runtime_bind_probe=true"

reset_def; unset 'DEF[SOLEUR_PROXY_PEER_ALLOWLIST]'; run_with_def
assert_rejects_with "SOLEUR_PROXY_PEER_ALLOWLIST missing" "A_peer_allowlist_empty"
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='  ,  '; run_with_def
assert_rejects_with "SOLEUR_PROXY_PEER_ALLOWLIST all-whitespace/commas parses empty" "A_peer_allowlist_empty"

reset_def; unset 'DEF[SOLEUR_HOST_ROSTER]'; run_with_def
assert_rejects_with "SOLEUR_HOST_ROSTER missing" "A_host_roster_empty"

reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-3":"10.0.1.11"}'; run_with_def
assert_rejects_with "roster without web-2 entry" "A_web2_not_in_roster"
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11","web-2":"10.0.1.99"}'; run_with_def
assert_rejects_with "roster duplicate key" "A_host_roster_duplicate_key"
reset_def; DEF[SOLEUR_HOST_ROSTER]='["10.0.1.10","10.0.1.11"]'; run_with_def
assert_rejects_with "roster non-object (array)" "A_host_roster_not_object"
reset_def; DEF[SOLEUR_HOST_ROSTER]='not json at all'; run_with_def
assert_rejects_with "roster invalid JSON" "A_host_roster_invalid_json"
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-2":"10.0.1.11","   ":"10.0.1.10"}'; run_with_def
assert_rejects_with "roster whitespace-only key" "A_host_roster_blank_key"
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"","web-2":"10.0.1.11"}'; run_with_def
assert_rejects_with "roster blank value" "A_host_roster_bad_value"

reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.11,10.9.9.9'; run_with_def
assert_rejects_with "allowlist peer not in roster addresses" "A_allowlist_not_subset_of_roster"
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.10'; run_with_def
assert_rejects_with "roster has web-2 but allowlist omits its dial address" "A_web2_addr_not_in_allowlist"

# =============================================================================
# §6 — Condition B (git-data cut-over config-shape).
# =============================================================================
reset_def; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
assert_rejects_with "GIT_DATA_STORE_ENABLED=false" "B_git_data_store_disabled"
reset_def; unset 'DEF[GIT_DATA_LUKS_CUTOVER_AT]'; run_with_def
assert_rejects_with "git-data LUKS cutover marker absent" "B_luks_cutover_marker_absent"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='not-a-timestamp'; run_with_def
assert_rejects_with "git-data LUKS cutover marker unparseable" "B_luks_cutover_marker_unparseable"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='2026-13-45T99:99:99Z'; run_with_def
assert_rejects_with "git-data marker garbage-but-ISO-shaped" "B_luks_cutover_marker_unparseable"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FUTURE_CUTOVER"; run_with_def
assert_rejects_with "git-data marker future-dated" "B_luks_cutover_marker_future"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='1960-01-01'; run_with_def
assert_rejects_with "git-data marker pre-1970 (negative epoch)" "B_luks_cutover_marker_pre_epoch"
reset_def; DEF[GIT_DATA_LUKS_SOAK_DAYS]='0'; run_with_def
assert_rejects_with "GIT_DATA_LUKS_SOAK_DAYS=0 (floor)" "B_luks_soak_days_invalid"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_rejects_with "git-data soak not elapsed (1d < 3d)" "B_luks_soak_not_elapsed"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$NOW_CUTOVER"; run_with_def
assert_rejects_with "git-data soak boundary delta==0 (marker==now)" "B_luks_soak_not_elapsed"

# =============================================================================
# §6459 — Condition B WORKSPACES_LUKS precondition (ADR-143 D3 coupling #2). A plaintext web-2
#          cannot be pooled: the flip reddens unless web-2 /workspaces is asserted LUKS-backed.
# =============================================================================
reset_def; unset 'DEF[WORKSPACES_LUKS_CUTOVER_AT]'; run_with_def
assert_rejects_with "workspaces LUKS marker absent → plaintext web-2 cannot flip" "B_workspaces_luks_marker_absent"
reset_def; DEF[WORKSPACES_LUKS_CUTOVER_AT]='not-a-timestamp'; run_with_def
assert_rejects_with "workspaces LUKS marker unparseable" "B_workspaces_luks_marker_unparseable"
reset_def; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$FUTURE_CUTOVER"; run_with_def
assert_rejects_with "workspaces LUKS marker future-dated" "B_workspaces_luks_marker_future"
reset_def; DEF[WORKSPACES_LUKS_CUTOVER_AT]='1960-01-01'; run_with_def
assert_rejects_with "workspaces LUKS marker pre-1970" "B_workspaces_luks_marker_pre_epoch"
reset_def; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_rejects_with "workspaces LUKS soak not elapsed (1d < 3d)" "B_workspaces_luks_soak_not_elapsed"
reset_def; DEF[WORKSPACES_LUKS_SOAK_DAYS]='0'; run_with_def
assert_rejects_with "WORKSPACES_LUKS_SOAK_DAYS=0 (floor)" "B_workspaces_luks_soak_days_invalid"

# =============================================================================
# §8 — Positive-tolerance / boundary cases — an OVER-strict regression goes RED here.
# =============================================================================
reset_def; unset 'DEF[GIT_DATA_LUKS_SOAK_DAYS]' 'DEF[WORKSPACES_LUKS_SOAK_DAYS]'; run_with_def
assert_zero "default soak days (3) with 4d-elapsed markers → exit 0"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$BOUNDARY_CUTOVER"; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$BOUNDARY_CUTOVER"; run_with_def
assert_zero "soak boundary (markers exactly 3d old) → exit 0"
reset_def
DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11","web-3":"10.0.1.12"}'
DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.10,10.0.1.11'
run_with_def
assert_zero "roster with extra host + allowlist all-in-roster (web-2 addr present) → exit 0"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$TZOFFSET_CUTOVER"; run_with_def
assert_zero "tz-offset (+02:00) git-data cutover marker accepted & elapsed → exit 0"

# =============================================================================
# §C — Condition C: STATIC committed-HCL anti-pooling assertions (CTO ruling 2b). The env-driven
#      gate above cannot catch an accidental COMMIT that pools web-2 — the actual single-user-
#      incident vector. These grep the REAL .tf tree; fail-closed on parse failure (file moved).
# =============================================================================
assert_grep() { # $1=desc $2=file $3=ERE that MUST match
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$SCRIPT_DIR/$2" ]]; then FAIL=$((FAIL + 1)); echo "  FAIL: $1 — $2 not found (fail-closed)"; return; fi
  if grep -qE "$3" "$SCRIPT_DIR/$2"; then PASS=$((PASS + 1)); echo "  PASS: $1"; else FAIL=$((FAIL + 1)); echo "  FAIL: $1 — no match for /$3/ in $2"; fi
}
assert_no_grep() { # $1=desc $2=file $3=ERE that must NOT match
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$SCRIPT_DIR/$2" ]]; then FAIL=$((FAIL + 1)); echo "  FAIL: $1 — $2 not found (fail-closed)"; return; fi
  if grep -qE "$3" "$SCRIPT_DIR/$2"; then FAIL=$((FAIL + 1)); echo "  FAIL: $1 — unexpected match for /$3/ in $2 (web-2 pooled?)"; else PASS=$((PASS + 1)); echo "  PASS: $1"; fi
}

# C.1 — the app A record (ingress) resolves to web-1 ONLY. The `cloudflare_record.app` content must
#       reference hcloud_server.web["web-1"] and NOT ["web-2"].
assert_grep    "C.1a: dns.tf app record content = hcloud_server.web[\"web-1\"]" dns.tf \
  'content[[:space:]]*=[[:space:]]*hcloud_server\.web\["web-1"\]\.ipv4_address'
# C.1b (V2 fix): EXACTLY ONE `name = "app"` A-record exists. C.1a alone only proves THE web-1 app
# record is present; it cannot see a SECOND `app` A-record round-robining ~50% of app.soleur.ai
# ingress to web-2 by a NON-literal reference (hardcoded IP, var.*, for_each) — that defeats a
# grep for the known-bad `["web-2"]` literal. Counting the record closes the vacuity.
TOTAL=$((TOTAL + 1))
if [[ ! -f "$SCRIPT_DIR/dns.tf" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: C.1b — dns.tf not found (fail-closed)"
else
  app_records=$(grep -cE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"app"[[:space:]]*$' "$SCRIPT_DIR/dns.tf") || true
  if [[ "$app_records" -eq 1 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: C.1b: exactly one 'name = \"app\"' record in dns.tf (no second pooling record)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: C.1b: found $app_records 'name = \"app\"' records in dns.tf (expected 1 — a second app A-record would pool web-2)"
  fi
fi
assert_no_grep "C.1c: dns.tf does NOT reference hcloud_server.web[\"web-2\"] (literal defense-in-depth)" dns.tf \
  'hcloud_server\.web\["web-2"\]'

# C.2 — the single tunnel connector predicate gates registration to web-2 (each.key=="web-2").
#       The connector moved off web-1 permanently (LUKS-pinned, `web-host-replace` refuses it —
#       it could never carry the cloudflared >= 2026.10.2 eMudhra fix). A connector on web-2 is
#       NOT pooling: it serves management-plane ingress only, proxying to the origin-relative
#       private IPs (deploy./ssh. → web-1's 10.0.1.10, registry. → 10.0.1.30) — it puts no
#       app.soleur.ai weight on web-2. The predicate's pin matters the other way now: exactly
#       ONE host registers (ADR-114 I1), and it must be the replaceable one.
# #9421 Part 2a: the predicate is the keyed field (validated exactly-one in variables.tf), and web-2 holds it.
assert_grep    "C.2: server.tf tunnel connector predicate is the keyed tunnel_connector field" server.tf \
  '^[[:space:]]*web_tunnel_connector[[:space:]]*=[[:space:]]*each\.value\.tunnel_connector[[:space:]]*$'
assert_grep    "C.2b: var.web_hosts gives tunnel_connector = true to web-2" variables.tf \
  '^[[:space:]]*"web-2"[[:space:]]*=[[:space:]]*\{.*tunnel_connector[[:space:]]*=[[:space:]]*true'
assert_grep    "C.2c: variables.tf validates exactly one tunnel_connector host" variables.tf \
  'length\(\[for h in values\(var\.web_hosts\) : h if h\.tunnel_connector\]\)[[:space:]]*==[[:space:]]*1'

# C.3 — DRAINED-SHAPE invariant (2026-11-01 rewrite, replaces structural absence;
#       pairing/anchoring hardened PR #11766). With web-2 pooled as a GATED member
#       (ADR-068 §(b); live serves at weight 1 since the 2026-11-08 serve flip, so the
#       member's weight is the literal 0 or exactly the gated variable, never another
#       expression), the assertion is BLOCK-SCOPE over the .tf files that declare a
#       cloudflare_load_balancer* resource:
#         * every `origins {}` block that points at web-2 — by `name = "web-2"` OR by
#           an `hcloud_server.web["web-2"]` reference ANYWHERE in the block (so a
#           renamed origin cannot dodge the pin) — must carry `weight = 0` where the
#           0 is RIGHT-ANCHORED (space/#/EOL after it — `weight = 0.5` must not
#           satisfy a prefix match);
#         * outside `origins {}` blocks, an `hcloud_server.web["web-2"]` reference
#           ANYWHERE on a line (attribute-assigned, not line-anchored) or a line-
#           anchored `name = "web-2"` is a STRAY — a web-2 pool/record smuggle is
#           not a drained origin.
#       What it pins, stated precisely (the earlier comment overstated it): it does
#       NOT match label references like `default_pool_ids` entries — those name
#       `cloudflare_load_balancer_pool.<label>` resources, not `hcloud_server.web`.
#       It pins the ORIGIN-SIDE shape: web-2 can only be reached as a weight-0
#       origin of a declared pool, never via a stray web-2-addressed construct.
#       The weight pairing is awk-ranged over the `origins {}` block — never a
#       bare line-grep, which a dropped `weight` term would satisfy silently.
#       Glob $SCRIPT_DIR explicitly (terraform-cwd class). Fail-closed: zero .tf
#       files = FAIL.
# c3_scan_file <file> -> "<bad_blocks> <w2_blocks> <stray>" — ONE helper so the
# synthetic fixtures below grade the SHIPPED logic, not a copy of it.
c3_scan_file() {
  local f="$1" bad=0 blocks=0 stray
  while IFS='|' read -r has_w2 has_w0; do
    [[ "$has_w2" == "1" ]] || continue
    blocks=$((blocks + 1))
    [[ "$has_w0" == "1" ]] || bad=$((bad + 1))
  done < <(awk '
    # Open of an origins block: the OPEN LINE itself is inspected too — a
    # single-line `origins { name = "web-2" }` used to scan 0 0 0 (invisible to
    # both the block census and the stray census). Braces are a DEPTH counter,
    # not a boolean: a nested `header {}` must not close the scan early and
    # misattribute the lines after it. The `next` here keeps a nested `origins`
    # line inside a block on the depth>0 path (it deepens, never re-opens).
    depth == 0 && /^[[:space:]]*origins[[:space:]]*\{/ {
      w2 = ($0 ~ /name[[:space:]]*=[[:space:]]*"web-2"/ || $0 ~ /hcloud_server\.web\["web-2"\]/) ? 1 : 0
      # weight on the open line can only sit INLINE (after `origins {`), so the
      # right-anchored-0 pattern is applied unanchored here; inside-line weight
      # stays line-anchored below.
      w0 = ($0 ~ /weight[[:space:]]*=[[:space:]]*(0([[:space:]]|#|$)|var\.web2_lb_weight[[:space:]]*(#|\}|$))/) ? 1 : 0
      line = $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      if (depth <= 0) printf "%s|%s\n", w2, w0
      next
    }
    # A `}`-led line is a close, not content — a trailing comment cannot
    # mint an origin member (same rule the boolean scan enforced).
    depth > 0 && /^[[:space:]]*\}/ {
      line = $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      if (depth <= 0) printf "%s|%s\n", w2, w0
      next
    }
    depth > 0 {
      if ($0 ~ /name[[:space:]]*=[[:space:]]*"web-2"/ || $0 ~ /hcloud_server\.web\["web-2"\]/) w2 = 1
      if ($0 ~ /^[[:space:]]*weight[[:space:]]*=[[:space:]]*(0([[:space:]]|#|$)|var\.web2_lb_weight[[:space:]]*(#|\}|$))/) w0 = 1
      line = $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      if (depth <= 0) printf "%s|%s\n", w2, w0
      next
    }
  ' "$f")
  stray=$(awk '
    # Same depth discipline: "outside" is depth==0 AND not an origins open line;
    # an origins block closes only when its OWN depth returns to 0.
    depth == 0 && /^[[:space:]]*origins[[:space:]]*\{/ {
      line = $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      next
    }
    depth > 0 {
      line = $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      next
    }
    ($0 ~ /hcloud_server\.web\["web-2"\]/ || $0 ~ /^[[:space:]]*name[[:space:]]*=[[:space:]]*"web-2"/) { n++ }
    END { print n+0 }
  ' "$f")
  printf '%s %s %s\n' "$bad" "$blocks" "$stray"
}
# #9421 Part 2a: the pool's origins are ONE dynamic block over var.web_hosts at local.web_lb_weights, where
# web-2's gated weight is min(declared lb_weight, var.web2_lb_weight) — so the drain still lands on web-2 and a
# gate can only lower a weight. c3_dynamic_ok pins that shape; C.3-dyn below mutation-proves it.
c3_dynamic_ok() { # c3_dynamic_ok <cloudflare-lb.tf> -> 0 iff the dynamic origins + min-gate shape holds
  local f="$1" nc
  nc="$(grep -vE '^[[:space:]]*#' "$f" || true)"  # all-comment file: empty, and the checks below refuse
  [[ "$(grep -cE '^[[:space:]]*dynamic[[:space:]]+"origins"[[:space:]]*\{' <<<"$nc")" -eq 1 ]] || return 1
  [[ "$(grep -cE '^[[:space:]]*origins[[:space:]]*\{' <<<"$nc")" -eq 0 ]] || return 1
  grep -qE '^[[:space:]]*for_each[[:space:]]*=[[:space:]]*var\.web_hosts[[:space:]]*$' <<<"$nc" || return 1
  grep -qE '^[[:space:]]*weight[[:space:]]*=[[:space:]]*local\.web_lb_weights\[origins\.key\][[:space:]]*$' <<<"$nc" || return 1
  grep -qE '^[[:space:]]*web_lb_gate[[:space:]]*=[[:space:]]*\{[[:space:]]*"web-2"[[:space:]]*=[[:space:]]*var\.web2_lb_weight[[:space:]]*\}[[:space:]]*$' <<<"$nc" || return 1
  grep -qF 'k => min(h.lb_weight, lookup(local.web_lb_gate, k, h.lb_weight))' <<<"$nc" || return 1
  return 0
}
C3D_TMP="$(mktemp -d)"
c3d() { # c3d <label> <from> <to> -> mutate a copy; must land and go red
  python3 - "$SCRIPT_DIR/cloudflare-lb.tf" "$C3D_TMP/m.tf" "$2" "$3" <<'PYM'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
open(dst, "w").write(s.replace(a, b, 1) if a in s else s)
PYM
  TOTAL=$((TOTAL + 1))
  if cmp -s "$SCRIPT_DIR/cloudflare-lb.tf" "$C3D_TMP/m.tf"; then FAIL=$((FAIL + 1)); echo "  FAIL: $1: mutation did not land"
  elif c3_dynamic_ok "$C3D_TMP/m.tf"; then FAIL=$((FAIL + 1)); echo "  FAIL: $1 stayed GREEN"
  else PASS=$((PASS + 1)); echo "  PASS: $1 -> RED"; fi
}
TOTAL=$((TOTAL + 1))
if c3_dynamic_ok "$SCRIPT_DIR/cloudflare-lb.tf"; then PASS=$((PASS + 1)); echo "  PASS: C.3-dyn control: dynamic origins over var.web_hosts at the min-gated weight"; else FAIL=$((FAIL + 1)); echo "  FAIL: C.3-dyn control: the dynamic origins / min-gate shape is not intact"; fi
c3d "C.3-dyn mutant: the gate raises instead of lowering (max)" 'min(h.lb_weight, lookup' 'max(h.lb_weight, lookup'
c3d "C.3-dyn mutant: the gate is bypassed (declared weight only)" 'k => min(h.lb_weight, lookup(local.web_lb_gate, k, h.lb_weight))' 'k => h.lb_weight'
c3d "C.3-dyn mutant: the drain var is detached from web-2" '"web-2" = var.web2_lb_weight' '"web-3" = var.web2_lb_weight'
c3d "C.3-dyn mutant: origins weight hardcoded to 1" 'weight  = local.web_lb_weights[origins.key]' 'weight  = 1'
c3d "C.3-dyn mutant: a literal origins block is re-added" '  dynamic "origins" {' '  origins {
    name = "x"
  }
  dynamic "origins" {'
rm -rf "$C3D_TMP"

web2_bad_blocks=0; web2_blocks=0; web2_stray=0; tf_seen=0
for f in "$SCRIPT_DIR"/*.tf; do
  [[ -f "$f" ]] || continue
  tf_seen=$((tf_seen + 1))
  grep -qE 'resource[[:space:]]+"cloudflare_load_balancer' "$f" || continue
  read -r f_bad f_blocks f_stray < <(c3_scan_file "$f")
  web2_bad_blocks=$((web2_bad_blocks + f_bad))
  web2_blocks=$((web2_blocks + f_blocks))
  web2_stray=$((web2_stray + f_stray))
done
TOTAL=$((TOTAL + 1))
if [[ "$tf_seen" -lt 1 ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: C.3-sweep: no .tf files found under $SCRIPT_DIR (fail-closed — dir moved?)"
elif [[ "$web2_blocks" -lt 1 ]] && ! c3_dynamic_ok "$SCRIPT_DIR/cloudflare-lb.tf"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: C.3-sweep: no origins block names web-2 and the dynamic origins shape (#9421) is not intact — the web-2 member is missing (assertions must not vacuously pass)"
elif [[ "$web2_bad_blocks" -gt 0 || "$web2_stray" -gt 0 ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: C.3-sweep: $web2_bad_blocks web-2 origins block(s) without 'weight = 0' or exactly var.web2_lb_weight + $web2_stray stray web-2 reference(s) outside origins blocks — web-2's weight must stay the literal 0 or the gated variable"
else
  PASS=$((PASS + 1)); echo "  PASS: C.3-sweep: $web2_blocks web-2 origins block(s) at weight = 0 or var.web2_lb_weight, no stray web-2 references — gated member holds"
fi

# C.3-fixtures — synthetic .tf driving the SHIPPED c3_scan_file (PR #11766 review:
# the `weight = 0.5` prefix-match bypass and the renamed-origin escape were both
# measured green). Assert on the helper's <bad blocks stray> triple.
C3_TMP="$(mktemp -d)"
c3_fixture() { # $1=name $2=hcl -> runs c3_scan_file, echoes the triple into C3_OUT
  printf '%s\n' "$2" > "$C3_TMP/$1.tf"
  C3_OUT="$(c3_scan_file "$C3_TMP/$1.tf")"
}
assert_c3() { # $1=desc $2=expected "<bad> <blocks> <stray>"
  TOTAL=$((TOTAL + 1))
  if [[ "$C3_OUT" == "$2" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $1 — expected '$2', got '$C3_OUT'"
  fi
}
c3_fixture good 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    address = hcloud_server.web["web-2"].ipv4_address
    enabled = true
    weight  = 0
  }
}'
assert_c3 "C.3-fixture: well-formed drained member (weight = 0) scans clean" "0 1 0"
c3_fixture half 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    address = hcloud_server.web["web-2"].ipv4_address
    enabled = true
    weight  = 0.5
  }
}'
assert_c3 "C.3-fixture: weight = 0.5 is NOT drained (right-anchored 0) → red" "1 1 0"
c3_fixture renamed 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "standby"
    address = hcloud_server.web["web-2"].ipv4_address
    enabled = true
    weight  = 1
  }
}'
assert_c3 "C.3-fixture: renamed origin still resolving web-2 IP pairs by address → red" "1 1 0"
c3_fixture missing 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    address = hcloud_server.web["web-2"].ipv4_address
    enabled = true
  }
}'
assert_c3 "C.3-fixture: web-2 origins block with no weight term → red" "1 1 0"
c3_fixture stray 'resource "cloudflare_load_balancer" "app" {
  zone_id          = var.cf_zone_id
  fallback_pool_id = hcloud_server.web["web-2"].ipv4_address
}'
assert_c3 "C.3-fixture: hcloud_server.web[\"web-2\"] attribute-assigned outside origins → stray" "0 0 1"
# Single-line blocks: the open line's own content must be scanned — a one-line
# origins block used to read as 0 0 0 (invisible to BOTH censuses).
c3_fixture oneline 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins { name = "web-2" }
}'
assert_c3 "C.3-fixture: single-line web-2 origins block without weight → red" "1 1 0"
c3_fixture oneline_ok 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins { name = "web-2" weight = 0 }
}'
assert_c3 "C.3-fixture: single-line drained member scans clean" "0 1 0"
c3_fixture oneline_hot 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins { name = "web-2" weight = 1 }
}'
assert_c3 "C.3-fixture: single-line hot web-2 member → red" "1 1 0"
# Nested blocks must not close the origins scan early: a `header {}` inside
# origins used to end the block at its own `}`, orphaning every line after it
# (weight unscanned, name misattributed to the stray census).
c3_fixture nested 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    check_response {
      header { name = "x" }
    }
    name    = "web-2"
    weight  = 0
  }
}'
assert_c3 "C.3-fixture: nested block does not close the origins scan early" "0 1 0"
c3_fixture nested_hot 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    check_response {
      header { name = "x" }
    }
    name    = "web-2"
    weight  = 1
  }
}'
assert_c3 "C.3-fixture: nested block + hot web-2 member still → red" "1 1 0"
# Gated-variable weight term (serve-arm prep): web-2's weight may be the literal 0 OR exactly
# var.web2_lb_weight (whose default is 1 = live and whose explicit-0 feeders are the drain arm and ga-overlay — C.4 below).
# Any other expression is not a drained member.
c3_fixture varok 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    weight  = var.web2_lb_weight
  }
}'
assert_c3 "C.3-fixture: weight = var.web2_lb_weight scans clean (gated variable: validation admits only 0 or 1)" "0 1 0"
c3_fixture varsuffix 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    weight  = var.web2_lb_weight + 1
  }
}'
assert_c3 "C.3-fixture: weight = var.web2_lb_weight + 1 is NOT the gated variable → red" "1 1 0"
c3_fixture varprefix 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    weight  = var.web2_lb_weight_extra
  }
}'
assert_c3 "C.3-fixture: weight = var.web2_lb_weight_extra (prefix) → red" "1 1 0"
c3_fixture varother 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    weight  = var.some_other_weight
  }
}'
assert_c3 "C.3-fixture: weight = var.<other> → red (only the gated variable is admitted)" "1 1 0"
c3_fixture varoneline 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins { name = "web-2" weight = var.web2_lb_weight }
}'
assert_c3 "C.3-fixture: single-line web-2 member on the gated variable scans clean" "0 1 0"
rm -rf "$C3_TMP"

# =============================================================================
# C.4 — the web-2 LB weight is a GATED VARIABLE (serve-arm prep).
#
# cloudflare-lb.tf feeds web-2's origin weight from var.web2_lb_weight so the cf-lb-overlay.yml
# `ga-pool-update mode=serve` arm CAN succeed (a hard-coded 0 made the arm structurally unable to
# flip). The invariants that keep this exactly as safe as the literal 0 was:
#   V   the variable's DEFAULT is 1 (the live serving shape; the default plan is a no-op against live) and it admits only {0,1};
#   F   the only feeders in the whole tree are the two plan steps of cf-lb-overlay.yml: ga_pool_update
#       (1 only when mode=serve, else an explicit 0) and ga_overlay (an explicit literal 0, so a fresh
#       GA3 create stays drained); every other path (routine apply, drift plan, laptop plan) rides the
#       default, which equals live (1);
#   O   the serve value can only be planned AFTER the §(c) gate chain step passed (fail-closed
#       step, `if: serve`, no continue-on-error), and the gate is evaluated on the SAME number
#       that is planned (SOLEUR_WEB2_SERVING_WEIGHT=$WEB2_LB_WEIGHT);
#   G   the gate, fed exactly what the arm injects, still refuses every unmet precondition.
# =============================================================================
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/cf-lb-overlay.yml"
c4_ok()  { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; }
c4_bad() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  FAIL: $1"; }
c4_assert() { # $1=desc $2=0|1 (1 = condition holds)
  if [[ "$2" == "1" ]]; then c4_ok "$1"; else c4_bad "$1"; fi
}
# Comment-stripped text (a `#` comment line can neither satisfy nor trip a pin).
c4_nocomment() { grep -vE '^[[:space:]]*#' "$1"; }

# --- V: the variable declaration -------------------------------------------------------------
VARS_TF="$SCRIPT_DIR/variables.tf"
V_BLOCK=""
[[ -f "$VARS_TF" ]] && V_BLOCK="$(awk '
  /^variable[[:space:]]+"web2_lb_weight"[[:space:]]*\{/ { on = 1 }
  on { print }
  on && /^\}/ { exit }
' "$VARS_TF")"
c4_assert "C.4-V1: variables.tf declares variable \"web2_lb_weight\"" "$([[ -n "$V_BLOCK" ]] && echo 1 || echo 0)"
v2_guard() { # $1 = the variable block text -> 0 iff type number AND exactly one top-level default attribute AND it is 1
  grep -qE '^[[:space:]]*type[[:space:]]*=[[:space:]]*number[[:space:]]*$' <<<"$1" || return 1
  [[ "$(grep -cE '^[[:space:]]*default[[:space:]]*=' <<<"$1" || true)" -eq 1 ]] || return 1
  grep -qE '^[[:space:]]*default[[:space:]]*=[[:space:]]*1[[:space:]]*$' <<<"$1"
}
c4_assert "C.4-V2: web2_lb_weight is type = number with exactly ONE default attribute, equal to 1 (the live serving shape; a duplicate or heredoc 'default = 1' line cannot stand in for it)" \
  "$(v2_guard "$V_BLOCK" && echo 1 || echo 0)"
c4_assert "C.4-V3: web2_lb_weight has a validation admitting ONLY 0 or 1" \
  "$(grep -qE 'validation[[:space:]]*\{' <<<"$V_BLOCK" && grep -qE 'condition[[:space:]]*=[[:space:]]*var\.web2_lb_weight[[:space:]]*==[[:space:]]*0[[:space:]]*\|\|[[:space:]]*var\.web2_lb_weight[[:space:]]*==[[:space:]]*1[[:space:]]*$' <<<"$V_BLOCK" && echo 1 || echo 0)"
c4_assert "C.4-V4: web2_lb_weight is declared exactly once in the tree's .tf files" \
  "$([[ "$(grep -hE '^variable[[:space:]]+"web2_lb_weight"' "$SCRIPT_DIR"/*.tf | wc -l)" -eq 1 ]] && echo 1 || echo 0)"
c4_assert "C.4-V5: cloudflare-lb.tf feeds web-2's origin weight from var.web2_lb_weight (the web_lb_gate local, #9421)" \
  "$(grep -qE '^[[:space:]]*web_lb_gate[[:space:]]*=[[:space:]]*\{[[:space:]]*"web-2"[[:space:]]*=[[:space:]]*var\.web2_lb_weight[[:space:]]*\}[[:space:]]*$' "$SCRIPT_DIR/cloudflare-lb.tf" && echo 1 || echo 0)"
c4_assert "C.4-V6: web-1's declared lb_weight stays the literal 1 and no gate variable names web-1" \
  "$(grep -qE '^[[:space:]]*"web-1"[[:space:]]*=[[:space:]]*\{.*lb_weight[[:space:]]*=[[:space:]]*1[,[:space:]]' "$SCRIPT_DIR/variables.tf" && ! grep -qE 'web_lb_gate[[:space:]]*=.*"web-1"' "$SCRIPT_DIR/cloudflare-lb.tf" && echo 1 || echo 0)"

# --- F: the feeder census ---------------------------------------------------------------------
# Every file in the live tree that names the variable, minus this test and the knowledge base.
FEEDERS="$(cd "$REPO_ROOT" && grep -rIl 'web2_lb_weight' .github apps scripts plugins tests 2>/dev/null \
  | grep -vE '(^|/)node_modules/' | grep -vE '^apps/web-platform/infra/lb-weight-gate\.test\.sh$' \
  | grep -vE '^apps/web-platform/infra/web-hosts-generic\.test\.sh$' | LC_ALL=C sort | tr '\n' ' ' || true)"
# (web-hosts-generic.test.sh is exempt: it passes -var web2_lb_weight=0 only to its own isolated console root,
#  never to a plan of this root, so it feeds no real plan.)
c4_assert "C.4-F1: only variables.tf, cloudflare-lb.tf and cf-lb-overlay.yml name web2_lb_weight (got: ${FEEDERS})" \
  "$([[ "$FEEDERS" == ".github/workflows/cf-lb-overlay.yml apps/web-platform/infra/cloudflare-lb.tf apps/web-platform/infra/variables.tf " ]] && echo 1 || echo 0)"
c4_assert "C.4-F2: no tfvars / auto.tfvars / TF_VAR_web2_lb_weight supplies the variable anywhere in the tree" \
  "$([[ -z "$(cd "$REPO_ROOT" && grep -rIlE 'TF_VAR_web2_lb_weight|WEB2_LB_WEIGHT' .github apps scripts plugins tests 2>/dev/null | grep -vE '(^|/)node_modules/' | grep -vE '^(\.github/workflows/cf-lb-overlay\.yml|apps/web-platform/infra/lb-weight-gate\.test\.sh)$')" ]] && echo 1 || echo 0)"

# The ga_pool_update job and its steps (2-space job key, 6-space `- name:` steps).
JOB="$(awk '/^  ga_pool_update:/ {on=1; print; next} on && /^  [A-Za-z0-9_-]+:/ {exit} on {print}' "$WF" 2>/dev/null || true)"
step_of() { # $1 = ERE matched against the step's `- name:` line
  PAT="$1" awk '
    /^      - / { if (on) exit; if ($0 ~ /^      - name:/ && $0 ~ ENVIRON["PAT"]) on = 1 }
    on { print }
  ' <<<"$JOB"
}
line_of() { # $1 = ERE on the `- name:` line -> line number inside $JOB (0 if absent)
  local n; n="$(grep -nE "^      - name:.*($1)" <<<"$JOB" | head -1 | cut -d: -f1 || true)"; echo "${n:-0}"
}
PIN_STEP="$(step_of 'Typo-guard' || true)"
GATE_STEP="$(step_of '§\(c\) gate chain')"
PLAN_STEP="$(step_of 'Terraform plan \(GA pool')"
c4_assert "C.4-F3: ga_pool_update job and its pin / gate-chain / plan steps are all found (non-vacuity)" \
  "$([[ -n "$JOB" && -n "$PIN_STEP" && -n "$GATE_STEP" && -n "$PLAN_STEP" ]] && echo 1 || echo 0)"
c4_assert "C.4-F4: WEB2_LB_WEIGHT is 1 ONLY when mode=serve, else 0 (the pin step)" \
  "$(grep -qE 'if \[\[ "\$MODE_RAW" == "serve" \]\]; then WEB2_LB_WEIGHT=1; else WEB2_LB_WEIGHT=0; fi' <<<"$PIN_STEP" && grep -qE 'echo "WEB2_LB_WEIGHT=\$\{WEB2_LB_WEIGHT\}" >> "\$GITHUB_ENV"' <<<"$PIN_STEP" && echo 1 || echo 0)"
c4_assert "C.4-F5: the plan step passes -var=web2_lb_weight from WEB2_LB_WEIGHT, exactly once" \
  "$([[ "$(c4_nocomment <(printf '%s\n' "$PLAN_STEP") | grep -cE -- '-var="web2_lb_weight=\$\{WEB2_LB_WEIGHT\}"')" -eq 1 ]] && echo 1 || echo 0)"
f6_guard() { [[ "$(c4_nocomment "$1" | grep -o 'web2_lb_weight' | wc -l)" -eq 2 ]]; }
c4_assert "C.4-F6: web2_lb_weight appears TWICE in the non-comment text of cf-lb-overlay.yml: the ga_pool_update plan step (\${WEB2_LB_WEIGHT}) and the ga_overlay plan step (literal 0); no other arm / job feeds it" \
  "$(f6_guard "$WF" && echo 1 || echo 0)"
c4_assert "C.4-F7: no other workflow names web2_lb_weight (routine apply, drift and validation plans ride the default, 1 = live)" \
  "$([[ -z "$(cd "$REPO_ROOT" && grep -lE 'web2_lb_weight|WEB2_LB_WEIGHT' .github/workflows/*.yml | grep -v 'cf-lb-overlay.yml')" ]] && echo 1 || echo 0)"

# --- F8: ga_overlay (GA3 fresh create) passes an EXPLICIT web2_lb_weight=0 (#12363) ---------------------
# The default is 1, so without this line a fresh ga-overlay create would plan web-2 at weight 1 and its own
# grader (cf_lb_gate_ga, which pins the drained two-member shape) would refuse the plan. F8 reads the ga_overlay
# plan step through its OWN extractor (the ga_pool_update helpers above are keyed on a different job) and
# pins a literal 0, exactly once, on a non-comment line.
gao_plan_of() { # $1 = workflow file -> the "Terraform plan (GA LB trio only)" step of the ga_overlay job
  awk '/^  ga_overlay:/ {job=1; next} job && /^  [A-Za-z0-9_-]+:/ {exit}
       job && /^      - / { if (on) exit; if ($0 ~ /^      - name: Terraform plan \(GA LB trio only\)/) on = 1 }
       job && on { print }' "$1" 2>/dev/null || true
}
gao_guard() { # $1 = workflow file -> 0 iff the token -var="web2_lb_weight=0" sits INSIDE the terraform-plan continuation chain, once, and nothing else in the step names the variable
  local step nc chain; step="$(gao_plan_of "$1")"
  [[ -n "$step" ]] || return 1
  nc="$(c4_nocomment <(printf '%s\n' "$step"))"
  # exactly ONE terraform-plan COMMAND (a line that STARTS with it; an echo or a second plan is not "the" plan)
  [[ "$(grep -cE '^[[:space:]]*terraform plan' <<<"$nc" || true)" -eq 1 ]] || return 1
  # the chain: from that line through the last line that ends in a continuation backslash; the literal must sit
  # before the first pipe (an argument of terraform, not of the redactor that follows it)
  chain="$(awk '/^[[:space:]]*terraform plan/ {on=1} on {print} on && !/\\[[:space:]]*$/ {exit}' <<<"$nc")"
  [[ -n "$chain" ]] || return 1
  [[ "$(grep -o -- '-var="web2_lb_weight=0"' <<<"${chain%%|*}" | wc -l)" -eq 1 ]] || return 1
  # occurrences (not lines) anywhere in the step: a dead-line, echo or duplicate -var (last value wins) is a second one
  [[ "$(grep -o 'web2_lb_weight' <<<"$nc" | wc -l)" -eq 1 ]] || return 1
  return 0
}
c4_assert "C.4-F8: the ga_overlay plan command carries -var=\"web2_lb_weight=0\" exactly once inside its terraform-plan argument chain, and nothing else in the step names the variable: a fresh GA3 create stays drained under default 1" \
  "$(gao_guard "$WF" && echo 1 || echo 0)"
F8_WORK="$(mktemp -d)"
f8mut() { # f8mut <label> <awk-program> — mutate a copy of the workflow; it must LAND and F8's guard must go red
  local label="$1" prog="$2" f="$F8_WORK/wf-mut.yml"
  awk "$prog" "$WF" > "$f"
  if cmp -s "$WF" "$f"; then c4_bad "$label: the mutation did not land (copy identical to pristine)"; return; fi
  if gao_guard "$f"; then c4_bad "$label stayed GREEN: F8 cannot see this defect"; else c4_ok "$label -> RED"; fi
}
f8mut "C.4-F8m1 mutant: the ga_overlay -var carries weight 1 (a fresh create would pool web-2 hot)" '/^  ga_overlay:/ {job=1} job && /-var="web2_lb_weight=0"/ {sub(/web2_lb_weight=0/, "web2_lb_weight=1")} {print}'
f8mut "C.4-F8m2 mutant: the ga_overlay -var line is deleted (default 1 would apply)" '/^  ga_overlay:/ {job=1} job && /-var="web2_lb_weight=0"/ {next} {print}'
f8mut "C.4-F8m3 mutant: the real -var is deleted and the literal moves to an echo BEFORE the plan (token present in the step, absent from the chain)" '/^  ga_overlay:/ {job=1} job && /-var="web2_lb_weight=0"/ {next} job && /^          doppler run --preserve-env/ && !done {print "          echo -var=\"web2_lb_weight=0\""; done=1} {print}'
f8mut "C.4-F8m4 mutant: a second -var=1 follows the 0 (the last value wins, one line per -var)" '/^  ga_overlay:/ {job=1} {print} job && /-var="web2_lb_weight=0"/ {print "              -var=\"web2_lb_weight=1\" \\"}'
f8mut "C.4-F8m5 mutant: the real -var is deleted and the literal rides the redactor AFTER the pipe (terraform itself gets no -var)" '/^  ga_overlay:/ {job=1} job && /^ *-var="web2_lb_weight=0"/ {next} job && /tf_redact_random_ids/ && !done {sub(/tf_redact_random_ids/, "tf_redact_random_ids -var=\"web2_lb_weight=0\""); done=1} {print}'
f8mut "C.4-F8m6 mutant: an echo decoy named terraform plan carries the literal and the real -var is deleted" '/^  ga_overlay:/ {job=1} job && /^ *-var="web2_lb_weight=0"/ {next} job && /^          doppler run --preserve-env/ && !done {print "          echo terraform plan \\"; print "            -var=\"web2_lb_weight=0\" \\"; done=1} {print}'
f8mut "C.4-F8m7 mutant: a SECOND terraform plan command without the var follows the first" '/^  ga_overlay:/ {job=1} {print} job && /tf_redact_random_ids/ && !done {print "          terraform plan -no-color -input=false -out=tfplan2 -target=cloudflare_load_balancer_pool.web_1"; done=1}'
f8mut "C.4-F8m8 mutant: a SAME-LINE duplicate -var=1 follows the 0 (a line count sees one line; an occurrence count sees two)" '/^  ga_overlay:/ {job=1} job && /^ *-var="web2_lb_weight=0"/ {sub(/-var="web2_lb_weight=0"/, "-var=\"web2_lb_weight=0\" -var=\"web2_lb_weight=1\"")} {print}'
rm -rf "$F8_WORK"
# F6 / V2 each get a same-line / heredoc mutant so the "count occurrences, one default" hardening is shown red
F6_WORK="$(mktemp -d)"
awk '/^ *-var="web2_lb_weight=0"/ {sub(/-var="web2_lb_weight=0"/, "-var=\"web2_lb_weight=0\" -var=\"web2_lb_weight=1\"")} {print}' "$WF" > "$F6_WORK/wf.yml"
if cmp -s "$WF" "$F6_WORK/wf.yml"; then c4_bad "C.4-F6m1: the mutation did not land"; elif f6_guard "$F6_WORK/wf.yml"; then c4_bad "C.4-F6m1 stayed GREEN: a same-line duplicate -var escapes the occurrence count"; else c4_ok "C.4-F6m1 mutant: a same-line duplicate -var=1 -> RED"; fi
V2_BAD1="$V_BLOCK"$'\n''  description = <<EOT'$'\n''  default = 1'$'\n''EOT'
V2_BAD2="$(sed -E 's/^([[:space:]]*)default([[:space:]]*)=([[:space:]]*)1/\1default\2=\31\n\1default = 1/' <<<"$V_BLOCK")"
V2_BAD3="$(sed -E 's/^([[:space:]]*)default([[:space:]]*)=([[:space:]]*)1[[:space:]]*$/\1default\2=\30\n\1# default = 1/' <<<"$V_BLOCK")"
for tag in 1 2 3; do
  v="V2_BAD$tag"
  if [[ "${!v}" == "$V_BLOCK" ]]; then c4_bad "C.4-V2m$tag: the mutation did not land"; elif v2_guard "${!v}"; then c4_bad "C.4-V2m$tag stayed GREEN: the single-default guard cannot see this variant"; else c4_ok "C.4-V2m$tag mutant (heredoc default / duplicate default / default 0 with a commented 1) -> RED"; fi
done
rm -rf "$F6_WORK"

# --- W: the drain invariant by EFFECT, not by text (T-P2-1) -----------------------------------------
# F4-F6 pin the pin step's WORDING. They cannot see a second, later writer: a `WEB2_LB_WEIGHT: "1"` in the plan step's env or a
# step before the plan that appends WEB2_LB_WEIGHT=1 to $GITHUB_ENV leaves every wording pin green while the plan (and the gate,
# which reads the same variable) would run at weight 1 on a DRAIN dispatch. w_guard states the invariant as effects:
#   W-a  exactly ONE non-comment line of the ga_pool_update job assigns WEB2_LB_WEIGHT=0|1 (the mode-derived if/else);
#   W-b  exactly ONE non-comment line of the job writes WEB2_LB_WEIGHT to $GITHUB_ENV;
#   W-c  no `WEB2_LB_WEIGHT:` YAML key anywhere in the workflow (a step-, job- or workflow-level env would override the pin);
#   W-d  EXECUTING the pin step body: mode=drain writes WEB2_LB_WEIGHT=0 exactly once, mode=serve writes 1 exactly once, and an
#        unknown mode is refused with nothing written.
# Each rule is mutation-proved on a sandbox copy of the workflow (control green first, mutant verified to have LANDED).
W_WORK="$(mktemp -d)"
w_guard() { # w_guard <workflow-file> -> 0 iff the invariant holds
  local wf="$1" JOB pin run nc m rc
  JOB="$(awk '/^  ga_pool_update:/ {on=1; print; next} on && /^  [A-Za-z0-9_-]+:/ {exit} on {print}' "$wf" 2>/dev/null || true)"
  [[ -n "$JOB" ]] || return 1
  nc="$(c4_nocomment <(printf '%s\n' "$JOB") || true)"
  [[ "$(grep -cE 'WEB2_LB_WEIGHT=[01]' <<<"$nc" || true)" -eq 1 ]] || return 1
  [[ "$(grep -E 'WEB2_LB_WEIGHT' <<<"$nc" | grep -c 'GITHUB_ENV' || true)" -eq 1 ]] || return 1
  [[ "$(c4_nocomment "$wf" | grep -cE '^[[:space:]]*(-[[:space:]]+)?WEB2_LB_WEIGHT[[:space:]]*:' || true)" -eq 0 ]] || return 1
  pin="$(step_of 'Typo-guard' || true)"
  run="$(awk '/^        run: \|[[:space:]]*$/ {on=1; next} on {print}' <<<"$pin" | sed -E 's/^          //')"
  [[ -n "$run" ]] || return 1
  printf '%s\n' "$run" > "$W_WORK/pin-run.sh"
  for m in drain serve; do
    : > "$W_WORK/env"; : > "$W_WORK/sum"
    (cd "$W_WORK" && env -i PATH="/usr/bin:/bin" CONFIRM_RAW=UPDATE-GA-LB-POOL REASON_RAW=fixture MODE_RAW="$m" GITHUB_ENV="$W_WORK/env" GITHUB_STEP_SUMMARY="$W_WORK/sum" GITHUB_RUN_ID=1 bash "$W_WORK/pin-run.sh" >/dev/null 2>&1) || return 1
    [[ "$(grep -c '^WEB2_LB_WEIGHT=' "$W_WORK/env" || true)" -eq 1 ]] || return 1
    if [[ "$m" == drain ]]; then [[ "$(grep '^WEB2_LB_WEIGHT=' "$W_WORK/env")" == "WEB2_LB_WEIGHT=0" ]] || return 1
    else [[ "$(grep '^WEB2_LB_WEIGHT=' "$W_WORK/env")" == "WEB2_LB_WEIGHT=1" ]] || return 1; fi
  done
  : > "$W_WORK/env"; rc=0
  (cd "$W_WORK" && env -i PATH="/usr/bin:/bin" CONFIRM_RAW=UPDATE-GA-LB-POOL REASON_RAW=fixture MODE_RAW=bogus GITHUB_ENV="$W_WORK/env" GITHUB_STEP_SUMMARY="$W_WORK/sum" GITHUB_RUN_ID=1 bash "$W_WORK/pin-run.sh" >/dev/null 2>&1) || rc=$?
  [[ "$rc" -ne 0 && ! -s "$W_WORK/env" ]] || return 1
  return 0
}
c4_assert "C.4-W0 control: the pristine workflow satisfies the effect-level drain invariant (one assignment, one GITHUB_ENV write, no env key, pin executes drain=0 / serve=1 / bogus refused)" \
  "$(w_guard "$WF" && echo 1 || echo 0)"
wmut() { # wmut <label> <awk-program> — mutate a sandbox copy of the workflow; the mutation must LAND and the guard must go red
  local label="$1" prog="$2" f="$W_WORK/wf-mut.yml"
  awk "$prog" "$WF" > "$f"
  if cmp -s "$WF" "$f"; then c4_bad "$label: the mutation did not land (copy identical to pristine)"; return; fi
  if w_guard "$f"; then c4_bad "$label stayed GREEN: the effect-level drain guard cannot see this defect"; else c4_ok "$label -> RED"; fi
}
wmut "C.4-W2 mutant: WEB2_LB_WEIGHT: \"1\" in the plan step's env" '/^      - name: Terraform plan \(GA pool/ {inplan=1} {print} inplan && /^        env:/ {print "          WEB2_LB_WEIGHT: \"1\""; inplan=0}'
wmut "C.4-W3 mutant: a step before the plan appends WEB2_LB_WEIGHT=1 to GITHUB_ENV" '/^      - name: Terraform plan \(GA pool/ {print "      - name: sneak"; print "        run: echo \"WEB2_LB_WEIGHT=1\" >> \"$GITHUB_ENV\""} {print}'
wmut "C.4-W3b mutant: a step before the plan appends a COMPUTED WEB2_LB_WEIGHT to GITHUB_ENV (no literal 0|1 on the line)" '/^      - name: Terraform plan \(GA pool/ {print "      - name: sneak"; print "        run: echo \"WEB2_LB_WEIGHT=${SNEAK}\" >> \"$GITHUB_ENV\""} {print}'
wmut "C.4-W4 mutant: a job-level env sets WEB2_LB_WEIGHT" '{print} /^  ga_pool_update:/ {inj=1} inj && /^    timeout-minutes:/ {print "    env:"; print "      WEB2_LB_WEIGHT: \"1\""; inj=0}'
wmut "C.4-W5 mutant: a workflow-level env sets WEB2_LB_WEIGHT" '/^env:/ && !done {print; print "  WEB2_LB_WEIGHT: \"1\""; done=1; next} {print}'
wmut "C.4-W6 mutant: the pin step assigns 1 in BOTH branches (drain would plan weight 1)" '{ if ($0 ~ /then WEB2_LB_WEIGHT=1; else WEB2_LB_WEIGHT=0; fi/) sub(/else WEB2_LB_WEIGHT=0/, "else WEB2_LB_WEIGHT=1"); print }'
wmut "C.4-W7 mutant: the pin step writes the weight to GITHUB_ENV a second time" '{print} /^          echo "WEB2_LB_WEIGHT=\$\{WEB2_LB_WEIGHT\}" >> "\$GITHUB_ENV"/ {print "          echo \"WEB2_LB_WEIGHT=1\" >> \"$GITHUB_ENV\""}'
wmut "C.4-W8 mutant: the mode guard no longer refuses an unknown mode" '{ if ($0 ~ /MODE_RAW" != "drain" && "\$MODE_RAW" != "serve"/) sub(/\[\[ .* \]\]; then/, "[[ -z \"$MODE_RAW\" ]]; then"); print }'
rm -rf "$W_WORK"

# --- O: ordering / fail-closed chain ---------------------------------------------------------
GATE_AT="$(line_of '§\(c\) gate chain')"; PLAN_AT="$(line_of 'Terraform plan \(GA pool')"
c4_assert "C.4-O1: the §(c) gate chain step precedes the plan step that carries the variable" \
  "$([[ "$GATE_AT" -gt 0 && "$PLAN_AT" -gt "$GATE_AT" ]] && echo 1 || echo 0)"
c4_assert "C.4-O2: the gate chain step is serve-gated on the step itself" \
  "$(grep -qE "^        if: inputs\.mode == 'serve'[[:space:]]*$" <<<"$GATE_STEP" && echo 1 || echo 0)"
c4_assert "C.4-O3: no continue-on-error anywhere in the job (a tolerated gate failure would still reach the plan)" \
  "$([[ -z "$(c4_nocomment <(printf '%s\n' "$JOB") | grep -E 'continue-on-error')" ]] && echo 1 || echo 0)"
c4_assert "C.4-O4: the gate is evaluated on the SAME weight that is planned (SOLEUR_WEB2_SERVING_WEIGHT=\$WEB2_LB_WEIGHT)" \
  "$(grep -qE 'SOLEUR_WEB2_SERVING_WEIGHT="\$WEB2_LB_WEIGHT"' <<<"$GATE_STEP" && echo 1 || echo 0)"
c4_assert "C.4-O5: the gate chain still requires the requires_runtime_bind_probe=true marker and the wrapper (not the bare gate)" \
  "$(grep -q 'requires_runtime_bind_probe=true' <<<"$GATE_STEP" && grep -q 'lb-weight-gate-with-marker.sh' <<<"$GATE_STEP" && echo 1 || echo 0)"
c4_assert "C.4-O6: the web-2 pool-health precondition (n>=2, all healthy) is still serve-gated and precedes the plan" \
  "$([[ "$(line_of 'web-2 health precondition')" -gt 0 && "$(line_of 'web-2 health precondition')" -lt "$PLAN_AT" ]] && grep -qE "if \[\[ \"\\\$W2_N\" -lt 2 \]\]" <<<"$JOB" && echo 1 || echo 0)"

# --- P: the arm injects ONLY what the gate reads; the retired synthetic bind is gone ----------
# Condition A.1 was deleted (#12359): the gate neither reads nor allowlists SOLEUR_PROXY_BIND, so the serve step's inner env
# carries exactly DOPPLER_TOKEN, DOPPLER_BIN, SOLEUR_WEB2_SERVING_WEIGHT and SOLEUR_SERVING_ROTATION, and the name appears on NO
# non-comment line of the workflow. p_guard states that; each clause is mutation-proved on a sandbox copy (control green first).
ROT_VAL="$(grep -oE 'SOLEUR_SERVING_ROTATION="[^"]+"' <<<"$GATE_STEP" | head -1 | sed -E 's/^SOLEUR_SERVING_ROTATION="(.*)"$/\1/' || true)"
P_WORK="$(mktemp -d)"
p_guard() { # p_guard <workflow-file> -> 0 iff the serve step injects exactly the four names and PROXY_BIND is on no code line
  local wf="$1" JOB gate joined names
  JOB="$(awk '/^  ga_pool_update:/ {on=1; print; next} on && /^  [A-Za-z0-9_-]+:/ {exit} on {print}' "$wf" 2>/dev/null || true)"
  gate="$(step_of '§\(c\) gate chain' || true)"
  [[ -n "$gate" ]] || return 1
  [[ "$(c4_nocomment "$wf" | grep -c 'PROXY_BIND' || true)" -eq 0 ]] || return 1
  printf '%s\n' "$gate" | grep -vE '^[[:space:]]*#' > "$P_WORK/gate-nc"
  joined="$(sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' "$P_WORK/gate-nc" | tr -s ' ')"
  # the inner env: everything between `doppler run ... -- env ` and ` bash "` on the wrapper line
  names="$(sed -nE 's/.*doppler run [^|]*-- env (.*) bash "\$\{GITHUB_WORKSPACE\}.*/\1/p' <<<"$joined" | grep -oE '(^| )[A-Z_0-9]+=' | tr -d ' =' | sort | tr '\n' ',' || true)"
  [[ "$names" == "DOPPLER_BIN,DOPPLER_TOKEN,SOLEUR_GATED_HOST,SOLEUR_SERVING_ROTATION,SOLEUR_WEB2_SERVING_WEIGHT," ]] || return 1
  # (the names are read from AFTER `doppler run ... -- env`, so the two gate inputs are by construction assigned after the
  # doppler run and override any ambient prd value; C.4-P1m6 proves an input moved before the run is not accepted)
  return 0
}
c4_assert "C.4-P1 control: the pristine serve step injects exactly {DOPPLER_TOKEN, DOPPLER_BIN, SOLEUR_WEB2_SERVING_WEIGHT, SOLEUR_SERVING_ROTATION} and a rotation naming web-2 (got rotation='${ROT_VAL}'); SOLEUR_PROXY_BIND is on NO non-comment line of the workflow" \
  "$([[ "$ROT_VAL" == *web-2* ]] && p_guard "$WF" && echo 1 || echo 0)"
pmut() { # pmut <label> <awk-program> — mutate a sandbox copy; the mutation must LAND and p_guard must go red
  local label="$1" prog="$2" f="$P_WORK/wf-mut.yml"
  awk "$prog" "$WF" > "$f"
  if cmp -s "$WF" "$f"; then c4_bad "$label: the mutation did not land (copy identical to pristine)"; return; fi
  if p_guard "$f"; then c4_bad "$label stayed GREEN: the guard cannot see this defect"; else c4_ok "$label -> RED"; fi
}
pmut "C.4-P1m1 mutant: the retired synthetic SOLEUR_PROXY_BIND line is re-added to the inner env" '{print} /^              SOLEUR_SERVING_ROTATION="web-1,web-2" \\$/ {print "              SOLEUR_PROXY_BIND=\"synthetic-gate-shape-input-not-a-bind-address\" \\"}'
pmut "C.4-P1m2 mutant: SOLEUR_PROXY_BIND is re-added as a DIFFERENT value" '{print} /^              SOLEUR_SERVING_ROTATION="web-1,web-2" \\$/ {print "              SOLEUR_PROXY_BIND=\"10.0.1.11\" \\"}'
pmut "C.4-P1m3 mutant: SOLEUR_PROXY_BIND is exported through GITHUB_ENV from the pin step" '{print} /^          echo "POOL_UPDATE_MODE=\$\{MODE_RAW\}" >> "\$GITHUB_ENV"/ {print "          echo \"SOLEUR_PROXY_BIND=x\" >> \"$GITHUB_ENV\""}'
pmut "C.4-P1m4 mutant: an extra, unrelated name joins the inner env" '{print} /^              SOLEUR_SERVING_ROTATION="web-1,web-2" \\$/ {print "              SOLEUR_EXTRA_INPUT=\"1\" \\"}'
pmut "C.4-P1m5 mutant: SOLEUR_SERVING_ROTATION is dropped from the inner env" '!/^              SOLEUR_SERVING_ROTATION="web-1,web-2" \\$/ {print}'
pmut "C.4-P1m6 mutant: the rotation input moves BEFORE the doppler run (ambient prd value would win)" '/^          GATE_OUT="\$\(env DOPPLER_TOKEN=/ {sub(/GATE_OUT="\$\(env /, "GATE_OUT=\"$(env SOLEUR_SERVING_ROTATION=\"web-1,web-2\" ")} !/^              SOLEUR_SERVING_ROTATION="web-1,web-2" \\$/ {print}'
rm -rf "$P_WORK"
c4_assert "C.4-P3: the ga_pool_update job never writes Doppler (no 'doppler secrets set|upload|delete')" \
  "$([[ -z "$(c4_nocomment <(printf '%s\n' "$JOB") | grep -E 'doppler[[:space:]]+secrets[[:space:]]+(set|upload|delete)')" ]] && echo 1 || echo 0)"

# --- G: the gate, fed exactly what the arm injects, keeps every fail-closed condition ----------
# Weight comes from the pin step's serve branch (1); rotation from the gate-chain step.
SERVE_W="$(grep -oE 'then WEB2_LB_WEIGHT=[0-9]+' <<<"$PIN_STEP" | head -1 | grep -oE '[0-9]+$' || true)"
arm_env() { # the injected pair, as the workflow sets them in serve mode
  reset_def
  DEF[SOLEUR_WEB2_SERVING_WEIGHT]="${SERVE_W:-}"
  DEF[SOLEUR_GATED_HOST]="$(grep -oE 'SOLEUR_GATED_HOST="[^"]+"' <<<"$GATE_STEP" | head -1 | sed -E 's/^SOLEUR_GATED_HOST="(.*)"$/\1/' || true)"
  DEF[SOLEUR_SERVING_ROTATION]="$ROT_VAL"
}
arm_env; run_with_def
assert_zero "C.4-G1: arm-injected pair + every precondition met → gate passes"
assert_stdout_contains "C.4-G1b: …and prints the flip-authorization marker the step greps for" "requires_runtime_bind_probe=true"
arm_env; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
assert_rejects_with "C.4-G2: arm-injected pair + git-data store disabled → refused" "B_git_data_store_disabled"
arm_env; unset 'DEF[GIT_DATA_LUKS_CUTOVER_AT]'; run_with_def
assert_rejects_with "C.4-G3: arm-injected pair + GIT_DATA_LUKS_CUTOVER_AT absent → refused" "B_luks_cutover_marker_absent"
arm_env; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_rejects_with "C.4-G4: arm-injected pair + git-data soak not elapsed → refused" "B_luks_soak_not_elapsed"
arm_env; unset 'DEF[WORKSPACES_LUKS_CUTOVER_AT]'; run_with_def
assert_rejects_with "C.4-G5: arm-injected pair + WORKSPACES_LUKS_CUTOVER_AT absent (today's Doppler state) → refused" "B_workspaces_luks_marker_absent"
arm_env; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_rejects_with "C.4-G6: arm-injected pair + workspaces soak not elapsed → refused" "B_workspaces_luks_soak_not_elapsed"
arm_env; DEF[GIT_DATA_LUKS_SOAK_DAYS]='0'; run_with_def
assert_rejects_with "C.4-G7: arm-injected pair + soak days 0 → refused (0 is rejected, not 'no soak')" "B_luks_soak_days_invalid"
arm_env; DEF[WORKSPACES_LUKS_SOAK_DAYS]='0'; run_with_def
assert_rejects_with "C.4-G8: arm-injected pair + workspaces soak days 0 → refused" "B_workspaces_luks_soak_days_invalid"
arm_env; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10"}'; run_with_def
assert_rejects_with "C.4-G9: arm-injected pair + roster omits web-2 → refused" "A_web2_not_in_roster"
arm_env; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.10'; run_with_def
assert_rejects_with "C.4-G10: arm-injected pair + web-2 addr not in allowlist → refused" "A_web2_addr_not_in_allowlist"
# The drain value is NOT authorization: weight 0 without web-2 in rotation is the standby branch,
# which prints the SHAPE-ONLY banner and NOT the marker the serve step requires.
arm_env; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'; DEF[SOLEUR_SERVING_ROTATION]=''; run_with_def
assert_zero "C.4-G11: standby inputs pass the gate…"
c4_assert "C.4-G11b: …but WITHOUT requires_runtime_bind_probe=true (the serve step would refuse it)" \
  "$([[ "$GATE_OUT" != *requires_runtime_bind_probe=true* ]] && echo 1 || echo 0)"

# --- R: the relay bind probe (serve only) — #12167 -------------------------------------------------
# The gate chain no longer checks the relay bind at all (Condition A.1 was deleted, #12359), and the
# pool-health read proves origin HEALTH, not that the relay listens on web-2's private address. This step
# closes that: it reads web-2's OWN relay report from Better Stack (scripts/lib/web2-relay-rows.sh, the
# credentials ride the environment, never argv) and refuses unless BOTH hold: (1) >= 2 own-line rows in the last 180 s,
# newest <= 120 s, every row proxy_state=listening addr=0.0.0.0 (the in-container wildcard the shipped design binds; docker
# publishes the private IP) port 8443 (workspaces_populated is recorded, not judged: owner ruling 2026-11-06); (2) web-1's
# newest relay_peer_probe row (last 24 h) for the address Terraform STATE holds for web-2 says result=ok (web-1 -> web-2);
# (3) the REVERSE direction: web-2's own newest row (host_name soleur-web-2) about the address STATE holds for web-1 says
# result=ok (web-2 -> web-1; existing sessions are owned by web-1). The owner-recorded gate is "ok in both directions".
# R1-R8 pin the step's position and form; E1-E24 EXECUTE the step's own run body against stubbed `terraform` and
# `curl` (the real helper and the real scripts/betterstack-query.sh in between), one refusal per fixture.
PROBE_STEP="$(step_of 'relay bind probe \(serve only\)' || true)"
PROBE_AT="$(line_of 'relay bind probe \(serve only\)')"
INIT_AT="$(line_of 'Terraform init \(parent root\)')"
PROBE_RUN="$(awk '/^        run: \|[[:space:]]*$/ {on=1; next} on {print}' <<<"$PROBE_STEP" | sed -E 's/^          //')"
c4_assert "C.4-R1: the 'relay bind probe (serve only)' step exists in ga_pool_update with a run body (non-vacuity)" \
  "$([[ -n "$PROBE_STEP" && "$PROBE_AT" -gt 0 && -n "$PROBE_RUN" ]] && echo 1 || echo 0)"
c4_assert "C.4-R2: order is gate chain < probe < plan (the probe runs after the gate, before anything is planned)" \
  "$([[ "$GATE_AT" -gt 0 && "$PROBE_AT" -gt "$GATE_AT" && "$PLAN_AT" -gt "$PROBE_AT" ]] && echo 1 || echo 0)"
c4_assert "C.4-R2b: the probe runs after Terraform init (it reads web-2's address from state)" \
  "$([[ "$INIT_AT" -gt 0 && "$PROBE_AT" -gt "$INIT_AT" ]] && echo 1 || echo 0)"
c4_assert "C.4-R3: the probe is serve-gated on the step itself" \
  "$(grep -qE "^        if: inputs\.mode == 'serve'[[:space:]]*$" <<<"$PROBE_STEP" && echo 1 || echo 0)"
PROBE_NC="$(c4_nocomment <(printf '%s\n' "$PROBE_STEP"))"
PROBE_RUN_NC="$(c4_nocomment <(printf '%s\n' "$PROBE_RUN"))"
c4_assert "C.4-R4: no continue-on-error / '|| true' / 'set +e' in the probe step (a tolerated refusal would still reach the plan)" \
  "$([[ -n "$PROBE_NC" && -z "$(grep -E 'continue-on-error|\|\|[[:space:]]*true|set[[:space:]]+\+e' <<<"$PROBE_NC")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R4b: no 'secrets.' expression in the probe's run body (credentials arrive only through the env block)" \
  "$([[ -n "$PROBE_RUN_NC" && -z "$(grep -F 'secrets.' <<<"$PROBE_RUN_NC")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R5: the peer address is READ FROM STATE (terraform show -json, hcloud_server_network.web[\"web-2\"]) and handed to the peer fetch AND the peer judge as a variable" \
  "$(grep -qF 'terraform show -json' <<<"$PROBE_RUN_NC" && grep -qF 'hcloud_server_network.web[\"web-2\"]' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_peer_judge[[:space:]]+"[^"]+"[[:space:]]+"[^"]+"[[:space:]]+"\$\{?WEB2_PRIVATE\}?"' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_peer_fetch[[:space:]]+"[^"]+"[[:space:]]+"[^"]+"[[:space:]]+"\$\{?WEB2_PRIVATE\}?"' <<<"$PROBE_RUN_NC" && echo 1 || echo 0)"
c4_assert "C.4-R5c: the REVERSE direction is READ FROM STATE too (hcloud_server_network.web[\"web-1\"]) and handed to the peer fetch AND the peer judge, dialled by the web-2 host constant (WRR_HOST_NAME), forward by web-1's (WRR_PEER_HOST_NAME)" \
  "$(grep -qF 'hcloud_server_network.web[\"web-1\"]' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_peer_fetch[[:space:]]+"[^"]+"[[:space:]]+"\$WRR_HOST_NAME"[[:space:]]+"\$\{?WEB1_PRIVATE\}?"' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_peer_judge[[:space:]]+"[^"]+"[[:space:]]+"\$WRR_HOST_NAME"[[:space:]]+"\$\{?WEB1_PRIVATE\}?"' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_peer_fetch[[:space:]]+"[^"]+"[[:space:]]+"\$WRR_PEER_HOST_NAME"[[:space:]]+"\$\{?WEB2_PRIVATE\}?"' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_peer_judge[[:space:]]+"[^"]+"[[:space:]]+"\$WRR_PEER_HOST_NAME"[[:space:]]+"\$\{?WEB2_PRIVATE\}?"' <<<"$PROBE_RUN_NC" && echo 1 || echo 0)"
c4_assert "C.4-R5b: no literal IPv4 address anywhere in the probe step" \
  "$([[ -n "$PROBE_NC" && -z "$(grep -E '(^|[^0-9.])[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)' <<<"$PROBE_NC")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R6: the step never names SOLEUR_PROXY_BIND, never writes Doppler or GITHUB_ENV" \
  "$([[ -n "$PROBE_NC" && -z "$(grep -E 'SOLEUR_PROXY_BIND|doppler[[:space:]]+secrets|GITHUB_ENV' <<<"$PROBE_NC")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R7: the three BETTERSTACK_QUERY_* credentials ride the step env, each refused when empty, none on a command line" \
  "$([[ "$(grep -cE '^          BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD): \$\{\{ secrets\.BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD) \}\}$' <<<"$PROBE_STEP")" -eq 3 ]] && grep -qE 'for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD' <<<"$PROBE_RUN_NC" && grep -qE '\-z "\$\{!v:-\}"' <<<"$PROBE_RUN_NC" && [[ -z "$(grep -E 'BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD)[^ ]*[[:space:]]*(=|\))' <<<"$(grep -vE 'for v in|^[[:space:]]*(if|echo)' <<<"$PROBE_RUN_NC")")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R8: the step uses the shared helper (wrr_fetch, wrr_judge, wrr_peer_fetch, wrr_peer_judge) and passes ONLY when ALL THREE verdicts (own line, web-1 -> web-2, web-2 -> web-1) are GREEN" \
  "$(grep -qF 'scripts/lib/web2-relay-rows.sh' <<<"$PROBE_RUN_NC" && grep -qE '^wrr_fetch|[[:space:]]wrr_fetch ' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_judge' <<<"$PROBE_RUN_NC" && grep -qE '^wrr_peer_fetch|[[:space:]]wrr_peer_fetch ' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_peer_judge' <<<"$PROBE_RUN_NC" && grep -qE '"\$VERDICT".*!=.*GREEN' <<<"$PROBE_RUN_NC" && grep -qE '"\$PEER_VERDICT".*!=.*GREEN' <<<"$PROBE_RUN_NC" && grep -qE '"\$PEER_VERDICT_REV".*!=.*GREEN' <<<"$PROBE_RUN_NC" && echo 1 || echo 0)"
c4_assert "C.4-R9: the step does NOT compare the app's addr to the private IP (the app binds the wildcard in its container): wrr_judge takes exactly one argument" \
  "$(grep -qE 'wrr_judge[[:space:]]+"[^"]+"\)"' <<<"$PROBE_RUN_NC" && ! grep -qE 'wrr_judge[[:space:]]+"[^"]+"[[:space:]]+"' <<<"$PROBE_RUN_NC" && echo 1 || echo 0)"

c4_assert "C.4-R10: the step refuses when the sourced helper stopped defining WRR_PORT / WRR_BIND_ADDR / WRR_HOST_NAME / WRR_PEER_HOST_NAME (a guarded check, so lint-workflow-step-env-refs holds and a missing constant cannot blank a host pin)" \
  "$(grep -qE '\[\[ -n "\$\{WRR_PORT:-\}" && -n "\$\{WRR_BIND_ADDR:-\}" && -n "\$\{WRR_HOST_NAME:-\}" && -n "\$\{WRR_PEER_HOST_NAME:-\}" \]\]' <<<"$PROBE_RUN_NC" && echo 1 || echo 0)"
c4_assert "C.4-R11: the accepted forward-probe residual (written before web-1's fan-out, so it describes web-2's PREVIOUS container; dispatch serve right after a release deploy) is stated in the step's summary line AND its refusal message" \
  "$([[ "$(grep -c "web-2's previous container" <<<"$PROBE_RUN_NC")" -ge 1 && "$(grep -c 'PREVIOUS container' <<<"$PROBE_RUN_NC")" -ge 1 && "$(grep -c 'right after a release deploy' <<<"$PROBE_RUN_NC")" -ge 1 ]] && echo 1 || echo 0)"

# --- E: execute the step's own run body, offline ------------------------------------------------------
R_WORK="$(mktemp -d)"; trap 'rm -rf "$R_WORK"' EXIT
R_BIN="$R_WORK/bin"; R_FX="$R_WORK/fx"; mkdir -p "$R_BIN" "$R_FX"
printf '%s\n' "$PROBE_RUN" > "$R_WORK/probe-run.sh"
cat > "$R_BIN/terraform" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "show -json" ] || { echo "terraform stub: only 'show -json' is taught" >&2; exit 64; }
[ -f "$FX/tf.fail" ] && exit 1
cat "$FX/state"
STUB
cat > "$R_BIN/curl" <<'STUB'
#!/usr/bin/env bash
url=""; data=""; user=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--data-binary) data="$2"; shift 2 ;;
    --config) if [ "$2" = - ]; then cfg="$(cat)"; user="${cfg#user = \"}"; user="${user%%\"*}"; fi; shift 2 ;;
    -u) echo "curl stub: credentials on ARGV" >&2; exit 64 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
leak="$(env | cut -d= -f1 | grep -E 'TOKEN|SECRET|PASSWORD|KEY|CREDENTIAL|AUTH|DOPPLER' | grep -vxE 'BETTERSTACK_QUERY_PASSWORD' || true)"
if [ -n "$leak" ]; then printf '%s\n' "$leak" >> "$LEAK"; exit 64; fi
case "$url" in "https://fixture-connect.betterstackdata.com?"*) : ;; *) exit 64 ;; esac
[ "$user" = fixture-user:fixture-pass ] || exit 64
printf 'q\n' >> "$CALLS"
printf '%s\n' "$data" | tr '\n' ' ' >> "$SQLLOG"; printf '\n' >> "$SQLLOG"
case "$(cat "$FX/mode" 2>/dev/null)" in 503) printf '{"error":"x"}'; exit 22 ;; timeout) exit 28 ;; esac
case "$data" in *relay_peer_probe*) case "$data" in *"'soleur-web-2'"*) sfx=_w2 ;; *) sfx= ;; esac; printf 'p%s\n' "$sfx" >> "$CALLS"; case "$(cat "$FX/peer_mode$sfx" 2>/dev/null)" in 503) printf '{"error":"x"}'; exit 22 ;; esac; cat "$FX/peer_rows$sfx" ;; *) cat "$FX/rows" ;; esac
STUB
chmod +x "$R_BIN/terraform" "$R_BIN/curl"
r_state() { printf '{"values":{"root_module":{"resources":[{"address":"hcloud_server_network.web[\\"web-1\\"]","values":{"ip":"10.0.1.10"}},{"address":"hcloud_server_network.web[\\"web-2\\"]","values":{"ip":"%s"}}]}}}' "$1" > "$R_FX/state"; }
r_line() { printf 'relay_probe proxy_state=%s addr=%s port=%s workspaces_populated=%s' "${1:-listening}" "${2:-0.0.0.0}" "${3:-8443}" "${4:-1}"; }
r_row() { jq -cn --arg a "$1" --arg l "$2" --arg h "${3:-soleur-web-2}" '{age_s:$a,host_name:$h,line:$l}'; }
r_peer() { printf 'relay_peer_probe peer=%s %s' "${1:-10.0.1.11}" "${2:-result=ok}"; }
r_prow() { jq -cn --arg a "$1" --arg l "$2" --arg h "${3:-soleur-web-platform}" '{age_s:$a,host_name:$h,line:$l}'; }
R_OUT=""; R_RC=0
r_exec() { # r_exec [ENV=VAL ...] — run the step body in a clean env; output -> R_OUT, rc -> R_RC
  : > "$R_WORK/leak"; : > "$R_WORK/calls"; : > "$R_WORK/summary"; : > "$R_WORK/sqllog"
  R_OUT="$(cd "$R_WORK" && env -i PATH="$R_BIN:/usr/bin:/bin" HOME="$R_WORK" TMPDIR="$R_WORK" FX="$R_FX" LEAK="$R_WORK/leak" CALLS="$R_WORK/calls" SQLLOG="$R_WORK/sqllog" \
    GITHUB_WORKSPACE="$REPO_ROOT" GITHUB_STEP_SUMMARY="$R_WORK/summary" GH_TOKEN=decoy-gh DOPPLER_TOKEN=decoy-doppler AWS_SECRET_ACCESS_KEY=decoy-aws \
    BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass \
    "$@" bash "$R_WORK/probe-run.sh" 2>&1)" && R_RC=0 || R_RC=$?
}
e_refuse() { # e_refuse <desc> <needle> [ENV=VAL ...] — exit 1 with an ::error:: line that NAMES the reason (a refusal for the wrong reason is red)
  r_exec "${@:3}"
  c4_assert "$1 → exit 1, refused for: $2" "$([[ "$R_RC" -eq 1 && "$R_OUT" == *"::error::"* && "$R_OUT" == *"$2"* && ! -s "$R_WORK/leak" ]] && echo 1 || echo 0)"
}
e_reset() { : > "$R_FX/mode"; : > "$R_FX/peer_mode"; : > "$R_FX/peer_mode_w2"; rm -f "$R_FX/tf.fail"; r_state 10.0.1.11; { r_row 20 "$(r_line)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; r_prow 3600 "$(r_peer)" > "$R_FX/peer_rows"; r_prow 1800 "$(r_peer 10.0.1.10)" soleur-web-2 > "$R_FX/peer_rows_w2"; }

if [[ -n "$PROBE_RUN" ]]; then
e_reset; r_exec
c4_assert "C.4-E1: two healthy own-line rows (addr=0.0.0.0) + an ok peer row for the state address → exit 0, three GREEN lines in the run summary (own line, web-1 -> web-2, web-2 -> web-1)" \
  "$([[ "$R_RC" -eq 0 && "$(grep -c 'GREEN' "$R_WORK/summary")" -eq 3 && "$(grep -c 'dir=w1_to_w2' "$R_WORK/summary")" -eq 1 && "$(grep -c 'dir=w2_to_w1' "$R_WORK/summary")" -eq 1 ]] && echo 1 || echo 0)"
c4_assert "C.4-E1a: …and all THREE queries were sent (own line, forward peer line, reverse peer line)" \
  "$([[ "$(grep -c '^q$' "$R_WORK/calls")" -eq 3 && "$(grep -c '^p$' "$R_WORK/calls")" -eq 1 && "$(grep -c '^p_w2$' "$R_WORK/calls")" -eq 1 ]] && echo 1 || echo 0)"
c4_assert "C.4-E1c: the three SQL texts the step actually sent carry the structured filters (CONTAINER_NAME once, SYSLOG_IDENTIFIER twice, startsWith three times) and no whole-row position(raw / extract(raw" \
  "$([[ "$(grep -o "JSONExtractString(raw,'CONTAINER_NAME') = 'soleur-web-platform'" "$R_WORK/sqllog" | wc -l)" -eq 1 && "$(grep -o "JSONExtractString(raw,'SYSLOG_IDENTIFIER') = 'ci-deploy'" "$R_WORK/sqllog" | wc -l)" -eq 2 && "$(grep -o 'startsWith(JSONExtractString(raw' "$R_WORK/sqllog" | wc -l)" -eq 3 && -z "$(grep -E 'position[(]raw|extract[(]raw' "$R_WORK/sqllog" || true)" ]] && echo 1 || echo 0)"
c4_assert "C.4-E1b: …no credential-shaped variable reached the query child, no decoy printed" \
  "$([[ ! -s "$R_WORK/leak" && "$R_OUT" != *decoy-* && "$R_OUT" != *fixture-pass* ]] && echo 1 || echo 0)"
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  e_reset; e_refuse "C.4-E2: $v absent" "$v is not configured" "$v="
  c4_assert "C.4-E2b: …and no query was sent" "$([[ ! -s "$R_WORK/calls" ]] && echo 1 || echo 0)"
done
e_reset; printf '503' > "$R_FX/mode"; e_refuse "C.4-E3: Better Stack answers 503" "FAILED"
e_reset; printf 'timeout' > "$R_FX/mode"; e_refuse "C.4-E3b: Better Stack times out" "FAILED"
e_reset; printf '<html>502 Bad Gateway</html>\n' > "$R_FX/rows"; e_refuse "C.4-E4: unparseable (HTML) body" "reason=body_unparseable"
e_reset; : > "$R_FX/rows"; e_refuse "C.4-E5: EMPTY body (zero rows is not a pass)" "reason=rows_below_floor"
e_reset; r_row 20 "$(r_line)" > "$R_FX/rows"; e_refuse "C.4-E6: one row only (floor is 2)" "reason=rows_below_floor"
e_reset; { r_row 20 "$(r_line)"; r_row 200 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E6b: second row outside the 180 s window" "reason=rows_below_floor"
e_reset; { r_row 121 "$(r_line)"; r_row 150 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E7: newest row 121 s old" "reason=newest_stale"
e_reset; { r_row 20 "$(r_line no_bind none)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E8: a row says proxy_state=no_bind" "reason=proxy_state_not_listening"
e_reset; { r_row 20 "$(r_line disabled)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E8b: a row says proxy_state=disabled" "reason=proxy_state_not_listening"
e_reset; { r_row 20 "$(r_line listening ::)"; r_row 80 "$(r_line listening ::)"; } > "$R_FX/rows"; e_refuse "C.4-E9: addr=:: (not the shipped IPv4 wildcard)" "reason=addr_mismatch"
e_reset; { r_row 20 "$(r_line listening 10.0.1.11)"; r_row 80 "$(r_line listening 10.0.1.11)"; } > "$R_FX/rows"; e_refuse "C.4-E9b: addr=10.0.1.11 (the old host-private-IP bind: the container can never report it)" "reason=addr_mismatch"
e_reset; { r_row 20 "$(r_line listening none)"; r_row 80 "$(r_line listening none)"; } > "$R_FX/rows"; e_refuse "C.4-E9c: addr=none while listening" "reason=addr_mismatch"
e_reset; { r_row 20 "$(r_line listening 0.0.0.0 8444)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E11: port 8444" "reason=port_mismatch"
# the peer line (web-1's relay_peer_probe about web-2's STATE address): the private-address reachability proof
e_reset; r_prow 3600 "$(r_peer 10.0.1.11 result=refused)" > "$R_FX/peer_rows"; e_refuse "C.4-E10: web-1's newest peer row says result=refused" "reason=peer_refused"
e_reset; r_prow 3600 "$(r_peer 10.0.1.11 result=denied)" > "$R_FX/peer_rows"; e_refuse "C.4-E10b: web-1's newest peer row says result=denied (allowlist)" "reason=peer_denied"
e_reset; r_prow 3600 "$(r_peer 10.0.1.11 result=tls)" > "$R_FX/peer_rows"; e_refuse "C.4-E10c: web-1's newest peer row says result=tls" "reason=peer_tls"
e_reset; : > "$R_FX/peer_rows"; e_refuse "C.4-E10d: no peer row at all in the last 24 h" "reason=peer_rows_none"
e_reset; r_prow 3600 "$(r_peer 10.0.1.12)" > "$R_FX/peer_rows"; e_refuse "C.4-E10e: the peer row is about another address, not the one STATE holds for web-2" "reason=peer_row_malformed"
e_reset; r_state 10.0.1.12; e_refuse "C.4-E10f: STATE says web-2 is 10.0.1.12 but the ok peer row is for 10.0.1.11 (compared against state, not a literal)" "reason=peer_row_malformed"
e_reset; r_prow 3600 "$(r_peer 10.0.1.11 skipped=exec_failed)" > "$R_FX/peer_rows"; e_refuse "C.4-E10g: web-1's newest peer row is skipped=exec_failed" "reason=peer_skipped"
e_reset; r_prow 90000 "$(r_peer)" > "$R_FX/peer_rows"; e_refuse "C.4-E10h: the only ok peer row is older than 24 h" "reason=peer_rows_none"
e_reset; printf '503' > "$R_FX/peer_mode"; e_refuse "C.4-E10i: Better Stack answers 503 to the peer query" "peer probe of web-2 FAILED"
e_reset; { r_prow 7200 "$(r_peer)"; r_prow 300 "$(r_peer 10.0.1.11 result=refused)"; } > "$R_FX/peer_rows"; e_refuse "C.4-E10j: a NEWER refused row beats an older ok" "reason=peer_refused"
e_reset; r_prow 3600 "$(r_peer)" soleur-web-2 > "$R_FX/peer_rows"; e_refuse "C.4-E10k: an ok peer row from web-2 itself is not web-1's probe" "reason=peer_rows_none"
# the REVERSE direction (web-2 -> web-1): each of these has a healthy forward direction, so only the reverse can refuse
e_reset; r_prow 1800 "$(r_peer 10.0.1.10 result=refused)" soleur-web-2 > "$R_FX/peer_rows_w2"; e_refuse "C.4-E17: web-2's newest row about web-1 says result=refused (forward is ok)" "reason=peer_refused dir=w2_to_w1"
e_reset; r_prow 1800 "$(r_peer 10.0.1.10 result=denied)" soleur-web-2 > "$R_FX/peer_rows_w2"; e_refuse "C.4-E17b: web-2 -> web-1 result=denied (web-1's allowlist lacks web-2)" "reason=peer_denied dir=w2_to_w1"
e_reset; r_prow 1800 "$(r_peer 10.0.1.10 result=tls)" soleur-web-2 > "$R_FX/peer_rows_w2"; e_refuse "C.4-E17c: web-2 -> web-1 result=tls" "reason=peer_tls dir=w2_to_w1"
e_reset; : > "$R_FX/peer_rows_w2"; e_refuse "C.4-E18: NO web-2 row at all in 24 h (a missing direction is a distinct refusal, not a pass)" "reason=peer_rows_none dir=w2_to_w1"
e_reset; r_prow 90000 "$(r_peer 10.0.1.10)" soleur-web-2 > "$R_FX/peer_rows_w2"; e_refuse "C.4-E18b: the only ok web-2 row is older than 24 h" "reason=peer_rows_none dir=w2_to_w1"
e_reset; r_prow 1800 "$(r_peer 10.0.1.10)" > "$R_FX/peer_rows_w2"; e_refuse "C.4-E19: the ok row about web-1 comes from WEB-1 (soleur-web-platform), not web-2: the dialing host is the direction" "reason=peer_rows_none dir=w2_to_w1"
e_reset; r_prow 1800 "$(r_peer 10.0.1.11)" soleur-web-2 > "$R_FX/peer_rows_w2"; e_refuse "C.4-E19b: web-2's ok row is about its own address, not web-1's" "reason=peer_row_malformed dir=w2_to_w1"
e_reset; r_prow 1800 "$(r_peer 10.0.1.10 skipped=exec_failed)" soleur-web-2 > "$R_FX/peer_rows_w2"; e_refuse "C.4-E19c: web-2's newest row is skipped=exec_failed" "reason=peer_skipped dir=w2_to_w1"
e_reset; { r_prow 7200 "$(r_peer 10.0.1.10)" soleur-web-2; r_prow 300 "$(r_peer 10.0.1.10 result=timeout)" soleur-web-2; } > "$R_FX/peer_rows_w2"; e_refuse "C.4-E19d: a NEWER web-2 timeout beats an older ok" "reason=peer_timeout dir=w2_to_w1"
e_reset; printf '503' > "$R_FX/peer_mode_w2"; e_refuse "C.4-E19e: Better Stack answers 503 to the reverse peer query" "peer probe of web-1 FAILED"
e_reset; r_prow 3600 "$(r_peer 10.0.1.11 result=refused)" > "$R_FX/peer_rows"; e_refuse "C.4-E19f: forward refused is labelled w1_to_w2 (the two directions carry distinct labels)" "reason=peer_refused dir=w1_to_w2"
e_reset; printf '{"values":{"root_module":{"resources":[{"address":"hcloud_server_network.web[\\"web-2\\"]","values":{"ip":"10.0.1.11"}}]}}}' > "$R_FX/state"; e_refuse "C.4-E20: web-1's private address absent from state" "web-1's private IPv4 is absent from state"
e_reset; r_state 10.0.1.10; e_refuse "C.4-E20b: state gives web-1 and web-2 the SAME address (a self-probe proves nothing)" "web-1's private IPv4 is absent from state or equals web-2's"
e_reset; { r_row 20 "$(r_line listening 0.0.0.0 8443 0)"; r_row 80 "$(r_line listening 0.0.0.0 8443 0)"; } > "$R_FX/rows"; r_exec
c4_assert "C.4-E12: workspaces_populated=0 is RECORDED, not judged (owner ruling 2026-11-06) → exit 0 and a GREEN line" \
  "$([[ "$R_RC" -eq 0 && "$(cat "$R_WORK/summary")" == *GREEN* ]] && echo 1 || echo 0)"
e_reset; { r_row 20 "$(r_line) extra=1"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E13: trailing text after the grammar (substring match must not pass)" "reason=row_malformed"
e_reset; { r_row 20 "x$(r_line)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E13b: leading text before the grammar" "reason=row_malformed"
e_reset; { r_row 20 "$(r_line)" soleur-web-platform; r_row 80 "$(r_line)" soleur-web-platform; } > "$R_FX/rows"; e_refuse "C.4-E14: rows from another host do not count" "reason=rows_below_floor"
e_reset; touch "$R_FX/tf.fail"; e_refuse "C.4-E15: terraform show -json fails" "terraform show -json failed"
e_reset; printf '{"values":{"root_module":{"resources":[]}}}' > "$R_FX/state"; e_refuse "C.4-E16: web-2's private address absent from state" "private IPv4 is absent from state"
e_reset; printf '{"values":{"root_module":{"resources":[{"address":"hcloud_server_network.web[\\"web-2\\"]","values":{"ip":"not-an-ip"}}]}}}' > "$R_FX/state"; e_refuse "C.4-E16b: web-2's state address is not a private IPv4" "private IPv4 is absent from state"
else
  c4_bad "C.4-E*: the probe step has no run body — the execute-the-step fixtures cannot run (vacuity refused)"
fi

# =============================================================================
# §A1 — A.1 stays deleted, and NOTHING keyed on SOLEUR_PROXY_BIND may creep back in.
#   Matrix: every row runs the gate with SOLEUR_PROXY_BIND set / empty / absent COMBINED with one invalid A or B
#     input and asserts the SPECIFIC sub_condition (so a bypass keyed on the bind, which would exit 0 on
#     bind-set while the pristine gate refuses, is caught), plus the OK rows (no bind -> SHAPE-ONLY marker).
#   Static: no non-comment line of the gate mentions PROXY_BIND (with or without the SOLEUR_ prefix) and the
#     retired sub-condition id is gone. (An indirect form such as v=SOLEUR_PROXY_; ${v}BIND is NOT detected
#     statically; the matrix rows are the behavioral backstop for it.)
#   Mutation: copies of the gate with (a) an A.1-style refusal re-introduced, (b) a bind-keyed exit-0 bypass and
#     (c) an unprefixed PROXY_BIND read are graded by the SAME matrix / static helpers the pristine gate is; each
#     mutation is asserted to have LANDED (differs from the pristine gate and carries the injected text) and
#     each must turn a helper RED.
# =============================================================================
# a1_apply <bind: a value | EMPTY | ABSENT> <var|-> <val|__UNSET__> — set DEF and run the gate
a1_apply() {
  reset_def
  case "$1" in
    ABSENT) ;;
    EMPTY) DEF[SOLEUR_PROXY_BIND]='' ;;
    *) DEF[SOLEUR_PROXY_BIND]="$1" ;;
  esac
  if [[ "$2" != "-" ]]; then
    if [[ "$3" == "__UNSET__" ]]; then unset "DEF[$2]"; else DEF[$2]="$3"; fi
  fi
  run_with_def
}
# bind|var|val|expected (OK = exit 0 with the marker, else the refusing sub_condition)
A1_MATRIX='10.0.1.10|-|-|OK
ABSENT|-|-|OK
EMPTY|-|-|OK
   |-|-|OK
10.0.1.10|GIT_DATA_STORE_ENABLED|false|B_git_data_store_disabled
ABSENT|GIT_DATA_STORE_ENABLED|false|B_git_data_store_disabled
EMPTY|GIT_DATA_STORE_ENABLED|false|B_git_data_store_disabled
10.0.1.10|SOLEUR_HOST_ROSTER|{"web-1":"10.0.1.10"}|A_web2_not_in_roster
10.0.1.10|SOLEUR_PROXY_PEER_ALLOWLIST|__UNSET__|A_peer_allowlist_empty
EMPTY|SOLEUR_PROXY_PEER_ALLOWLIST|__UNSET__|A_peer_allowlist_empty
10.0.1.10|WORKSPACES_LUKS_CUTOVER_AT|__UNSET__|B_workspaces_luks_marker_absent'
# a1_row_ok <bind> <var> <val> <expected> — 0 iff the current $GATE behaves as expected for the row
a1_row_ok() {
  a1_apply "$1" "$2" "$3"
  if [[ "$4" == "OK" ]]; then
    [[ "$GATE_RC" -eq 0 && "$GATE_OUT" == *"requires_runtime_bind_probe=true"* ]]
  else
    [[ "$GATE_RC" -ne 0 ]] && has_gate_fail "$GATE_ERR" "$4"
  fi
}
# a1_matrix_mismatches — how many matrix rows the current $GATE fails (silent)
a1_matrix_mismatches() {
  local n=0 b v val exp
  while IFS='|' read -r b v val exp; do
    a1_row_ok "$b" "$v" "$val" "$exp" || n=$((n + 1))
  done <<<"$A1_MATRIX"
  echo "$n"
}
# a1_static_hits <file> — non-comment lines mentioning PROXY_BIND in any spelling
a1_static_hits() {
  local n=0 l
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" =~ ^[[:space:]]*# ]] && continue
    [[ "$l" == *PROXY_BIND* ]] && n=$((n + 1))
  done <"$1"
  echo "$n"
}

# --- matrix rows against the pristine gate (each is its own reported assertion) ---
while IFS='|' read -r a1_b a1_v a1_val a1_exp; do
  a1_apply "$a1_b" "$a1_v" "$a1_val"
  if [[ "$a1_exp" == "OK" ]]; then
    assert_zero "A1-matrix: bind='${a1_b}' + valid A/B -> exit 0"
    assert_stdout_contains "A1-matrix: bind='${a1_b}' + valid A/B -> SHAPE-ONLY marker" "requires_runtime_bind_probe=true"
  else
    assert_rejects_with "A1-matrix: bind='${a1_b}' + ${a1_v}=${a1_val} refuses" "$a1_exp"
  fi
done <<<"$A1_MATRIX"

# --- static rows ---
TOTAL=$((TOTAL + 1))
a1_hits="$(a1_static_hits "$GATE")"
if [[ "$a1_hits" -eq 0 ]]; then PASS=$((PASS + 1)); echo "  PASS: A1-static: no non-comment line of lb-weight-gate.sh mentions PROXY_BIND (any spelling)"
else FAIL=$((FAIL + 1)); echo "  FAIL: A1-static: $a1_hits non-comment line(s) of lb-weight-gate.sh mention PROXY_BIND"; fi
assert_no_grep "A1-static: the retired A_proxy_bind_empty sub-condition id is gone from the gate" lb-weight-gate.sh \
  'A_proxy_bind_empty'

# --- mutation rows ---
A1_TMP="$(mktemp -d)"
trap 'rm -rf "$A1_TMP" "${R_WORK:-}"' EXIT
GATE_PRISTINE="$GATE"
# a1_mutate <label> <injected-line> <red-by: matrix|static> — copy the gate with <injected-line> before the PARITY
# POINTER, assert it LANDED, then require the named helper to go RED on the copy. The pristine gate is the control.
a1_mutate() {
  local label="$1" inject="$2" redby="$3" mut="$A1_TMP/lb-weight-gate.sh" got
  sed "/^# PARITY POINTER:/i $inject" "$GATE_PRISTINE" > "$mut"
  TOTAL=$((TOTAL + 1))
  if cmp -s "$mut" "$GATE_PRISTINE" || [[ "$(cat "$mut")" != *"$inject"* ]]; then
    FAIL=$((FAIL + 1)); echo "  FAIL: A1-mutation $label: the mutation did NOT land (byte-identical to the pristine gate)"; return
  fi
  PASS=$((PASS + 1)); echo "  PASS: A1-mutation $label: the mutation LANDED"
  TOTAL=$((TOTAL + 1))
  if [[ "$redby" == "matrix" ]]; then GATE="$mut"; got="$(a1_matrix_mismatches)"; GATE="$GATE_PRISTINE"
  else got="$(a1_static_hits "$mut")"; fi
  if [[ "$got" -gt 0 ]]; then PASS=$((PASS + 1)); echo "  PASS: A1-mutation $label: the $redby check goes RED ($got)"
  else FAIL=$((FAIL + 1)); echo "  FAIL: A1-mutation $label: the $redby check stayed green — the guard is vacuous"; fi
}
# control: the pristine gate is green under both helpers
TOTAL=$((TOTAL + 1))
if [[ "$(a1_matrix_mismatches)" -eq 0 && "$(a1_static_hits "$GATE_PRISTINE")" -eq 0 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: A1-control: the pristine gate is green under the matrix and the static helper"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: A1-control: the pristine gate is not green under the A1 helpers"
fi
a1_mutate "re-introduced refusal" '[[ -n "${SOLEUR_PROXY_BIND-}" ]] || fail "A_proxy_bind_empty"' matrix
a1_mutate "bind-keyed exit-0 bypass" '[[ -z "${SOLEUR_PROXY_BIND-}" ]] || { echo requires_runtime_bind_probe=true; echo SHAPE-ONLY; exit 0; }' matrix
a1_mutate "unprefixed PROXY_BIND read" '[[ -n "${PROXY_BIND-}" ]] || fail "A_unprefixed_bind"' static
GATE="$GATE_PRISTINE"

# =============================================================================
# §SK — #12849: the soak floor (Guard 1), the soak evidence line (Guard 2), the per-instance grader precondition
#        in the serve arm (Guard 3) and the gate-chain summary mirror + anti-vacuity check (Guard 4).
#   The grammar exists ONCE, as SOAK_EV_RE / INSTANCE_EV_RE in scripts/lib/serve-soak-evidence.sh (G4): this suite
#   SOURCES it, so the producer rows (the real gate's stderr) and the consumer rows (the helper's mirror and pass
#   re-check) are graded by the same text. Rows marked "committed mutation" mutate a sandbox copy of the workflow
#   (textual YAML pins only, G5); behaviour mutations are run by hand once and recorded in the PR body.
#   Each subsection declares its row count and a counter refuses a subsection whose rows did not all execute.
# =============================================================================
SSE_LIB="$REPO_ROOT/scripts/lib/serve-soak-evidence.sh"
SSE_PROBE="$REPO_ROOT/scripts/serve-soak-evidence-last.sh"
GRADER_FILE="$REPO_ROOT/scripts/followthroughs/web2-luks-live-6931.sh"
WRAPPER_FILE="$SCRIPT_DIR/lb-weight-gate-with-marker.sh"
ROWS_LIB_FILE="$REPO_ROOT/scripts/lib/web2-luks-rows.sh"
BASH_BIN="$(command -v bash)"
SK_WORK="$(mktemp -d)"
trap 'rm -rf "$A1_TMP" "${R_WORK:-}" "${SK_WORK:-}"' EXIT
SSE_LOADED=0
if [[ -f "$SSE_LIB" ]]; then
  # shellcheck source=scripts/lib/serve-soak-evidence.sh
  if source "$SSE_LIB" && [[ -n "${SOAK_EV_RE:-}" && -n "${INSTANCE_EV_RE:-}" && -n "${SOAK_FLOOR_S:-}" ]]; then SSE_LOADED=1; fi
fi
if [[ "$SSE_LOADED" -ne 1 ]]; then SOAK_EV_RE='SSE_HELPER_NOT_LOADED'; INSTANCE_EV_RE='SSE_HELPER_NOT_LOADED'; SOAK_FLOOR_S=0; fi

SEC_NAME=""; SEC_DECL=0; SEC_RAN=0
sec_open() { SEC_NAME="$1"; SEC_DECL="$2"; SEC_RAN=0; }
srow() { # <desc> <1|0> — one reported row of the current subsection
  SEC_RAN=$((SEC_RAN + 1)); TOTAL=$((TOTAL + 1))
  if [[ "$2" == 1 ]]; then PASS=$((PASS + 1)); echo "  PASS: $1"; else FAIL=$((FAIL + 1)); echo "  FAIL: $1"; fi
}
sk_check() { # <desc> <predicate...> — runs the predicate in THIS shell (never inside $( )) and reports one row
  local d="$1"; shift
  if "$@"; then srow "$d" 1; else srow "$d" 0; fi
}
sk_instrument() { # srow and sk_check must be able to report a FAIL; graded and reported without srow itself (test-design P1)
  local out
  out="$(PASS=0; FAIL=0; TOTAL=0; SEC_RAN=0; srow instr-a 0; srow instr-b 1; sk_check instr-c false; sk_check instr-d true; echo "P=$PASS F=$FAIL")"
  TOTAL=$((TOTAL + 1))
  if [[ "$out" == *"FAIL: instr-a"*"PASS: instr-b"*"FAIL: instr-c"*"PASS: instr-d"*"P=2 F=2" ]]; then PASS=$((PASS + 1)); echo "  PASS: §SK instrument: srow and sk_check report both verdicts"
  else FAIL=$((FAIL + 1)); echo "  FAIL: §SK instrument: srow/sk_check cannot report a failure (${out//$'\n'/ | })"; fi
}
sec_close() { # the subsection's own-dispatch guard: every declared row executed, no more, no fewer
  TOTAL=$((TOTAL + 1))
  if [[ "$SEC_RAN" -eq "$SEC_DECL" ]]; then PASS=$((PASS + 1)); echo "  PASS: §SK-${SEC_NAME}: ${SEC_RAN} of ${SEC_DECL} declared rows executed"
  else FAIL=$((FAIL + 1)); echo "  FAIL: §SK-${SEC_NAME}: ${SEC_RAN} rows executed, ${SEC_DECL} declared (a row was skipped or added without its count)"; fi
}

# --- evidence-line readers over $GATE_ERR (set by run_with_def; these only read it) -----------------------------
ev_lines() { # <kind|any> -> the lines of $GATE_ERR that FULLY match the grammar (of that kind)
  local l re="^${SOAK_EV_RE}\$"
  while IFS= read -r l; do
    [[ "$l" =~ $re ]] || continue
    if [[ "$1" == any || "$l" == "SOLEUR_SOAK_EVIDENCE kind=$1 "* ]]; then printf '%s\n' "$l"; fi
  done <<<"$GATE_ERR"
  return 0
}
raw_ev_n() { # <kind|any> -> how many lines START with the evidence prefix (of that kind), well-formed or not
  local l n=0
  while IFS= read -r l; do
    if [[ "$l" == "SOLEUR_SOAK_EVIDENCE "* ]] && [[ "$1" == any || "$l" == "SOLEUR_SOAK_EVIDENCE kind=$1 "* ]]; then n=$((n + 1)); fi
  done <<<"$GATE_ERR"
  echo "$n"
}
ev_field() { # <line> <name> -> the value of one field, anchored on (^| )name=([^ ]+)( |$)
  local re="(^| )$2=([^ ]+)( |\$)"
  if [[ "$1" =~ $re ]]; then printf '%s' "${BASH_REMATCH[2]}"; fi
}
p_refuses() { if [[ "$GATE_RC" -eq 1 ]] && has_gate_fail "$GATE_ERR" "$1"; then return 0; fi; return 1; }
p_passes() { [[ "$GATE_RC" -eq 0 && "$GATE_OUT" == *requires_runtime_bind_probe=true* ]]; }
p_ev() { # <kind> <field=value>... — exactly one line of that kind, it matches the grammar, every named field equals
  local kind="$1" line kv; shift
  [[ "$(raw_ev_n "$kind")" -eq 1 ]] || return 1
  line="$(ev_lines "$kind")"
  [[ -n "$line" && "$line" != *$'\n'* ]] || return 1
  for kv in "$@"; do [[ "$(ev_field "$line" "${kv%%=*}")" == "${kv#*=}" ]] || return 1; done
  return 0
}
p_ev_none() { [[ "$(raw_ev_n "$1")" -eq 0 ]]; }
p_ev_age() { # <kind> <expected-seconds> — age_s within [expected, expected + elapsed-since-NOW + 120]
  # NOW is taken once at suite start and the markers are built from it, so the slack is the real time elapsed since
  # then plus 120 s: a contended host (the suite reaching §SK minutes after NOW) is not a soak-age defect.
  local a slack; a="$(ev_field "$(ev_lines "$1")" age_s)"; slack=$(( $(date -u +%s) - NOW + 120 ))
  if [[ "$a" =~ ^-?[0-9]+$ ]] && (( a >= $2 && a <= $2 + slack )); then return 0; fi
  return 1
}
p_one_verdict() { # <kind> — the raw line of that kind carries exactly one ` verdict=` token
  local l t
  while IFS= read -r l; do
    if [[ "$l" == "SOLEUR_SOAK_EVIDENCE kind=$1 "* ]]; then t="${l// verdict=/}"; (( (${#l} - ${#t}) == 9 )) || return 1; fi
  done <<<"$GATE_ERR"
  return 0
}

TWO_D_CUTOVER=$(ISO "$(( NOW - 2 * 86400 ))")
SIX_D_CUTOVER=$(ISO "$(( NOW - 6 * 86400 ))")
TEN_D_CUTOVER=$(ISO "$(( NOW - 10 * 86400 ))")
K1000_D_CUTOVER=$(ISO "$(( NOW - 1000 * 86400 ))")
SPACE_CUTOVER="$(date -u -d "@$(( NOW - 4 * 86400 ))" '+%Y-%m-%d %H:%M:%S')"

# -----------------------------------------------------------------------------------------------------------------
# §SK-floor — Guard 1: SOAK_FLOOR_DAYS=3; 1 and 2 refuse *_below_floor; 3, 5, 999 accept; 0, leading zeros, text,
#   a forged field, more than 3 digits and arithmetic-wrapping values refuse *_invalid (G1, F10); unset/empty = 3.
# -----------------------------------------------------------------------------------------------------------------
sk_instrument
sec_open floor 89
for sk_kn in git ws; do
  if [[ "$sk_kn" == git ]]; then
    KNOB=GIT_DATA_LUKS_SOAK_DAYS; MK=GIT_DATA_LUKS_CUTOVER_AT; KIND=git_data; PFX=B_luks
  else
    KNOB=WORKSPACES_LUKS_SOAK_DAYS; MK=WORKSPACES_LUKS_CUTOVER_AT; KIND=workspaces_luks; PFX=B_workspaces_luks
  fi
  for v in 1 2; do
    reset_def; DEF[$KNOB]="$v"; run_with_def
    sk_check "G1: $KNOB=$v (4-day markers) refuses ${PFX}_soak_days_below_floor (the whole gate_fail line)" p_refuses "${PFX}_soak_days_below_floor"
    sk_check "G1: $KNOB=$v: one $KIND line soak_days=$v source=env floor_days=3 required_s=none verdict=fail sub_condition=${PFX}_soak_days_below_floor" \
      p_ev "$KIND" "soak_days=$v" source=env floor_days=3 marker_at=none age_s=none required_s=none verdict=fail "sub_condition=${PFX}_soak_days_below_floor"
  done
  if [[ "$sk_kn" == git ]]; then sk_check "G1: a git-data refusal yields NO workspaces_luks line" p_ev_none workspaces_luks; fi
  reset_def; DEF[$KNOB]='3'; run_with_def
  sk_check "G1: $KNOB=3 with 4-day markers passes" p_passes
  sk_check "G1: $KNOB=3: $KIND line soak_days=3 source=env required_s=259200 verdict=pass sub_condition=none" p_ev "$KIND" soak_days=3 source=env required_s=259200 verdict=pass sub_condition=none
  reset_def; DEF[$KNOB]='5'; DEF[$MK]="$SIX_D_CUTOVER"; run_with_def
  sk_check "G1 H2: $KNOB=5 with a 6-day marker passes (a value may lengthen the soak)" p_passes
  sk_check "G1 H2: $KNOB=5: required_s=432000 source=env verdict=pass" p_ev "$KIND" soak_days=5 source=env required_s=432000 verdict=pass
  sk_check "G1 H2: $KNOB=5: age_s is the 6-day marker's age" p_ev_age "$KIND" $(( 6 * 86400 ))
  reset_def; DEF[$KNOB]='5'; run_with_def
  sk_check "G1 H2: $KNOB=5 with 4-day markers refuses ${PFX}_soak_not_elapsed (the lengthened soak is enforced)" p_refuses "${PFX}_soak_not_elapsed"
  sk_check "G1 H2: $KNOB=5 with 4-day markers: required_s=432000 verdict=fail" p_ev "$KIND" soak_days=5 required_s=432000 verdict=fail "sub_condition=${PFX}_soak_not_elapsed"
  reset_def; DEF[$KNOB]='999'; DEF[$MK]="$K1000_D_CUTOVER"; run_with_def
  sk_check "G1 H2: $KNOB=999 with a 1000-day marker passes (the 3-digit cap still allows any real lengthening)" p_passes
  sk_check "G1 H2: $KNOB=999: required_s=86313600 verdict=pass" p_ev "$KIND" soak_days=999 required_s=86313600 verdict=pass
  for v in 0 010 08 abc '1 verdict=pass' 1000 200000000000000 18446744073709551619; do
    reset_def; DEF[$KNOB]="$v"; run_with_def
    sk_check "G1: $KNOB='$v' refuses ${PFX}_soak_days_invalid" p_refuses "${PFX}_soak_days_invalid"
    sk_check "G1: $KNOB='$v': soak_days=invalid source=env required_s=none verdict=fail (the raw value is never printed)" \
      p_ev "$KIND" soak_days=invalid source=env required_s=none verdict=fail "sub_condition=${PFX}_soak_days_invalid"
    sk_check "G1: $KNOB='$v': the $KIND line carries exactly one verdict= token" p_one_verdict "$KIND"
  done
  reset_def; unset "DEF[$KNOB]"; run_with_def
  sk_check "G1: $KNOB unset passes with 4-day markers" p_passes
  sk_check "G1: $KNOB unset: source=default soak_days=3 required_s=259200" p_ev "$KIND" soak_days=3 source=default required_s=259200 verdict=pass
  reset_def; DEF[$KNOB]=''; run_with_def
  sk_check "G1: $KNOB empty passes with 4-day markers" p_passes
  sk_check "G1: $KNOB empty: source=default soak_days=3" p_ev "$KIND" soak_days=3 source=default required_s=259200 verdict=pass
  reset_def; unset "DEF[$KNOB]"; DEF[$MK]="$TWO_D_CUTOVER"; run_with_def
  sk_check "G1: $KNOB unset with a 2-day marker refuses ${PFX}_soak_not_elapsed (the default is the floor, never 1)" p_refuses "${PFX}_soak_not_elapsed"
  sk_check "G1: $KNOB unset with a 2-day marker: source=default soak_days=3 required_s=259200" p_ev "$KIND" soak_days=3 source=default required_s=259200 verdict=fail "sub_condition=${PFX}_soak_not_elapsed"
done
sk_floor_static() { # SOAK_FLOOR_DAYS=3 once, plain NAME= form, never read through an expansion that could take it from the env
  local nc; nc="$(grep -vE '^[[:space:]]*#' "$GATE" || true)"
  [[ "$(grep -cE '^SOAK_FLOOR_DAYS=3$' <<<"$nc" || true)" -eq 1 ]] || return 1
  ! grep -qE '\{SOAK_FLOOR_DAYS(:?[-=?+])' <<<"$nc"
}
sk_check "G1: the gate assigns the floor exactly once, in plain NAME= form (SOAK_FLOOR_DAYS=3; never a := expansion)" sk_floor_static
sk_knob_default() { # both knob reads default to the floor constant, never to a literal
  [[ "$(grep -cF 'SOAK_DAYS="${GIT_DATA_LUKS_SOAK_DAYS:-$SOAK_FLOOR_DAYS}"' "$GATE" || true)" -eq 1 ]] || return 1
  [[ "$(grep -cF 'WS_SOAK_DAYS="${WORKSPACES_LUKS_SOAK_DAYS:-$SOAK_FLOOR_DAYS}"' "$GATE" || true)" -eq 1 ]] || return 1
  return 0
}
sk_check "G1: both knob reads default to the floor (\${KNOB:-\$SOAK_FLOOR_DAYS}), never to a literal" sk_knob_default
sec_close

# -----------------------------------------------------------------------------------------------------------------
# §SK-evidence — Guard 2: one well-formed line per kind whose evaluation started; verdict and sub_condition equal
#   the gate's decision; zero lines on the standby branch, Condition A, B.1 and TOP refusals; no raw env text.
# -----------------------------------------------------------------------------------------------------------------
sec_open evidence 65
reset_def; run_with_def
sk_check "G2: full pass exits 0 with the flip marker" p_passes
sk_check "G2: full pass prints exactly two evidence lines" eval '[[ "$(raw_ev_n any)" -eq 2 && "$(ev_lines any | grep -c .)" -eq 2 ]]'
sk_check "G2: full pass: git_data line host=web-2 soak_days=3 source=env floor_days=3 marker_at=<the marker> required_s=259200 verdict=pass sub_condition=none" \
  p_ev git_data host=web-2 soak_days=3 source=env floor_days=3 "marker_at=$ELAPSED_CUTOVER" required_s=259200 verdict=pass sub_condition=none
sk_check "G2: full pass: workspaces_luks line, same shape" \
  p_ev workspaces_luks host=web-2 soak_days=3 source=env floor_days=3 "marker_at=$ELAPSED_CUTOVER" required_s=259200 verdict=pass sub_condition=none
sk_check "G2: full pass: git_data age_s is the marker age (4 d, within 120 s)" p_ev_age git_data $(( 4 * 86400 ))
sk_check "G2: full pass: workspaces_luks age_s is the marker age (4 d, within 120 s)" p_ev_age workspaces_luks $(( 4 * 86400 ))
sk_check "G2: the evidence goes to stderr, never stdout (stdout stays the flip marker + banner)" eval '[[ "$GATE_OUT" != *SOLEUR_SOAK_EVIDENCE* ]]'
# every refusal id in B.3-B.5 (git data; B.2's are in §SK-floor): exactly one git_data fail line, no workspaces line
for row in "B_luks_cutover_marker_absent|__UNSET__|none|none" \
           "B_luks_cutover_marker_unparseable|not-a-timestamp|unparseable|none" \
           "B_luks_cutover_marker_unparseable|2026-13-45T99:99:99Z|unparseable|none" \
           "B_luks_cutover_marker_pre_epoch|1960-01-01|1960-01-01T00:00:00Z|none" \
           "B_luks_cutover_marker_future|$FUTURE_CUTOVER|$FUTURE_CUTOVER|-" \
           "B_luks_soak_not_elapsed|$FRESH_CUTOVER|$FRESH_CUTOVER|-"; do
  IFS='|' read -r rid rval rmark rage <<<"$row"
  reset_def; if [[ "$rval" == __UNSET__ ]]; then unset 'DEF[GIT_DATA_LUKS_CUTOVER_AT]'; else DEF[GIT_DATA_LUKS_CUTOVER_AT]="$rval"; fi; run_with_def
  sk_check "G2: $rid ($rval) refuses with that id" p_refuses "$rid"
  if [[ "$rage" == none ]]; then
    sk_check "G2: $rid: one git_data line verdict=fail sub_condition=$rid marker_at=$rmark age_s=none required_s=259200" \
      p_ev git_data verdict=fail "sub_condition=$rid" "marker_at=$rmark" age_s=none required_s=259200
  else
    sk_check "G2: $rid: one git_data line verdict=fail sub_condition=$rid marker_at=$rmark required_s=259200" \
      p_ev git_data verdict=fail "sub_condition=$rid" "marker_at=$rmark" required_s=259200
  fi
  sk_check "G2: $rid: no workspaces_luks line (its evaluation never started)" p_ev_none workspaces_luks
done
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FUTURE_CUTOVER"; run_with_def
sk_check "G2: B_luks_cutover_marker_future: age_s is the negative delta (-2 d, within 120 s)" p_ev_age git_data $(( -2 * 86400 ))
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
sk_check "G2: B_luks_soak_not_elapsed: age_s is the marker age (1 d, within 120 s)" p_ev_age git_data 86400
# every refusal id in B.6-B.10 (workspaces; B.6's own are in §SK-floor): one workspaces fail line after one git pass line
for row in "B_workspaces_luks_marker_absent|WORKSPACES_LUKS_CUTOVER_AT|__UNSET__|none|none" \
           "B_workspaces_luks_marker_other_host|WORKSPACES_LUKS_MARKER_HOST|__UNSET__|none|none" \
           "B_workspaces_luks_marker_unparseable|WORKSPACES_LUKS_CUTOVER_AT|not-a-timestamp|unparseable|none" \
           "B_workspaces_luks_marker_unparseable|WORKSPACES_LUKS_CUTOVER_AT|2026-13-45T99:99:99Z|unparseable|none" \
           "B_workspaces_luks_marker_pre_epoch|WORKSPACES_LUKS_CUTOVER_AT|1960-01-01|1960-01-01T00:00:00Z|none" \
           "B_workspaces_luks_marker_future|WORKSPACES_LUKS_CUTOVER_AT|$FUTURE_CUTOVER|$FUTURE_CUTOVER|-" \
           "B_workspaces_luks_soak_not_elapsed|WORKSPACES_LUKS_CUTOVER_AT|$FRESH_CUTOVER|$FRESH_CUTOVER|-"; do
  IFS='|' read -r rid rvar rval rmark rage <<<"$row"
  reset_def; if [[ "$rval" == __UNSET__ ]]; then unset "DEF[$rvar]"; else DEF[$rvar]="$rval"; fi; run_with_def
  sk_check "G2: $rid ($rvar=$rval) refuses with that id" p_refuses "$rid"
  if [[ "$rage" == none ]]; then
    sk_check "G2: $rid: one workspaces_luks line verdict=fail sub_condition=$rid marker_at=$rmark age_s=none required_s=259200" \
      p_ev workspaces_luks verdict=fail "sub_condition=$rid" "marker_at=$rmark" age_s=none required_s=259200
  else
    sk_check "G2: $rid: one workspaces_luks line verdict=fail sub_condition=$rid marker_at=$rmark required_s=259200" \
      p_ev workspaces_luks verdict=fail "sub_condition=$rid" "marker_at=$rmark" required_s=259200
  fi
  sk_check "G2: $rid: exactly one git_data line, verdict=pass sub_condition=none (the git-data soak was met first)" p_ev git_data verdict=pass sub_condition=none
done
reset_def; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$FUTURE_CUTOVER"; run_with_def
sk_check "G2: B_workspaces_luks_marker_future: age_s is the negative delta" p_ev_age workspaces_luks $(( -2 * 86400 ))
# zero lines where no soak kind's evaluation started
reset_def; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'; DEF[SOLEUR_SERVING_ROTATION]='web-1'; run_with_def
sk_check "G2: the weight-0 standby pass prints ZERO evidence lines" eval '[[ "$GATE_RC" -eq 0 && "$(raw_ev_n any)" -eq 0 ]]'
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10"}'; run_with_def
sk_check "G2: a Condition A refusal (A_web2_not_in_roster) prints its gate_fail line and ZERO evidence lines" eval 'p_refuses A_web2_not_in_roster && [[ "$(raw_ev_n any)" -eq 0 ]]'
reset_def; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
sk_check "G2: a B.1 refusal (B_git_data_store_disabled) prints its gate_fail line and ZERO evidence lines" eval 'p_refuses B_git_data_store_disabled && [[ "$(raw_ev_n any)" -eq 0 ]]'
reset_def; unset 'DEF[SOLEUR_GATED_HOST]'; run_with_def
sk_check "G2: a TOP refusal (TOP_gated_host_absent) still prints its gate_fail line under set -u (EV_KIND is initialised before fail()) and ZERO evidence lines" eval 'p_refuses TOP_gated_host_absent && [[ "$(raw_ev_n any)" -eq 0 ]]'
# no raw environment text: offset and space-separated markers come back as the epoch-rebuilt Z form
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$TZOFFSET_CUTOVER"; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$TZOFFSET_CUTOVER"; run_with_def
sk_check "G2: a +02:00 git-data marker is printed as its Z-form rebuild" p_ev git_data "marker_at=$ELAPSED_CUTOVER" verdict=pass
sk_check "G2: a +02:00 workspaces marker is printed as its Z-form rebuild" p_ev workspaces_luks "marker_at=$ELAPSED_CUTOVER" verdict=pass
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$SPACE_CUTOVER"; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$SPACE_CUTOVER"; run_with_def
sk_check "G2: a space-separated git-data marker still yields a grammar-matching Z-form line" p_ev git_data "marker_at=$ELAPSED_CUTOVER" verdict=pass
sk_check "G2: a space-separated workspaces marker still yields a grammar-matching Z-form line" p_ev workspaces_luks "marker_at=$ELAPSED_CUTOVER" verdict=pass
# the age window is per kind: markers 6 days apart
reset_def; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$TEN_D_CUTOVER"; run_with_def
sk_check "G2: per-kind age: the git_data line reads the git-data marker (4 d)" p_ev_age git_data $(( 4 * 86400 ))
sk_check "G2: per-kind age: the workspaces_luks line reads the workspaces marker (10 d), not the git-data one" p_ev_age workspaces_luks $(( 10 * 86400 ))
sk_check "G2: per-kind marker: the workspaces_luks line prints its own marker" p_ev workspaces_luks "marker_at=$TEN_D_CUTOVER"
# H2: the host is not hardcoded — web-3 pooled on web-2's marker
reset_def; DEF[SOLEUR_GATED_HOST]='web-3'; DEF[SOLEUR_SERVING_ROTATION]='web-1,web-3'; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.12'; DEF[SOLEUR_HOST_ROSTER]="$R13"; run_with_def
sk_check "G2 H2: web-3 on web-2's marker refuses B_workspaces_luks_marker_other_host" p_refuses B_workspaces_luks_marker_other_host
sk_check "G2 H2: web-3: the git_data line says host=web-3 verdict=pass" p_ev git_data host=web-3 verdict=pass sub_condition=none
sk_check "G2 H2: web-3: the workspaces_luks line says host=web-3 marker_at=none sub_condition=B_workspaces_luks_marker_other_host" \
  p_ev workspaces_luks host=web-3 marker_at=none age_s=none verdict=fail sub_condition=B_workspaces_luks_marker_other_host
sk_check "G2: the gate names the grammar's one copy (SOAK_EV_RE in scripts/lib/serve-soak-evidence.sh) at its emit site" \
  eval 'grep -qF "SOAK_EV_RE" "$GATE" && grep -qF "scripts/lib/serve-soak-evidence.sh" "$GATE"'
sk_check "G2: the gate header records ^gate_fail sub_condition= as the only refusal contract (the evidence line is non-authoritative)" \
  eval 'grep -qE "^#.*\\^gate_fail sub_condition=.*only refusal contract" "$GATE"'
sec_close

# -----------------------------------------------------------------------------------------------------------------
# §SK-grammar — G4: the ONE grammar copy, its positive and negative fixtures, and the F8/G8 parity rows.
# -----------------------------------------------------------------------------------------------------------------
sec_open grammar 26
sk_check "G4: scripts/lib/serve-soak-evidence.sh loads and defines SOAK_EV_RE, INSTANCE_EV_RE and SOAK_FLOOR_S" eval '[[ "$SSE_LOADED" -eq 1 ]]'
re_full() { local re="^$1\$"; [[ "$2" =~ $re ]]; }
EVP='SOLEUR_SOAK_EVIDENCE kind=git_data host=web-2 soak_days=3 source=default floor_days=3 marker_at=2026-11-17T12:18:54Z age_s=87883 required_s=259200 verdict=pass sub_condition=none'
for fx in "$EVP" \
  'SOLEUR_SOAK_EVIDENCE kind=workspaces_luks host=web-2 soak_days=1 source=env floor_days=3 marker_at=2026-11-17T12:18:54Z age_s=87883 required_s=none verdict=fail sub_condition=B_workspaces_luks_soak_days_below_floor' \
  'SOLEUR_SOAK_EVIDENCE kind=git_data host=web-3 soak_days=invalid source=env floor_days=3 marker_at=none age_s=none required_s=none verdict=fail sub_condition=B_luks_soak_days_invalid' \
  'SOLEUR_SOAK_EVIDENCE kind=git_data host=web-2 soak_days=3 source=default floor_days=3 marker_at=unparseable age_s=none required_s=259200 verdict=fail sub_condition=B_luks_cutover_marker_unparseable' \
  'SOLEUR_SOAK_EVIDENCE kind=workspaces_luks host=web-2 soak_days=3 source=default floor_days=3 marker_at=2026-11-20T12:18:54Z age_s=-172800 required_s=259200 verdict=fail sub_condition=B_workspaces_luks_marker_future'; do
  sk_check "G4 positive fixture matches SOAK_EV_RE: ${fx:21:60}..." re_full "$SOAK_EV_RE" "$fx"
done
for fx in "$EVP extra=1" \
  "${EVP/ source=default/}" \
  "${EVP/soak_days=3 source=default/source=default soak_days=3}" \
  "${EVP/soak_days=3/soak_days=1 verdict=pass}" \
  "${EVP/verdict=pass/verdict=pass verdict=fail}" \
  "${EVP/kind=git_data/kind=other}" \
  "${EVP/soak_days=3/soak_days=010}" \
  "${EVP/soak_days=3/soak_days=1000}" \
  "${EVP/marker_at=2026-11-17T12:18:54Z/marker_at=2026-11-17 12:18:54}" \
  "${EVP/sub_condition=none/sub_condition=none\`}" \
  "x$EVP"; do
  sk_check "G4 negative fixture does NOT match SOAK_EV_RE: ...${fx: -50}" eval '! re_full "$SOAK_EV_RE" "$fx"'
done
sk_check "G4: INSTANCE_EV_RE matches the PASS line and the host=invalid rc=none CANNOT_ESTABLISH line" \
  eval 're_full "$INSTANCE_EV_RE" "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=PASS" && re_full "$INSTANCE_EV_RE" "SOLEUR_INSTANCE_SOAK host=invalid grader=web2-luks-live-6931 rc=none verdict=CANNOT_ESTABLISH"'
sk_check "G4: INSTANCE_EV_RE refuses an unknown verdict word, a trailing field and a NOT YET with a space" \
  eval '! re_full "$INSTANCE_EV_RE" "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=OK" && ! re_full "$INSTANCE_EV_RE" "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=PASS x=1" && ! re_full "$INSTANCE_EV_RE" "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=2 verdict=NOT YET"'
sk_check "R9: INSTANCE_EV_RE matches the rc=interrupted line (a cancel/timeout, distinct from rc=none)" \
  eval 're_full "$INSTANCE_EV_RE" "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=interrupted verdict=CANNOT_ESTABLISH"'
sk_check "GRADE_TEXT_RE accepts a verdict-shaped line and refuses a backtick (fence break-out) or a workflow command" \
  eval '[[ "PASS: ok — 3 days" =~ $GRADE_TEXT_RE && ! "NOT YET: x \`\`\`" =~ $GRADE_TEXT_RE && ! "::error::x" =~ $GRADE_TEXT_RE ]]'
sk_check "test-design P3: has_gate_fail is whole-line anchored (an evidence line ending sub_condition=X is not a gate_fail line)" \
  eval '! has_gate_fail "SOLEUR_SOAK_EVIDENCE kind=git_data verdict=fail sub_condition=B_luks_soak_not_elapsed" B_luks_soak_not_elapsed && has_gate_fail "gate_fail sub_condition=B_luks_soak_not_elapsed" B_luks_soak_not_elapsed'
sk_one_grammar() { # the grammar is assigned in exactly one non-test file of the tree: the helper
  local got
  got="$(cd "$REPO_ROOT" && grep -rlE --exclude-dir=node_modules '^(readonly[[:space:]]+)?SOAK_EV_RE=' apps scripts .github tests plugins 2>/dev/null | grep -v '\.test\.' | LC_ALL=C sort | tr '\n' ' ' || true)"
  [[ "$got" == "scripts/lib/serve-soak-evidence.sh " ]]
}
sk_check "G4: SOAK_EV_RE is defined in exactly one non-test file of the tree (the helper)" sk_one_grammar
sk_parity() { # F8/G8: grader SOAK_DAYS == gate SOAK_FLOOR_DAYS (both non-empty); helper SOAK_FLOOR_S == both * 86400
  local g f s
  g="$(sed -nE 's/^SOAK_DAYS=([0-9]+)$/\1/p' "$GRADER_FILE")"; f="$(sed -nE 's/^SOAK_FLOOR_DAYS=([0-9]+)$/\1/p' "$GATE")"
  s="$(sed -nE 's/^readonly SOAK_FLOOR_S=([0-9]+)$/\1/p' "$SSE_LIB" 2>/dev/null)"
  [[ -n "$g" && -n "$f" && -n "$s" && "$g" != *$'\n'* && "$f" != *$'\n'* && "$s" != *$'\n'* ]] || return 1
  [[ "$g" == "$f" && "$s" -eq $(( f * 86400 )) && "$s" -eq $(( g * 86400 )) && "$SOAK_FLOOR_S" == "$s" ]]
}
sk_check "F8/G8 parity: grader SOAK_DAYS = gate SOAK_FLOOR_DAYS, and the helper's SOAK_FLOOR_S = both x 86400" sk_parity
sk_check "F8: the grader's comment above SOAK_DAYS=3 names SOAK_FLOOR_DAYS and the parity row" \
  eval '[[ "$(grep -B1 -E "^SOAK_DAYS=3\$" "$GRADER_FILE" | head -1)" == *SOAK_FLOOR_DAYS* && "$(grep -B1 -E "^SOAK_DAYS=3\$" "$GRADER_FILE" | head -1)" == *parity* ]]'
sk_census_substring() { # every sub_condition= check in both gate suites is anchored on the whole gate_fail line
  local needle='*"''sub_condition=' f n=0
  for f in "$SCRIPT_DIR/lb-weight-gate.test.sh" "$SCRIPT_DIR/lb-weight-gate-with-marker.test.sh"; do
    n=$(( n + $(grep -vE '^[[:space:]]*#' "$f" | grep -cF -- "$needle" || true) ))
  done
  [[ "$n" -eq 0 ]]
}
sk_check "census: no sub_condition= substring check remains in either gate suite (all anchored on the whole gate_fail line)" sk_census_substring
sec_close

# -----------------------------------------------------------------------------------------------------------------
# §SK-wiring — Guard 3 / Guard 4 YAML wiring + host parity + knob census, each with committed mutation rows (G5).
# -----------------------------------------------------------------------------------------------------------------
sk_job() { awk '/^  ga_pool_update:/ {on=1; print; next} on && /^  [A-Za-z0-9_-]+:/ {exit} on {print}' "$1" 2>/dev/null || true; }
sk_step() { # <job-text> <ERE on the - name: line>
  PAT="$2" awk '/^      - / { if (on) exit; if ($0 ~ /^      - name:/ && $0 ~ ENVIRON["PAT"]) on = 1 } on { print }' <<<"$1"
}
sk_line() { local n; n="$(grep -nE "^      - name:.*($2)" <<<"$1" | head -1 | cut -d: -f1 || true)"; echo "${n:-0}"; }
sk_run() { awk '/^        run: \|[[:space:]]*$/ {on=1; next} on {print}' <<<"$1" | sed -E 's/^          //'; }
sk_nc() { grep -vE '^[[:space:]]*#' <<<"$1" || true; }
SK_GRADER_CALL='sse_instance_soak "$SOLEUR_GATED_HOST" "${GITHUB_WORKSPACE}/scripts/followthroughs/web2-luks-live-6931.sh"'
SK_LOAD_GRADER='source "$sse_f" && declare -F sse_instance_soak >/dev/null || { echo "::error::serve-soak-evidence helper not loaded ($sse_f) - wiring defect, do not re-dispatch"; exit 1; }'
SK_LOAD_GATE='source "$sse_f" && declare -F sse_gate_chain_mirror >/dev/null && declare -F sse_gate_chain_verify >/dev/null || { echo "::error::serve-soak-evidence helper not loaded ($sse_f) - wiring defect, do not re-dispatch"; exit 1; }'
SK_SSE_F='sse_f="${GITHUB_WORKSPACE}/scripts/lib/serve-soak-evidence.sh"'
SK_MIRROR='sse_gate_chain_mirror "${RUNNER_TEMP}/lb-gate.stderr" "$SOLEUR_GATED_HOST" "$gate_rc"'
SK_BACKSTOP='[[ "$gate_rc" -eq 0 ]] || exit 1'
SK_VERIFY='sse_gate_chain_verify "${RUNNER_TEMP}/lb-gate.stderr" "$SOLEUR_GATED_HOST"'
SK_TRAP="trap 'cat \"\${RUNNER_TEMP}/lb-gate.stderr\" >&2; rm -f \"\${RUNNER_TEMP}/lb-gate.stderr\"' EXIT"
SK_INNER_ENV='env -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS -u PS4 DOPPLER_TOKEN="$DOPPLER_TOKEN_LUKS_MARKER" DOPPLER_BIN="${RUNNER_TEMP}/doppler-cli/doppler" \'

sk_grader_ok() { # <workflow> -> 0 iff the grader step is wired as Guard 3 requires (AC8)
  local job st nc run runnc keys envs want ga gr he pl
  job="$(sk_job "$1")"; [[ -n "$job" ]] || return 1
  [[ "$(grep -cE '^      - name: per-instance soak grader \(serve only\)[[:space:]]*$' <<<"$job" || true)" -eq 1 ]] || return 1
  st="$(sk_step "$job" 'per-instance soak grader \(serve only\)')"; nc="$(sk_nc "$st")"
  keys="$(sed -nE 's/^      - (name):.*/\1/p; s/^        ([A-Za-z_-]+):.*/\1/p' <<<"$nc" | tr '\n' ',')"
  [[ "$keys" == "name,if,env,run," ]] || return 1
  grep -qxE "        if: inputs\.mode == 'serve'" <<<"$nc" || return 1
  envs="$(awk '/^        env:/ {on=1; next} /^        [A-Za-z]/ {on=0} on' <<<"$nc" | LC_ALL=C sort | tr '\n' '|')"
  want="$(printf '%s\n' '          SOLEUR_GATED_HOST: web-2' \
    '          BETTERSTACK_QUERY_HOST: ${{ secrets.BETTERSTACK_QUERY_HOST }}' \
    '          BETTERSTACK_QUERY_USERNAME: ${{ secrets.BETTERSTACK_QUERY_USERNAME }}' \
    '          BETTERSTACK_QUERY_PASSWORD: ${{ secrets.BETTERSTACK_QUERY_PASSWORD }}' | LC_ALL=C sort | tr '\n' '|')"
  [[ "$envs" == "$want" ]] || return 1
  run="$(sk_run "$st")"; runnc="$(sk_nc "$run")"
  [[ "$(head -1 <<<"$runnc")" == "set -euo pipefail" ]] || return 1
  ! grep -qF 'secrets.' <<<"$runnc" || return 1
  ! grep -qE 'continue-on-error|\|\|[[:space:]]*true|set[[:space:]]+\+e|^[[:space:]]*shell:' <<<"$nc" || return 1
  ! grep -qE '^    defaults:' <<<"$job" || return 1
  # the helper owns this step's traps (R7): any trap here (an ERR trap that exits 0) could turn its refusal green
  ! grep -qE '(^|[;&|[:space:]])trap([[:space:]]|$)' <<<"$runnc" || return 1
  grep -qxF '# shellcheck source=scripts/lib/serve-soak-evidence.sh' <<<"$run" || return 1
  grep -qxF -- "$SK_SSE_F" <<<"$runnc" || return 1
  [[ "$(grep -cxF -- "$SK_LOAD_GRADER" <<<"$runnc" || true)" -eq 1 ]] || return 1
  [[ "$(grep -cxF -- "$SK_GRADER_CALL" <<<"$runnc" || true)" -eq 1 ]] || return 1
  [[ "$(grep -c 'sse_instance_soak' <<<"$runnc" || true)" -eq 2 ]] || return 1
  # the whole non-comment body, line for line (test-design P2: `set +o errexit` / `exit 0` slip past any denylist)
  [[ "$(grep -v '^[[:space:]]*$' <<<"$runnc")" == "$(printf '%s\n' 'set -euo pipefail' "$SK_SSE_F" "$SK_LOAD_GRADER" "$SK_GRADER_CALL")" ]] || return 1
  ga="$(sk_line "$job" '§\(c\) gate chain')"; gr="$(sk_line "$job" 'per-instance soak grader \(serve only\)')"
  he="$(sk_line "$job" 'web-2 health precondition')"; pl="$(sk_line "$job" 'Terraform plan \(GA pool')"
  [[ "$ga" -gt 0 && "$gr" -gt "$ga" && "$he" -gt "$gr" && "$pl" -gt "$gr" ]] || return 1
  return 0
}
# the gate step's whole non-comment run body, line for line (fix round, test-design P2: `exit "0"` / `exit 00` slip
# past any errexit denylist; the flip-marker `if` line is pinned by the same snapshot)
SK_GATE_BODY="$(cat <<'SKGATEBODY'
set -euo pipefail
GATE_OUT=""
gate_rc=0
: >"${RUNNER_TEMP}/lb-gate.stderr"
trap 'cat "${RUNNER_TEMP}/lb-gate.stderr" >&2; rm -f "${RUNNER_TEMP}/lb-gate.stderr"' EXIT
GATE_OUT="$(env DOPPLER_TOKEN="$DOPPLER_TOKEN_PRD" doppler run --preserve-env -p soleur -c prd -- \
  env -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS -u PS4 DOPPLER_TOKEN="$DOPPLER_TOKEN_LUKS_MARKER" DOPPLER_BIN="${RUNNER_TEMP}/doppler-cli/doppler" \
    SOLEUR_WEB2_SERVING_WEIGHT="$WEB2_LB_WEIGHT" SOLEUR_GATED_HOST="web-2" \
    SOLEUR_SERVING_ROTATION="web-1,web-2" \
  bash "${GITHUB_WORKSPACE}/apps/web-platform/infra/lb-weight-gate-with-marker.sh" 2>"${RUNNER_TEMP}/lb-gate.stderr")" || gate_rc=$?
sse_f="${GITHUB_WORKSPACE}/scripts/lib/serve-soak-evidence.sh"
source "$sse_f" && declare -F sse_gate_chain_mirror >/dev/null && declare -F sse_gate_chain_verify >/dev/null || { echo "::error::serve-soak-evidence helper not loaded ($sse_f) - wiring defect, do not re-dispatch"; exit 1; }
sse_gate_chain_mirror "${RUNNER_TEMP}/lb-gate.stderr" "$SOLEUR_GATED_HOST" "$gate_rc"
[[ "$gate_rc" -eq 0 ]] || exit 1
printf '%s\n' "$GATE_OUT"
if ! grep -q 'requires_runtime_bind_probe=true' <<<"$GATE_OUT"; then
  echo "::error::§(c) gate chain exited 0 WITHOUT the flip-authorization marker (requires_runtime_bind_probe=true) — the standby branch passed vacuously and Conditions A/B were never evaluated; web-2 is NOT authorized to serve. NOTHING planned, NOTHING applied."
  exit 1
fi
sse_gate_chain_verify "${RUNNER_TEMP}/lb-gate.stderr" "$SOLEUR_GATED_HOST"
SKGATEBODY
)"
sk_gate_ok() { # <workflow> -> 0 iff the gate chain step captures, replays, mirrors, backstops and re-checks (Guard 4)
  local job st nc run runnc a b c d m keys
  job="$(sk_job "$1")"; st="$(sk_step "$job" '§\(c\) gate chain')"; [[ -n "$st" ]] || return 1
  nc="$(sk_nc "$st")"; run="$(sk_run "$st")"; runnc="$(sk_nc "$run")"
  keys="$(sed -nE 's/^      - (name):.*/\1/p; s/^        ([A-Za-z_-]+):.*/\1/p' <<<"$nc" | tr '\n' ',')"
  [[ "$keys" == "name,if,env,run," ]] || return 1
  ! grep -qE '^    defaults:' <<<"$job" || return 1
  [[ "$(grep -cE '(^|[;&|[:space:]])trap([[:space:]]|$)' <<<"$runnc" || true)" -eq 1 ]] || return 1
  [[ "$(grep -cxF -- "            $SK_INNER_ENV" <<<"$nc" || true)" -eq 1 ]] || return 1
  grep -qxF '          SOLEUR_GATED_HOST: web-2' <<<"$nc" || return 1
  [[ "$(head -1 <<<"$runnc")" == "set -euo pipefail" ]] || return 1
  a="$(grep -nxF 'gate_rc=0' <<<"$runnc" | head -1 | cut -d: -f1 || true)"; b="$(grep -nxF ': >"${RUNNER_TEMP}/lb-gate.stderr"' <<<"$runnc" | head -1 | cut -d: -f1 || true)"
  c="$(grep -nxF -- "$SK_TRAP" <<<"$runnc" | head -1 | cut -d: -f1 || true)"; d="$(grep -nE '^GATE_OUT="\$\(env DOPPLER_TOKEN=' <<<"$runnc" | head -1 | cut -d: -f1 || true)"
  [[ -n "$a" && -n "$b" && -n "$c" && -n "$d" && "$a" -lt "$d" && "$b" -lt "$d" && "$c" -lt "$d" ]] || return 1
  [[ "$(grep -cF 'lb-weight-gate-with-marker.sh" 2>"${RUNNER_TEMP}/lb-gate.stderr")" || gate_rc=$?' <<<"$runnc" || true)" -eq 1 ]] || return 1
  grep -qxF '# shellcheck source=scripts/lib/serve-soak-evidence.sh' <<<"$run" || return 1
  grep -qxF -- "$SK_SSE_F" <<<"$runnc" || return 1
  [[ "$(grep -cxF -- "$SK_LOAD_GATE" <<<"$runnc" || true)" -eq 1 ]] || return 1
  [[ "$(grep -cxF -- "$SK_MIRROR" <<<"$runnc" || true)" -eq 1 && "$(grep -c 'sse_gate_chain_mirror' <<<"$runnc" || true)" -eq 2 ]] || return 1
  m="$(grep -nxF -- "$SK_MIRROR" <<<"$runnc" | cut -d: -f1 || true)"
  [[ "$(sed -n "$((m + 1))p" <<<"$runnc")" == "$SK_BACKSTOP" ]] || return 1
  [[ "$(grep -cxF -- "$SK_VERIFY" <<<"$runnc" || true)" -eq 1 && "$(grep -c 'sse_gate_chain_verify' <<<"$runnc" || true)" -eq 2 ]] || return 1
  [[ "$(grep -nxF -- "$SK_VERIFY" <<<"$runnc" | cut -d: -f1)" -gt "$(grep -nF "grep -q 'requires_runtime_bind_probe=true'" <<<"$runnc" | head -1 | cut -d: -f1)" ]] || return 1
  ! grep -qE 'continue-on-error|\|\|[[:space:]]*true|set[[:space:]]+\+e' <<<"$nc" || return 1
  ! grep -qE 'set[[:space:]]+\+o|errexit|(^|[;&|[:space:]])exit[[:space:]]+0([;[:space:]]|$)' <<<"$runnc" || return 1
  # comment lines are dropped only when they do not sit inside a backslash continuation (fix round 2, P3: a
  # comment there ends the command early); blank lines are dropped as before
  [[ "$(awk '/^[[:space:]]*#/ && prev !~ /\\$/ {next} /^[[:space:]]*$/ {next} {print; prev=$0}' <<<"$run")" == "$SK_GATE_BODY" ]] || return 1
  return 0
}
# every step from the gate chain on carries no if:, or exactly the serve condition (test-design P2: `if: always()` on
# plan/apply would let a refused gate or grader step reach apply)
sk_downstream_if_ok() {
  local job; job="$(sk_job "$1")"; [[ -n "$job" ]] || return 1
  local ifs # both YAML spellings: `        if:` after `- name:`, and `      - if:` as the step's first key (fix round)
  ifs="$(awk '/^(      - |        )name: §\(c\) gate chain/ {on=1} on && /^(      - |        )if:/ {sub(/^      - if:/, "        if:"); print}' <<<"$job")"
  ! grep -vxF "        if: inputs.mode == 'serve'" <<<"$ifs" | grep -q . || return 1
  [[ "$(grep -c . <<<"$ifs" || true)" -ge 4 ]]
}
# R4 class (fix round): the health step's doppler-run shell unsets every bash startup variable a prd_terraform
# secret could plant (BASH_ENV/ENV run a file; SHELLOPTS=xtrace + PS4='$(cmd)' runs a command) - exactly once
sk_health_env_ok() {
  local job st nc; job="$(sk_job "$1")"; st="$(sk_step "$job" 'web-2 health precondition')"; nc="$(sk_nc "$(sk_run "$st")")"
  [[ "$(grep -cF -- "-c prd_terraform -- env -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS -u PS4 bash -c '" <<<"$nc" || true)" -eq 1 ]] \
    && [[ "$(grep -c 'doppler run' <<<"$nc" || true)" -eq 1 ]]
}
# Fix round 2 (test-design P2): the step-key checks read the PARSED job, so a quoted or spaced key (`"if":`,
# `if :`, `"shell":`) - the same key to a YAML parser - cannot slip past a text match on `if:` / `shell:`.
# Gate and grader steps: exactly {name, if, env, run}. Every step from the gate on: no shell, no
# continue-on-error, and no `if` or exactly the serve condition. At least 4 steps from the gate on carry it.
sk_yaml_ok() {
  SK_YF="$1" python3 - <<'SKYAML' 2>/dev/null
import os, sys, yaml
try:
    wf = yaml.safe_load(open(os.environ["SK_YF"]))
    steps = wf["jobs"]["ga_pool_update"]["steps"]
except Exception:
    sys.exit(1)
names = [str(st.get("name", "")) for st in steps]
gi = [i for i, n in enumerate(names) if n.startswith("§(c) gate chain")]
ri = [i for i, n in enumerate(names) if n.startswith("per-instance soak grader")]
if len(gi) != 1 or len(ri) != 1 or ri[0] < gi[0]:
    sys.exit(1)
serve = "inputs.mode == 'serve'"
for i in (gi[0], ri[0]):
    if set(steps[i].keys()) != {"name", "if", "env", "run"} or steps[i]["if"] != serve:
        sys.exit(1)
gated = 0
for st in steps[gi[0]:]:
    if "shell" in st or "continue-on-error" in st:
        sys.exit(1)
    if "if" in st:
        if st["if"] != serve:
            sys.exit(1)
        gated += 1
sys.exit(0 if gated >= 4 else 1)
SKYAML
}
sk_host_parity_ok() { # <workflow> -> the five web-2 literal sites agree (the #12869 un-keying list)
  local job gs gr inner step_gate step_grader wrap rows helper
  job="$(sk_job "$1")"; gs="$(sk_nc "$(sk_step "$job" '§\(c\) gate chain')")"; gr="$(sk_nc "$(sk_step "$job" 'per-instance soak grader \(serve only\)')")"
  step_gate="$(sed -nE 's/^          SOLEUR_GATED_HOST: ([a-z0-9-]+)[[:space:]]*$/\1/p' <<<"$gs")"
  inner="$(grep -oE 'SOLEUR_GATED_HOST="[^"]+"' <<<"$gs" | sed -E 's/^SOLEUR_GATED_HOST="(.*)"$/\1/' || true)"
  step_grader="$(sed -nE 's/^          SOLEUR_GATED_HOST: ([a-z0-9-]+)[[:space:]]*$/\1/p' <<<"$gr")"
  wrap="$(sed -nE 's/^MARKER_HOST="([^"]+)".*/\1/p' "$WRAPPER_FILE")"
  rows="$(sed -nE 's/^W2L_HOST_NAME="soleur-([^"]+)".*/\1/p' "$ROWS_LIB_FILE")"
  helper="$(sed -nE 's/^readonly SSE_GRADED_HOST="([^"]+)".*/\1/p' "$SSE_LIB" 2>/dev/null)"
  [[ -n "$step_gate" && "$step_gate" != *$'\n'* ]] || return 1
  [[ "$inner" == "$step_gate" && "$step_grader" == "$step_gate" && "$wrap" == "$step_gate" && "$rows" == "$step_gate" && "$helper" == "$step_gate" ]]
}
sk_knob_census_ok() { local nc; nc="$(grep -vE '^[[:space:]]*#' "$1" || true)"; ! grep -qE '(GIT_DATA|WORKSPACES)_LUKS_SOAK_DAYS' <<<"$nc"; }
sk_no_marker_name() { ! grep -qiE 'workspaces_luks_cutover_at' "$1"; }
sk_grader_name_ok() { # the helper's grader= value is the basename of the grader the step hands it
  [[ "${SSE_GRADER_NAME:-}" == web2-luks-live-6931 ]] && grep -qF "scripts/followthroughs/${SSE_GRADER_NAME}.sh\"" <<<"$(sk_job "$1")"
}
sec_open wiring 48
sk_check "G3/AC8: ga_pool_update has exactly one 'per-instance soak grader (serve only)' step: keys name/if/env/run, serve-gated, env exactly SOLEUR_GATED_HOST + the three BETTERSTACK_QUERY_* secrets, no tolerance, guarded helper load, one bare sse_instance_soak call, gate < grader < health < plan" sk_grader_ok "$WF"
sk_check "G4: the gate chain step: step-level SOLEUR_GATED_HOST, gate_rc=0, the stderr file truncated, the EXIT replay trap, the redirect after the wrapper path with || gate_rc=\$?, a guarded helper load, the bare mirror call followed by the inline backstop, and the re-check after the flip-marker check" sk_gate_ok "$WF"
sk_check "G3/F5: the web-2 literal agrees at all five sites (gate step env, the inner literal, grader step env, the wrapper's MARKER_HOST, the rows library's W2L_HOST_NAME, the helper's SSE_GRADED_HOST) — the #12869 un-keying list" sk_host_parity_ok "$WF"
sk_check "G1 row 11: no (GIT_DATA|WORKSPACES)_LUKS_SOAK_DAYS on any non-comment line of cf-lb-overlay.yml (doppler run --preserve-env would let an ambient value win)" sk_knob_census_ok "$WF"
sk_check "AC19: cf-lb-overlay.yml never names the soak marker's Doppler name, in any case, not even in a comment" sk_no_marker_name "$WF"
sk_check "G3: the helper's grader= value (SSE_GRADER_NAME) is the basename of the grader the step hands it" sk_grader_name_ok "$WF"
sk_check "test-design P2: every ga_pool_update step from the gate chain on has no if: or exactly inputs.mode == 'serve' (a refusal cannot reach apply)" sk_downstream_if_ok "$WF"
sk_check "fix round 2: the PARSED job agrees - gate/grader keys {name,if,env,run}, no shell/continue-on-error and only the serve if: from the gate on" sk_yaml_ok "$WF"
sk_check "R4 class: the health step's doppler-run shell unsets BASH_ENV, ENV, SHELLOPTS, BASHOPTS and PS4" sk_health_env_ok "$WF"
sk_check "R2 parity: the knob the helper sets (W2L_REQUIRE_BOOT_JOIN=1) is the one the grader reads, once each, outside comments" \
  eval '[[ "$(grep -vE "^[[:space:]]*#" "$SSE_LIB" | grep -cF "W2L_REQUIRE_BOOT_JOIN=1" || true)" -eq 1 && "$(grep -vE "^[[:space:]]*#" "$REPO_ROOT/scripts/followthroughs/web2-luks-live-6931.sh" | grep -cF "\"\${W2L_REQUIRE_BOOT_JOIN:-}\" == 1" || true)" -eq 1 ]]'
SKW="$SK_WORK/wf"; mkdir -p "$SKW"
skmut() { # <label> <guard-fn> <awk-program> — committed mutation: it must LAND and the guard must go RED
  local f="$SKW/m.yml"
  awk "$3" "$WF" > "$f"
  if cmp -s "$WF" "$f"; then srow "$1: the mutation did not land (copy identical to pristine)" 0; return; fi
  if "$2" "$f"; then srow "$1 stayed GREEN" 0; else srow "$1 -> RED" 1; fi
}
SK_IN_GRADER='/^      - name: per-instance soak grader/ {g=1; print; next} /^      - / {g=0}'
SK_IN_GATE='/^      - name: §\(c\) gate chain/ {g=1; print; next} /^      - / {g=0}'
skmut "G3-1a committed mutant: the grader step's if: becomes false" sk_grader_ok "$SK_IN_GRADER"' g && /^        if: / {print "        if: false"; next} {print}'
skmut "G3-1b committed mutant: the grader step's serve condition is removed" sk_grader_ok "$SK_IN_GRADER"' g && /^        if: / {next} {print}'
skmut "G3-2 committed mutant: the grader step moves after the Terraform plan step" sk_grader_ok '/^      - name: per-instance soak grader/ {buf=1} buf && /^      - / && !/per-instance soak grader/ {buf=0} buf {held = held $0 "\n"; next} /^      - name: Plan gate \(updates/ {printf "%s", held} {print}'
skmut "G3-3a committed mutant: continue-on-error: true on the grader step" sk_grader_ok "$SK_IN_GRADER"' g && /^        if: / {print; print "        continue-on-error: true"; next} {print}'
skmut "G3-3b committed mutant: || true after the helper call" sk_grader_ok '{ if ($0 ~ /^          sse_instance_soak "\$SOLEUR_GATED_HOST"/) print $0 " || true"; else print }'
skmut "G3-4 committed mutant: a shell: key on the grader step" sk_grader_ok "$SK_IN_GRADER"' g && /^        if: / {print; print "        shell: bash"; next} {print}'
skmut "G3-4c committed mutant: a job-level defaults: block" sk_grader_ok '{print} /^  ga_pool_update:/ {inj=1} inj && /^    timeout-minutes:/ {print "    defaults:"; print "      run:"; print "        shell: bash"; inj=0}'
skmut "G3-4d committed mutant: the grader step's helper load is unguarded (a bare source)" sk_grader_ok "$SK_IN_GRADER"' g && /^          source "\$sse_f" && declare -F sse_instance_soak/ {print "          source \"$sse_f\""; next} {print}'
skmut "G3-4e committed mutant: the grader step names a credential through secrets. in its run body" sk_grader_ok '{print} /^          sse_instance_soak "\$SOLEUR_GATED_HOST"/ {print "          echo \"${{ secrets.BETTERSTACK_QUERY_PASSWORD }}\" >/dev/null"}'
skmut "G3-4b1 committed mutant: the gate step's inline backstop is deleted" sk_gate_ok '!/^          \[\[ "\$gate_rc" -eq 0 \]\] \|\| exit 1$/ {print}'
skmut "G3-4b2 committed mutant: the mirror call is wrapped in if (errexit off for it)" sk_gate_ok '{ if ($0 ~ /^          sse_gate_chain_mirror /) print "          if " substr($0, 11) "; then :; fi"; else print }'
skmut "G3-4b3 committed mutant: the pass re-check is dropped" sk_gate_ok '!/^          sse_gate_chain_verify / {print}'
skmut "G3-4b4 committed mutant: the gate rc is swallowed (|| true instead of || gate_rc=\$?)" sk_gate_ok '{ sub(/ \|\| gate_rc=\$\?$/, " || true"); print }'
skmut "G4-3 committed mutant: the EXIT replay trap is dropped" sk_gate_ok '!/^          trap .cat "\$\{RUNNER_TEMP\}\/lb-gate.stderr" >&2; rm -f "\$\{RUNNER_TEMP\}\/lb-gate.stderr". EXIT$/ {print}'
skmut "G4-3b committed mutant: the stderr capture moves outside the substitution (2> after the closing paren)" sk_gate_ok '{ if ($0 ~ /lb-weight-gate-with-marker.sh" 2>"\$\{RUNNER_TEMP\}\/lb-gate.stderr"\)" \|\| gate_rc=\$\?$/) sub(/" 2>"\$\{RUNNER_TEMP\}\/lb-gate.stderr"\)"/, "\")\" 2>\"${RUNNER_TEMP}/lb-gate.stderr\""); print }'
skmut "R7 committed mutant: trap 'exit 0' ERR before the bare sse_instance_soak call" sk_grader_ok '/^          sse_instance_soak "\$SOLEUR_GATED_HOST"/ {print "          trap '"'"'exit 0'"'"' ERR"} {print}'
skmut "R7 committed mutant: a second trap (ERR, exit 0) in the gate step" sk_gate_ok '{print} /^          trap .cat "\$\{RUNNER_TEMP\}\/lb-gate.stderr" >&2; rm -f/ {print "          trap '"'"'exit 0'"'"' ERR"}'
skmut "R7 committed mutant: a shell: key on the gate step" sk_gate_ok "$SK_IN_GATE"' g && /^        if: / {print; print "        shell: bash"; next} {print}'
skmut "R4 class committed mutant: the gate step's inner env keeps BASH_ENV/ENV out but lets SHELLOPTS in" sk_gate_ok '{ sub(/ -u SHELLOPTS -u BASHOPTS -u PS4 DOPPLER_TOKEN=/, " DOPPLER_TOKEN="); print }'
skmut "R4 class committed mutant: the health step's shell lets SHELLOPTS/PS4 in" sk_health_env_ok '{ sub(/-- env -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS -u PS4 bash -c/, "-- env -u BASH_ENV -u ENV bash -c"); print }'
skmut "R4 committed mutant: the gate step's inner env no longer unsets BASH_ENV/ENV" sk_gate_ok '{ sub(/env -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS -u PS4 DOPPLER_TOKEN="\$DOPPLER_TOKEN_LUKS_MARKER"/, "env DOPPLER_TOKEN=\"$DOPPLER_TOKEN_LUKS_MARKER\""); print }'
skmut "test-design P2 committed mutant: set +o errexit + exit 0 in the grader step" sk_grader_ok "$SK_IN_GRADER"' g && /^          set -euo pipefail$/ {print; print "          set +o errexit"; next} {print} /^          sse_instance_soak "\$SOLEUR_GATED_HOST"/ {print "          exit 0"}'
skmut "test-design P2 committed mutant: set +o errexit before the gate step's re-check" sk_gate_ok '/^          sse_gate_chain_verify / {print "          set +o errexit"} {print}'
skmut "fix round 2 committed mutant: a quoted \"if\": always() on the apply step" sk_yaml_ok '{print} /^      - name: Terraform apply \(the graded tfplan\)/ {print "        \"if\": always()"}'
skmut "fix round 2 committed mutant: a spaced 'if :' always() on the apply step" sk_yaml_ok '{print} /^      - name: Terraform apply \(the graded tfplan\)/ {print "        if : always()"}'
skmut "fix round 2 committed mutant: a quoted \"shell\": on the grader step" sk_yaml_ok '{print} /^      - name: per-instance soak grader/ {print "        \"shell\": bash -c '"'"'exit 0'"'"' {0}"}'
skmut "fix round 2 committed mutant: a quoted \"shell\": on the gate step" sk_yaml_ok '{print} /^      - name: §\(c\) gate chain/ {print "        \"shell\": bash -c '"'"'exit 0'"'"' {0}"}'
skmut "fix round 2 committed mutant: a comment inside the gate step's backslash continuation" sk_gate_ok '{print} /^            env -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS -u PS4 DOPPLER_TOKEN=/ {print "            # inner env hands the wrapper its token"}'
skmut "fix-round committed mutant: '- if: always()' as the apply step's first key" sk_downstream_if_ok '/^      - name: Terraform apply \(the graded tfplan\)/ {print "      - if: always()"; sub(/^      - name:/, "        name:")} {print}'
skmut "fix-round committed mutant: exit \"0\" right after set -euo pipefail in the gate step" sk_gate_ok "$SK_IN_GATE"' g && /^          set -euo pipefail$/ {print; print "          exit \"0\""; next} {print}'
skmut "test-design P2 committed mutant: if: always() on the Terraform apply step" sk_downstream_if_ok '{print} /^      - name: Terraform apply \(the graded tfplan\)/ {print "        if: always()"}'
skmut "G3-5 committed mutant: the grader step's host becomes web-3 while the gate step keeps web-2" sk_host_parity_ok "$SK_IN_GRADER"' g && /^          SOLEUR_GATED_HOST: web-2$/ {print "          SOLEUR_GATED_HOST: web-3"; next} {print}'
skmut "G3-5b committed mutant: the gate step's step-level host becomes web-3 while the inner literal keeps web-2" sk_host_parity_ok "$SK_IN_GATE"' g && /^          SOLEUR_GATED_HOST: web-2$/ {print "          SOLEUR_GATED_HOST: web-3"; next} {print}'
skmut "G1-11a committed mutant: a soak knob in the gate step's env:" sk_knob_census_ok "$SK_IN_GATE"' g && /^          DOPPLER_TOKEN_LUKS_MARKER:/ {print; print "          WORKSPACES_LUKS_SOAK_DAYS: \"1\""; next} {print}'
skmut "G1-11b committed mutant: a soak knob in the job's env:" sk_knob_census_ok '{print} /^  ga_pool_update:/ {inj=1} inj && /^    timeout-minutes:/ {print "    env:"; print "      GIT_DATA_LUKS_SOAK_DAYS: \"1\""; inj=0}'
skmut "G1-11c committed mutant: an earlier step exports a soak knob to GITHUB_ENV" sk_knob_census_ok '{print} /^          echo "WEB2_LB_WEIGHT=\$\{WEB2_LB_WEIGHT\}" >> "\$GITHUB_ENV"/ {print "          echo \"WORKSPACES_LUKS_SOAK_DAYS=1\" >> \"$GITHUB_ENV\""}'
P_WORK="$SK_WORK/p"; mkdir -p "$P_WORK"
skmut "G1-10 committed mutant: WORKSPACES_LUKS_SOAK_DAYS=3 pinned in the gate step's inner env (p_guard C.4-P1)" p_guard '{print} /^              SOLEUR_SERVING_ROTATION="web-1,web-2" \\$/ {print "              WORKSPACES_LUKS_SOAK_DAYS=\"3\" \\"}'
# the trap line, EXECUTED: on any exit it replays every captured line (evidence and gate_fail) to the log
sk_trap_exec() {
  local st run line out
  st="$(sk_step "$(sk_job "$WF")" '§\(c\) gate chain')"; run="$(sk_nc "$(sk_run "$st")")"
  line="$(grep -xF -- "$SK_TRAP" <<<"$run" | head -1)"; [[ -n "$line" ]] || return 1
  mkdir -p "$SK_WORK/rt"
  local want; want="$(printf '%s\n' "$EVP" 'a Doppler notice' 'gate_fail sub_condition=B_luks_soak_not_elapsed')"
  printf '%s\n' "$want" > "$SK_WORK/rt/lb-gate.stderr"
  out="$(env -i PATH=/usr/bin:/bin RUNNER_TEMP="$SK_WORK/rt" "$BASH_BIN" --norc -c "set -e; $line; exit 1" 2>&1 >/dev/null </dev/null || true)"
  [[ "$out" == "$want" && ! -e "$SK_WORK/rt/lb-gate.stderr" ]]
}
sk_check "G4 executed: the gate step's EXIT trap replays the captured stderr (evidence + gate_fail lines) on a refusal exit, then removes the file" sk_trap_exec
sec_close

# -----------------------------------------------------------------------------------------------------------------
# §SK-instance — Guard 3 executed rows on sse_instance_soak (a stub grader records its calls, env and clock).
# -----------------------------------------------------------------------------------------------------------------
SKI="$SK_WORK/inst"; mkdir -p "$SKI/home" "$SKI/rt"
cat > "$SKI/grader.sh" <<EOF
#!$BASH_BIN
printf 'x\n' >> "$SKI/calls"
env > "$SKI/env"
printf '%s' "\${SOLEUR_FT_EARLIEST-__UNSET__}" > "$SKI/ft"
if [ -f "$SKI/term" ]; then printf '%s' "\$\$" > "$SKI/pid"; exec sleep 30; fi
cat "$SKI/text" 2>/dev/null
exit "\$(cat "$SKI/rc" 2>/dev/null || echo 0)"
EOF
chmod +x "$SKI/grader.sh"
SKI_RC=0; SKI_OUT=""; SKI_ERR=""
# shellcheck disable=SC2034 # read inside the eval'd row predicates
ski_run() { # <host> <stub-rc> <stub-text> [ENV=VAL ...] [-- shell-opts] — runs the helper in a clean env, as the step does
  local host="$1" src="$2" txt="$3"; shift 3
  : > "$SKI/calls"; rm -f "$SKI/env" "$SKI/ft"; : > "$SKI/summary"
  printf '%s' "$src" > "$SKI/rc"; printf '%b' "$txt" > "$SKI/text"
  env -i PATH="/usr/bin:/bin" HOME="$SKI/home" RUNNER_TEMP="$SKI/rt" GITHUB_STEP_SUMMARY="$SKI/summary" \
    BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass \
    "$@" "$BASH_BIN" -c "set ${SKI_OPTS:--euo} pipefail; source \"\$1\"; sse_instance_soak \"\$2\" \"\$3\"" _ "$SSE_LIB" "$host" "$SKI/grader.sh" \
    >"$SKI/out" 2>"$SKI/err" && SKI_RC=0 || SKI_RC=$?
  SKI_OUT="$(cat "$SKI/out")"; SKI_ERR="$(cat "$SKI/err")"
}
fenced() { # <file> <heading-prefix> -> the lines inside the ```text fence under the first heading with that prefix
  awk -v h="$2" 'index($0, h) == 1 {seen = 1; next} seen && $0 == "```text" {on = 1; next} on && $0 == "```" {exit} on {print}' "$1"
}
ski_line_ok() { # <expected line> — exactly once on stderr, and the summary fence holds exactly it
  local n; n="$(grep -cxF -- "$1" <<<"$SKI_ERR" || true)"
  [[ "$n" -eq 1 && "$(fenced "$SKI/summary" '### per-instance soak grader (serve only)')" == "$1" ]] && re_full "$INSTANCE_EV_RE" "$1"
}
ski_calls() { [[ "$(grep -c . "$SKI/calls" || true)" -eq "$1" ]]; }
sec_open instance 50
for row in "0|PASS|PASS: the soak is met" "1|FAIL|FAIL: a non-green probe row" "2|NOT_YET|NOT YET: the soak is still running" \
           "3|CANNOT_ESTABLISH|CANNOT ESTABLISH: BETTERSTACK_QUERY_HOST is not injected" "78|CANNOT_ESTABLISH|" "126|CANNOT_ESTABLISH|" "127|CANNOT_ESTABLISH|"; do
  IFS='|' read -r src sv stxt <<<"$row"
  ski_run web-2 "$src" "$stxt"
  want="SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=${src} verdict=${sv}"
  if [[ "$src" -eq 0 ]]; then
    sk_check "G3 executed: grader rc 0 -> return 0 and '$want' on stderr and fenced in the summary" eval '[[ "$SKI_RC" -eq 0 ]] && ski_line_ok "$want"'
    sk_check "G3 executed: grader rc 0 -> no ::error:: line" eval '[[ "$SKI_OUT$SKI_ERR" != *"::error::"* ]]'
  else
    sk_check "G3 executed: grader rc $src -> return 1 and '$want' on stderr and fenced in the summary" eval '[[ "$SKI_RC" -eq 1 ]] && ski_line_ok "$want"'
    sk_check "G3 executed: grader rc $src -> an ::error:: naming verdict=$sv and NOTHING planned" eval '[[ "$SKI_OUT" == *"::error::per-instance soak grader verdict=${sv} rc=${src}"* && "$SKI_OUT" == *"NOTHING planned, NOTHING applied"* ]]'
  fi
  sk_check "G3 executed: grader rc $src -> the stub grader was called exactly once" ski_calls 1
done
ski_run web-2 2 'NOT YET: x' SOLEUR_FT_EARLIEST=2020-01-01T00:00:00Z
sk_check "G3 executed: an ambient SOLEUR_FT_EARLIEST reaches the grader as EMPTY (no clock: an unmet soak is NOT YET, never a window FAIL)" eval '[[ -f "$SKI/ft" && "$(cat "$SKI/ft")" == "" ]]'
ski_run web-2 0 'PASS: ok' HCLOUD_TOKEN=decoy-hcloud TF_VAR_github_app_runtime_doppler_token=decoy-tfvar DOPPLER_TOKEN=decoy-doppler AWS_SECRET_ACCESS_KEY=decoy-aws
sk_check "G10 executed: the grader's environment is exactly the env -i allowlist (PATH HOME TMPDIR, the three BETTERSTACK_QUERY_*, SOLEUR_FT_EARLIEST) plus bash's own PWD/SHLVL/_" \
  eval '[[ "$(sed -nE "s/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p" "$SKI/env" | LC_ALL=C sort | tr "\n" ",")" == "BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_PASSWORD,BETTERSTACK_QUERY_USERNAME,HOME,PATH,PWD,SHLVL,SOLEUR_FT_EARLIEST,TMPDIR,W2L_REQUIRE_BOOT_JOIN,_," ]]'
sk_check "G10 executed: no planted decoy credential value (HCLOUD_TOKEN, TF_VAR_github_app_runtime_doppler_token, DOPPLER_TOKEN, AWS_SECRET_ACCESS_KEY) reached the grader" eval '! grep -q "decoy-" "$SKI/env"'
sk_check "G10 executed: TMPDIR is RUNNER_TEMP" eval 'grep -qxF "TMPDIR=$SKI/rt" "$SKI/env"'
sk_check "R10 executed: the grader's HOME is a fresh scratch dir under RUNNER_TEMP (never the job HOME, where ~/.jq could be planted), removed after the run" \
  eval 'h="$(sed -n "s/^HOME=//p" "$SKI/env")"; [[ "$h" == "$SKI/rt/sse-grader-home."* && ! -e "$h" ]]'
sk_check "R10 executed: the grader's PATH is pinned to /usr/bin:/bin" eval 'grep -qxF "PATH=/usr/bin:/bin" "$SKI/env"'
sk_check "R2 executed: the serve arm asks the grader for the boot_id join (W2L_REQUIRE_BOOT_JOIN=1)" eval 'grep -qxF "W2L_REQUIRE_BOOT_JOIN=1" "$SKI/env"'
ski_run web-3 0 'PASS: ok'
sk_check "F5/G7 executed: gated host web-3 -> return 1 with 'SOLEUR_INSTANCE_SOAK host=web-3 ... rc=none verdict=CANNOT_ESTABLISH' (until #12869)" eval '[[ "$SKI_RC" -eq 1 ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-3 grader=web2-luks-live-6931 rc=none verdict=CANNOT_ESTABLISH"'
sk_check "F5/G7 executed: gated host web-3 -> the grader is never called, and an ::error:: says why" eval 'ski_calls 0 && [[ "$SKI_OUT" == *"::error::"*"web-2"* ]]'
ski_run '' 0 'PASS: ok'
sk_check "G7 executed: an empty gated host prints host=invalid rc=none verdict=CANNOT_ESTABLISH and never calls the grader" eval '[[ "$SKI_RC" -eq 1 ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=invalid grader=web2-luks-live-6931 rc=none verdict=CANNOT_ESTABLISH" && ski_calls 0'
ski_run 'Web 2;x' 0 'PASS: ok'
sk_check "G7 executed: a malformed gated host prints host=invalid (never the raw text)" eval '[[ "$SKI_RC" -eq 1 && "$SKI_ERR" != *"Web 2"* ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=invalid grader=web2-luks-live-6931 rc=none verdict=CANNOT_ESTABLISH"'
ski_run web-2 2 'NOT YET: no GREEN web-2 readiness row opens the soak (RED none); web-2 has not been (re)born onto LUKS, or its probe/readiness telemetry is dark.'
sk_check "G12 executed: NOT YET with no GREEN readiness row -> the grader's line is in the log" eval '[[ "$SKI_RC" -eq 1 && "$SKI_OUT$SKI_ERR" == *"NOT YET: no GREEN web-2 readiness row opens the soak"* ]]'
sk_check "G12 executed: ...and the ::error:: names the 90-day replace next step (web-host-replace.md, the 3-day soak)" eval '[[ "$SKI_OUT" == *"::error::"*"90 days"*"web-host-replace.md"*"3-day soak"* ]]'
ski_run web-2 1 'FAIL: spoiled'
sk_check "G3 executed: FAIL -> the ::error:: says the soak is spoiled and a replace is the repair" eval '[[ "$SKI_OUT" == *"::error::"*"spoiled"*"replace is the repair"* ]]'
sk_check "user-impact 1 executed: FAIL -> the ::error:: says to drain first if web-2 is serving" eval '[[ "$SKI_OUT" == *"::error::"*"mode=drain first"* ]]'
sk_check "agent-native 1 executed: the grader's first line is in the summary as grade_text= (its own fence, after the verdict fence)" eval 'grep -qxF "grade_text=FAIL: spoiled" "$SKI/summary" && [[ "$(fenced "$SKI/summary" "### per-instance soak grader (serve only)")" == "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=1 verdict=FAIL" ]]'
ski_run web-2 0 ''
sk_check "R1 executed: rc 0 with no first line (an empty grader) -> verdict=CANNOT_ESTABLISH rc=0, return 1, never PASS" eval '[[ "$SKI_RC" -eq 1 ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=CANNOT_ESTABLISH" && [[ "$SKI_OUT" == *"::error::"*"disagree"*"do not re-dispatch"* ]]'
ski_run web-2 0 'FAIL: but exited 0'
sk_check "R1 executed: rc 0 with a FAIL: first line -> CANNOT_ESTABLISH, return 1" eval '[[ "$SKI_RC" -eq 1 ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=CANNOT_ESTABLISH"'
ski_run web-2 1 ''
sk_check "R1 executed: rc 1 with no line (a bash abort) -> CANNOT_ESTABLISH, never the 'replace is the repair' FAIL advice" eval '[[ "$SKI_RC" -eq 1 && "$SKI_OUT" != *"replace is the repair"* ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=1 verdict=CANNOT_ESTABLISH"'
ski_run web-2 3 'PASS: but exited 3'
sk_check "R1 / test-design P3 executed: rc 3 with a PASS: first line never serves (CANNOT_ESTABLISH, return 1)" eval '[[ "$SKI_RC" -eq 1 ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=3 verdict=CANNOT_ESTABLISH"'
ski_run web-2 2 'PASS: but exited 2'
sk_check "R1 executed: rc 2 with a PASS: first line -> CANNOT_ESTABLISH" eval '[[ "$SKI_RC" -eq 1 ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=2 verdict=CANNOT_ESTABLISH"'
sk_check "test-design P3: ski_line_ok refuses a line that is not on stderr (the predicate can say no)" eval '! ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=PASS"'
ski_run web-2 3 'CANNOT ESTABLISH: x'
sk_check "G3 executed: CANNOT_ESTABLISH rc 3 -> the ::error:: says the Better Stack credentials or the shared helper are missing" eval '[[ "$SKI_OUT" == *"::error::"*"Better Stack credentials or the shared helper are missing"* ]]'
ski_run web-2 127 ''
sk_check "G3 executed: rc 127 -> the ::error:: says a code or wiring defect, do not re-dispatch" eval '[[ "$SKI_OUT" == *"::error::"*"code or wiring defect"*"do not re-dispatch"* ]]'
ski_run web-2 2 '::error::forged by the grader'
sk_check "infra-security 3 executed: grader text that is not a verdict line is never echoed (no forged workflow command), grade_text=unprintable instead" \
  eval '! grep -qE "^::error::forged" <<<"$SKI_OUT$SKI_ERR" && [[ "$SKI_OUT$SKI_ERR" == *"grade_text=unprintable"* ]]'
ski_run web-2 2 'NOT YET: fine\n::warning::second line'
sk_check "infra-security 3 executed: a multi-line grader text never echoes its later lines" eval '! grep -qE "^::warning::second line" <<<"$SKI_OUT$SKI_ERR"'
ski_run web-2 2 'NOT YET: waiting'
sk_check "G3 executed: a verdict-shaped grader line is echoed to the log as grade_text=<line>" eval '[[ "$SKI_ERR" == *"grade_text=NOT YET: waiting"* ]]'
SKI_OPTS='-euxo'; ski_run web-2 0 'PASS: ok'; SKI_OPTS=''
sk_check "G3 executed: under xtrace the helper refuses with 78 before any credential is used (grader never called)" eval '[[ "$SKI_RC" -eq 78 ]] && ski_calls 0'
ski_term() { # TERM the helper while the grader runs: the trap still leaves exactly one verdict line
  local pid spid
  : > "$SKI/calls"; : > "$SKI/summary"; rm -f "$SKI/pid"; : > "$SKI/term"; printf 0 > "$SKI/rc"; : > "$SKI/text"
  env -i PATH="/usr/bin:/bin" HOME="$SKI/home" RUNNER_TEMP="$SKI/rt" GITHUB_STEP_SUMMARY="$SKI/summary" \
    BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    "$BASH_BIN" -c 'set -euo pipefail; source "$1"; sse_instance_soak "$2" "$3"' _ "$SSE_LIB" web-2 "$SKI/grader.sh" >"$SKI/out" 2>"$SKI/err" &
  pid=$!
  for _ in $(seq 1 100); do [[ -s "$SKI/pid" ]] && break; sleep 0.1; done
  spid="$(cat "$SKI/pid" 2>/dev/null || true)"
  kill -TERM "$pid" 2>/dev/null || true
  [[ -n "$spid" ]] && kill -TERM "$spid" 2>/dev/null
  wait "$pid" 2>/dev/null && SKI_RC=0 || SKI_RC=$?
  rm -f "$SKI/term"; SKI_ERR="$(cat "$SKI/err")"
  if [[ -n "$spid" && "$SKI_RC" -ne 0 ]] && ski_line_ok "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=interrupted verdict=CANNOT_ESTABLISH"; then return 0; fi
  return 1
}
sk_check "observability 3 / R9 executed: a TERM while the grader runs still leaves exactly one 'rc=interrupted verdict=CANNOT_ESTABLISH' line (EXIT/TERM trap), distinct from the wrong-host rc=none" ski_term
sec_close

# -----------------------------------------------------------------------------------------------------------------
# §SK-chain — Guard 4 executed rows on sse_gate_chain_mirror / _verify / _check (stub stderr files).
# -----------------------------------------------------------------------------------------------------------------
SKG="$SK_WORK/chain"; mkdir -p "$SKG"
SKG_RC=0; SKG_OUT=""
# shellcheck disable=SC2034 # read inside the eval'd row predicates
skg_run() { # <fn> <args...> — the helper in a clean env under set -euo pipefail, as the step runs it
  : > "$SKG/summary"
  env -i PATH="/usr/bin:/bin" GITHUB_STEP_SUMMARY="$SKG/summary" "$BASH_BIN" -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$SSE_LIB" "$@" \
    >"$SKG/out" 2>"$SKG/err" && SKG_RC=0 || SKG_RC=$?
  SKG_OUT="$(cat "$SKG/out" "$SKG/err")"
}
evl() { # <kind> <host> <days> <src> <marker> <age> <req> <verdict> <sub>
  printf 'SOLEUR_SOAK_EVIDENCE kind=%s host=%s soak_days=%s source=%s floor_days=3 marker_at=%s age_s=%s required_s=%s verdict=%s sub_condition=%s\n' "$@"
}
SKG_GP="$(evl git_data web-2 3 default 2026-11-10T00:00:00Z 400000 259200 pass none)"
SKG_WP="$(evl workspaces_luks web-2 3 default 2026-11-10T00:00:00Z 400000 259200 pass none)"
SKG_WF="$(evl workspaces_luks web-2 1 env 2026-11-17T12:18:54Z 87883 none fail B_workspaces_luks_soak_days_below_floor)"
printf '%s\n' 'Doppler notice: fetching secrets' "$SKG_GP" "$SKG_WF" "$SKG_WF extra=forged" 'gate_fail sub_condition=B_workspaces_luks_soak_days_below_floor' > "$SKG/refuse"
printf '%s\n' 'Doppler notice: fetching secrets' "$SKG_GP" "$SKG_WP" "${SKG_WP/verdict=pass/verdict=pass verdict=pass}" > "$SKG/pass"
skg_fence() { fenced "$SKG/summary" '### §(c) gate chain soak evidence'; }
sec_open chain 27
skg_run sse_gate_chain_mirror "$SKG/refuse" web-2 1
sk_check "G4 executed: a refusal (rc 1) returns 1" eval '[[ "$SKG_RC" -eq 1 ]]'
sk_check "G4 executed: the refusal's fenced summary holds exactly the two grammar lines (the forged line and the Doppler notice stay out)" eval '[[ "$(skg_fence)" == "$(printf "%s\n%s" "$SKG_GP" "$SKG_WF")" ]]'
sk_check "G4 executed: the refusal heading repeats the refusing id" eval 'grep -qxF "### §(c) gate chain soak evidence (refused: sub_condition=B_workspaces_luks_soak_days_below_floor)" "$SKG/summary"'
sk_check "G4/AC17 executed: the ::error:: names the refusing id" eval '[[ "$SKG_OUT" == *"::error::§(c) gate chain refused the flip (sub_condition=B_workspaces_luks_soak_days_below_floor)"* ]]'
sk_check "G4 executed: a below_floor refusal's ::error:: names the 3-day floor, #12933 and 'values may only lengthen it'" eval '[[ "$SKG_OUT" == *"below the 3-day floor"*"#12933"*"values may only lengthen it"* ]]'
sk_check "spec-flow 5 executed: a refusal records 'per-instance soak grader: NOT RUN (gate refused)' in the summary" eval 'grep -qF -- "per-instance soak grader: NOT RUN (gate refused)" "$SKG/summary"'
sk_check "user-impact executed: the refusal's ::error:: says a refused serve never drains and names mode=drain" eval '[[ "$SKG_OUT" == *"A refused serve never drains"*"mode=drain"* ]]'
printf '%s\n' 'gate_fail sub_condition=A_web2_not_in_roster' > "$SKG/conda"
skg_run sse_gate_chain_mirror "$SKG/conda" web-2 1
sk_check "G4-7 executed: a zero-line Condition A refusal still prints its ::error:: (the no-match grep is guarded under set -e) and an empty fence" eval '[[ "$SKG_RC" -eq 1 && "$SKG_OUT" == *"::error::§(c) gate chain refused the flip (sub_condition=A_web2_not_in_roster)"* && -z "$(skg_fence)" ]] && grep -qxF "\`\`\`text" "$SKG/summary"'
printf '%s\n' 'marker_source_fail class=names_rc_1 marker=X config=Y gate_not_run=true' > "$SKG/wrap"
skg_run sse_gate_chain_mirror "$SKG/wrap" web-2 3
sk_check "G4 executed: a wrapper/Doppler failure before the gate ran names the refusing id gate_not_run_<class> (never the marker key)" eval '[[ "$SKG_RC" -eq 1 && "$SKG_OUT" == *"::error::§(c) gate chain refused the flip (sub_condition=gate_not_run_names_rc_1)"* && "$SKG_OUT" != *"marker=X"* ]]'
printf '%s\n' 'some other stderr' > "$SKG/none"
skg_run sse_gate_chain_mirror "$SKG/none" web-2 3
sk_check "G4 executed: a refusal with neither a gate_fail nor a marker_source_fail line names the id 'none'" eval '[[ "$SKG_RC" -eq 1 && "$SKG_OUT" == *"(sub_condition=none)"* ]]'
skg_run sse_gate_chain_mirror "$SKG/pass" web-2 0
sk_check "G4 executed: a pass (rc 0) mirror returns 0 and writes no ::error::" eval '[[ "$SKG_RC" -eq 0 && "$SKG_OUT" != *"::error::"* ]]'
sk_check "G4-8 executed: the pass fence holds exactly the two pass lines (a doubled-verdict forgery and the Doppler notice stay out)" eval '[[ "$(skg_fence)" == "$(printf "%s\n%s" "$SKG_GP" "$SKG_WP")" ]]'
printf '%s\n' 'Doppler notice: fetching secrets' "$SKG_GP" 'another notice' "$SKG_WP" > "$SKG/pass-clean"
skg_run sse_gate_chain_verify "$SKG/pass-clean" web-2
sk_check "G4 H2 executed: the pass re-check accepts one well-formed pass line per kind with interleaved non-evidence stderr" eval '[[ "$SKG_RC" -eq 0 && "$SKG_OUT" != *"::error::"* ]]'
skg_run sse_gate_chain_verify "$SKG/pass" web-2
sk_check "data-integrity 2 executed: a near-miss evidence line (doubled verdict) next to two good pass lines refuses (never skipped)" eval '[[ "$SKG_RC" -eq 1 && "$SKG_OUT" == *"malformed soak evidence line"* ]]'
skg_vrefuses() { # <desc> <file-content...> — the pass re-check must return 1 with the anti-vacuity message
  printf '%s\n' "${@:2}" > "$SKG/v"
  skg_run sse_gate_chain_verify "$SKG/v" web-2
  sk_check "$1" eval '[[ "$SKG_RC" -eq 1 && "$SKG_OUT" == *"::error::§(c) gate chain: gate passed but soak evidence for kind="*" is missing or malformed - a code defect, not a soak wait; do not re-dispatch"* ]]'
}
skg_vrefuses "G4-4 executed: a pass with no workspaces_luks line refuses (anti-vacuity, second member)" "$SKG_GP"
skg_vrefuses "G4 executed: a pass with no git_data line refuses" "$SKG_WP"
skg_vrefuses "G4 executed: a pass with zero evidence lines refuses" 'Doppler notice'
skg_vrefuses "G8/G4-5 executed: a pass line with none fields refuses" "$SKG_GP" "$(evl workspaces_luks web-2 3 default none none none pass none)"
skg_vrefuses "G8/G4-5 executed: a pass line with required_s=86400 (below SOAK_FLOOR_S) refuses" "$SKG_GP" "$(evl workspaces_luks web-2 1 env 2026-11-17T12:18:54Z 87883 86400 pass none)"
skg_vrefuses "G8 executed: a pass line whose age_s is below its required_s refuses" "$SKG_GP" "$(evl workspaces_luks web-2 3 default 2026-11-17T12:18:54Z 87883 259200 pass none)"
skg_vrefuses "G4-6 executed: pass lines for a different host refuse" "$(evl git_data web-3 3 default 2026-11-10T00:00:00Z 400000 259200 pass none)" "$(evl workspaces_luks web-3 3 default 2026-11-10T00:00:00Z 400000 259200 pass none)"
skg_vrefuses "G4 executed: two pass lines for one kind refuse (exactly one per kind)" "$SKG_GP" "$SKG_GP" "$SKG_WP"
skg_vrefuses "design P2 executed: a 13-digit age_s on a pass line refuses (no arithmetic on an unbounded field)" "$SKG_GP" "$(evl workspaces_luks web-2 3 default 2026-11-10T00:00:00Z 1234567890123 259200 pass none)"
skg_vrefuses "G4 executed: a verdict=fail line for a kind on a passing gate refuses" "$SKG_GP" "$(evl workspaces_luks web-2 3 default 2026-11-10T00:00:00Z 400000 259200 fail B_workspaces_luks_soak_not_elapsed)"
# F11: the REAL gate's stderr is what the consumer accepts (producer and consumer graded by the one grammar)
reset_def; run_with_def; printf '%s\n' "$GATE_ERR" > "$SKG/real-pass"
skg_run sse_gate_chain_verify "$SKG/real-pass" web-2
sk_check "F11 executed: the real gate's pass stderr satisfies the helper's pass re-check" eval '[[ "$SKG_RC" -eq 0 ]]'
reset_def; DEF[WORKSPACES_LUKS_SOAK_DAYS]='1'; run_with_def; printf '%s\n' "$GATE_ERR" > "$SKG/real-refuse"
skg_run sse_gate_chain_mirror "$SKG/real-refuse" web-2 1
sk_check "F11 executed: the real gate's below_floor refusal is mirrored line for line (git pass + workspaces fail) and named in the ::error:: (run 44304068922 regression)" \
  eval '[[ "$SKG_RC" -eq 1 && "$(skg_fence | grep -c .)" -eq 2 && "$SKG_OUT" == *"(sub_condition=B_workspaces_luks_soak_days_below_floor)"* ]]'
skg_run sse_gate_chain_verify "$SKG/pass-clean" 'web 2'
sk_check "G4 executed: a malformed gated host is refused by the re-check, never interpolated into a pattern" eval '[[ "$SKG_RC" -eq 1 ]]'
sec_close

# -----------------------------------------------------------------------------------------------------------------
# §SK-probe — G11 executed rows on scripts/serve-soak-evidence-last.sh with a stub gh in the real log format.
# -----------------------------------------------------------------------------------------------------------------
SKP="$SK_WORK/probe"; mkdir -p "$SKP/bin"
cat > "$SKP/bin/gh" <<EOF
#!$BASH_BIN
printf '%s\n' "\$*" >> "$SKP/argv"
case "\$1 \$2" in
  "run list") cat "$SKP/list.json" ;;
  "run view") [ -f "$SKP/log.\$3" ] && cat "$SKP/log.\$3" || exit 1 ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$SKP/bin/gh"
SKP_RC=0; SKP_OUT=""
# shellcheck disable=SC2034 # read inside the eval'd row predicates
skp_run() { : > "$SKP/argv"; SKP_OUT="$(cd "$SKP" && env -i PATH="$SKP/bin:/usr/bin:/bin" HOME="$SKP" "$BASH_BIN" "$SSE_PROBE" "$@" 2>/dev/null)" && SKP_RC=0 || SKP_RC=$?; }
skp_log() { # <id> <lines...> — a `gh run view --log` body: <job>\t<step>\t<timestamp> <text>
  local id="$1" l; shift; : > "$SKP/log.$id"
  for l in "$@"; do printf 'ga_pool_update\t§(c) gate chain (serve mode only — fail-closed BEFORE plan)\t2026-11-18T12:43:37.1234567Z %s\n' "$l" >> "$SKP/log.$id"; done
}
SKP_I='SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=2 verdict=NOT_YET'
skp_list() { # <id:status:conclusion> ... -> the gh run list body, newest first
  local e out="" id st co; for e in "$@"; do IFS=: read -r id st co <<<"$e"
    out="${out:+$out,}{\"databaseId\":$id,\"headBranch\":\"main\",\"headSha\":\"$(printf '%040d' "$id")\",\"status\":\"$st\",\"conclusion\":\"$co\"}"; done
  printf '[%s]\n' "$out" > "$SKP/list.json"
}
skp_list 303:completed:success 302:completed:failure 301:completed:success
rm -f "$SKP"/log.*
skp_log 303 'Run terraform plan' 'no evidence here'
skp_log 302 'Doppler notice' "$SKG_GP" "$SKG_WF extra=forged" "$SKG_WF" 'gate_fail sub_condition=B_workspaces_luks_soak_days_below_floor' "$SKP_I" 'grade_text=NOT YET: waiting'
skp_log 301 "$SKG_GP" "$SKG_WP"
sec_open probe 15
skp_run
sk_check "G11 executed: the probe prints the newest run holding evidence with its branch, sha and conclusion, then its matched lines (soak, gate_fail, instance, grade_text), prefix stripped (exit 0)" \
  eval '[[ "$SKP_RC" -eq 0 && "$SKP_OUT" == "$(printf "%s\n%s\n%s\n%s\n%s\n%s" "run=302 branch=main sha=$(printf %040d 302) conclusion=failure" "$SKG_GP" "$SKG_WF" "gate_fail sub_condition=B_workspaces_luks_soak_days_below_floor" "$SKP_I" "grade_text=NOT YET: waiting")" ]]'
sk_check "G11 executed: the run list is the main branch of cf-lb-overlay.yml, limit 50, with status and conclusion (the older run is never read)" \
  eval 'grep -qE "^run list .*--workflow cf-lb-overlay\.yml" "$SKP/argv" && grep -qE "^run list .*--branch main" "$SKP/argv" && grep -qE "^run list .*--limit 50( |$)" "$SKP/argv" && grep -qE "^run list .*status,conclusion" "$SKP/argv" && ! grep -qE "^run view 301" "$SKP/argv"'
skp_log 302 "$SKG_GP" "$SKG_GP" "$SKG_WP" "$SKG_WP" "$SKG_WF" "$SKP_I" "$SKP_I"
skp_run
sk_check "G11 executed: at most 2 SOLEUR_SOAK_EVIDENCE lines (one per kind) and 1 SOLEUR_INSTANCE_SOAK line are printed" \
  eval '[[ "$SKP_RC" -eq 0 && "$(grep -c "^SOLEUR_SOAK_EVIDENCE " <<<"$SKP_OUT")" -eq 2 && "$(grep -c "^SOLEUR_INSTANCE_SOAK " <<<"$SKP_OUT")" -eq 1 ]]'
sk_check "fix round executed: the two soak lines are one per KIND (git_data and workspaces_luks once each, not the first two lines)" \
  eval '[[ "$(grep -c "^SOLEUR_SOAK_EVIDENCE kind=git_data " <<<"$SKP_OUT")" -eq 1 && "$(grep -c "^SOLEUR_SOAK_EVIDENCE kind=workspaces_luks " <<<"$SKP_OUT")" -eq 1 ]]'
skp_log 302 "$SKG_GP" "SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=PASS" 'grade_text=PASS: early' "$SKP_I" 'grade_text=NOT YET: waiting'
skp_run
sk_check "security fix round executed: the LAST instance and grade_text lines win (an earlier well-formed line in the step is not the verdict)" \
  eval '[[ "$SKP_RC" -eq 0 && "$SKP_OUT" == *"$SKP_I"* && "$SKP_OUT" == *"grade_text=NOT YET: waiting" && "$SKP_OUT" != *"verdict=PASS"* && "$SKP_OUT" != *"PASS: early"* ]]'
skp_log 302 'Run gate' 'gate_fail sub_condition=B_top_not_authorized'
skp_run
sk_check "code-quality fix round executed: a refused run with only a gate_fail line is a hit (it answers why), not passed over" \
  eval '[[ "$SKP_RC" -eq 0 && "$SKP_OUT" == "$(printf "%s\n%s" "run=302 branch=main sha=$(printf %040d 302) conclusion=failure" "gate_fail sub_condition=B_top_not_authorized")" ]]'
skp_list 304:in_progress: 303:completed:success 302:completed:failure
skp_log 304 "$SKG_GP"
skp_run
sk_check "R8 executed: a newer run still in progress is skipped (never read), the newest completed run with evidence is printed" eval '[[ "$SKP_RC" -eq 0 && "$SKP_OUT" == "run=302 "* ]] && ! grep -qE "^run view 304" "$SKP/argv"'
skp_list 305:completed:cancelled 302:completed:failure
skp_run
sk_check "R8 executed: a completed run whose log cannot be read (cancelled with no log) is skipped, not a read fault" eval '[[ "$SKP_RC" -eq 0 && "$SKP_OUT" == "run=302 "* ]] && grep -qE "^run view 305" "$SKP/argv"'
skp_list 305:completed:cancelled 306:completed:cancelled
skp_run
sk_check "R8 executed: no run log readable at all exits 3 (a read fault, not 'no evidence')" eval '[[ "$SKP_RC" -eq 3 ]]'
skp_list 307:completed:success
: > "$SKP/log.307"; printf 'staging_record\tsome step\t2026-11-18T12:43:37.1234567Z %s\n' "$SKG_GP" "$SKP_I" >> "$SKP/log.307"
skp_run
sk_check "security P3-b executed: a grammar-shaped line from another job is never printed (only ga_pool_update's two evidence steps are read)" eval '[[ "$SKP_RC" -eq 2 && "$SKP_OUT" != *SOLEUR_* ]]'
skp_list 303:completed:success 302:completed:failure 301:completed:success
skp_log 302 'nothing' ; skp_log 301 'nothing either'
skp_run
sk_check "G11 executed: a window with no evidence exits 2 with one line that carries neither token" \
  eval '[[ "$SKP_RC" -eq 2 && "$SKP_OUT" == "no soak evidence in the last 3 runs" && "$SKP_OUT" != *SOLEUR_* ]]'
skp_run --limit 2
sk_check "G11 executed: --limit narrows the window (2) and the no-match line names it" eval '[[ "$SKP_RC" -eq 2 && "$SKP_OUT" == "no soak evidence in the last 2 runs" ]] && grep -qE "^run list .*--limit 2( |$)" "$SKP/argv"'
skp_run --limit 51
sk_check "G11 executed: a --limit above 50 is refused (exit 64), nothing listed" eval '[[ "$SKP_RC" -eq 64 && ! -s "$SKP/argv" ]]'
printf 'not json' > "$SKP/list.json"; skp_run
sk_check "G11 executed: an unreadable run list exits 3 (a read fault is not 'no evidence')" eval '[[ "$SKP_RC" -eq 3 ]]'
skp_list 308:completed:success; skp_log 308 "$SKG_GP" 'grade_text=::error::forged' 'gate_fail sub_condition=x;y'
skp_run
sk_check "R8 executed: a grade_text line that is not verdict-shaped and a malformed gate_fail line are never printed" eval '[[ "$SKP_RC" -eq 0 && "$SKP_OUT" != *"::error::"* && "$SKP_OUT" != *"x;y"* ]]'
sec_close

# --- Minimum-cardinality guard (an empty loop must not GREEN with zero coverage) ---
MIN_CASES=658 # 330 -> 613 (#12849 §SK rows) -> 643 (#12934 review fixes R1-R10 + test-design rows) -> 652 (fix round: R4 class, gate body, if spellings, R2 parity, probe rows) -> 658 (fix round 2: parsed-YAML key checks + 5 mutants; measured)
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${TOTAL} total ==="
if [[ "$TOTAL" -lt "$MIN_CASES" ]]; then
  echo "GUARD FAIL: ran ${TOTAL} assertions, expected >= ${MIN_CASES}" >&2
  exit 2
fi
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
