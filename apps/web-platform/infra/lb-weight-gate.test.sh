#!/usr/bin/env bash
# Tests for lb-weight-gate.sh — the rebuilt fail-closed, SHAPE-ONLY ADR-068 §(c) / ADR-141 D3
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
#   §0 TOP-GUARD (ADR-141 D3): the standby PASS branch (weight==0 & web-2 ∉ rotation) + the
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
    [SOLEUR_SERVING_ROTATION]='web-1,web-2'
    [SOLEUR_PROXY_BIND]='10.0.1.10'
    [SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.11'
    [SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11"}'
    [GIT_DATA_STORE_ENABLED]='true'
    [GIT_DATA_LUKS_CUTOVER_AT]="$ELAPSED_CUTOVER"
    [GIT_DATA_LUKS_SOAK_DAYS]='3'
    [WORKSPACES_LUKS_CUTOVER_AT]="$ELAPSED_CUTOVER"
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
  out=$(env -i PATH="$PATH" "${args[@]}" bash "$GATE" 2>"$errfile") && GATE_RC=0 || GATE_RC=$?
  GATE_OUT="$out"
  GATE_ERR="$(cat "$errfile")"
  rm -f "$errfile"
}

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1 (rc=${GATE_RC})"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }

assert_zero()    { if [[ "$GATE_RC" -eq 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_nonzero() { if [[ "$GATE_RC" -ne 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_stdout_contains() {
  if [[ "$GATE_OUT" == *"$2"* ]]; then pass "$1"; else fail "$1 — stdout missing '$2'"; fi
}
assert_stderr_contains() {
  if [[ "$GATE_ERR" == *"sub_condition=$2"* ]]; then pass "$1"
  else fail "$1 — stderr missing 'sub_condition=$2' (got: ${GATE_ERR})"; fi
}
assert_rejects_with() {
  assert_nonzero "$1"
  assert_stderr_contains "$1 [sub_condition]" "$2"
}

echo "=== lb-weight-gate.sh test suite (rebuilt #6575 / ADR-141 D3) ==="

# =============================================================================
# §0 — TOP-GUARD (ADR-141 D3): the serving-weight polarity fix.
# =============================================================================

# 0a. THE #6575-FLAW FIX: the correct out-of-band standby state — web-2 weight==0, NOT in the
#     serving rotation — PASSES, even with NO valid flip-time roster/relay env at all (proving the
#     short-circuit runs BEFORE Condition A/B). A correct pre-flip config CAN pass this gate.
reset_def
DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'
DEF[SOLEUR_SERVING_ROTATION]=''            # explicit empty = "no rotation" (a SET, valid state)
unset 'DEF[SOLEUR_PROXY_BIND]' 'DEF[SOLEUR_PROXY_PEER_ALLOWLIST]' 'DEF[SOLEUR_HOST_ROSTER]'
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
reset_def; unset 'DEF[SOLEUR_PROXY_BIND]'; run_with_def
assert_rejects_with "SOLEUR_PROXY_BIND missing" "A_proxy_bind_empty"
reset_def; DEF[SOLEUR_PROXY_BIND]='   '; run_with_def
assert_rejects_with "SOLEUR_PROXY_BIND whitespace-only" "A_proxy_bind_empty"

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
# §6459 — Condition B WORKSPACES_LUKS precondition (ADR-141 D3 coupling #2). A plaintext web-2
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
assert_no_grep "C.1b: dns.tf app record does NOT reference hcloud_server.web[\"web-2\"]" dns.tf \
  'hcloud_server\.web\["web-2"\]'

# C.2 — the single tunnel connector predicate still gates registration to web-1 (each.key=="web-1"),
#       so web-2 never registers as a tunnel connector (ADR-114 I1 — no coin-flipped ingress).
assert_grep    "C.2: server.tf tunnel connector predicate is each.key == \"web-1\"" server.tf \
  'web_tunnel_connector[[:space:]]*=[[:space:]]*each\.key[[:space:]]*==[[:space:]]*"web-1"'

# C.3 — no cloudflare_load_balancer pools web-2 at weight>0. Today there is NO LB at all (Phase 6),
#       so the assertion is: no cloudflare_load_balancer_pool resource exists yet. When the LB lands
#       in Phase 6, this assertion must be tightened to "no web-2 origin with weight>0 pre-flip".
# Glob $SCRIPT_DIR explicitly (NOT a bare `*.tf`, which would expand against the CALLER's CWD and
# make the assertion count — and the MIN_CASES guard — non-deterministic across invocation dirs;
# the terraform-cwd class). One aggregate assertion over the whole infra dir: no .tf declares a
# cloudflare_load_balancer yet (LB is Phase 6). When the LB lands, tighten this to "no web-2 origin
# with weight>0 pre-flip". Fail-closed: zero .tf files found = a moved/renamed dir = FAIL.
lb_hits=0; tf_seen=0
for f in "$SCRIPT_DIR"/*.tf; do
  [[ -f "$f" ]] || continue
  tf_seen=$((tf_seen + 1))
  grep -qE 'resource[[:space:]]+"cloudflare_load_balancer' "$f" && lb_hits=$((lb_hits + 1)) || true
done
TOTAL=$((TOTAL + 1))
if [[ "$tf_seen" -lt 1 ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: C.3-sweep: no .tf files found under $SCRIPT_DIR (fail-closed — dir moved?)"
elif [[ "$lb_hits" -eq 0 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: C.3-sweep: none of $tf_seen .tf files declares a cloudflare_load_balancer (LB is Phase 6)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: C.3-sweep: $lb_hits .tf file(s) declare a cloudflare_load_balancer — tighten Condition C to assert web-2 weight==0 pre-flip"
fi

# --- Minimum-cardinality guard (an empty loop must not GREEN with zero coverage) ---
MIN_CASES=70
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
