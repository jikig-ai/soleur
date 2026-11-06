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
  trap 'rm -f "$errfile"' RETURN  # owning trap (ADR-129): errfile cleaned on every function return, even if `cat` fails
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
assert_stderr_contains() {
  if [[ "$GATE_ERR" == *"sub_condition=$2"* ]]; then pass "$1"
  else fail "$1 — stderr missing 'sub_condition=$2' (got: ${GATE_ERR})"; fi
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
  app_records=$(grep -cE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"app"[[:space:]]*$' "$SCRIPT_DIR/dns.tf")
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
assert_grep    "C.2: server.tf tunnel connector predicate is each.key == \"web-2\"" server.tf \
  'web_tunnel_connector[[:space:]]*=[[:space:]]*each\.key[[:space:]]*==[[:space:]]*"web-2"'

# C.3 — DRAINED-SHAPE invariant (2026-11-01 rewrite, replaces structural absence;
#       pairing/anchoring hardened PR #11766). With web-2 pooled as a drained member
#       (ADR-068 §(b) — weight 0, health-checked, zero traffic until the #6027 window
#       flip), the assertion is BLOCK-SCOPE over the .tf files that declare a
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
      w0 = ($0 ~ /weight[[:space:]]*=[[:space:]]*0([[:space:]]|#|$)/) ? 1 : 0
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
      if ($0 ~ /^[[:space:]]*weight[[:space:]]*=[[:space:]]*0([[:space:]]|#|$)/) w0 = 1
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
elif [[ "$web2_blocks" -lt 1 ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: C.3-sweep: no origins block names web-2 — the drained member is missing (or a resource label was renamed; assertions must not vacuously pass)"
elif [[ "$web2_bad_blocks" -gt 0 || "$web2_stray" -gt 0 ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: C.3-sweep: $web2_bad_blocks web-2 origins block(s) without 'weight = 0' + $web2_stray stray web-2 reference(s) outside origins blocks — web-2 must stay a drained member pre-flip"
else
  PASS=$((PASS + 1)); echo "  PASS: C.3-sweep: $web2_blocks web-2 origins block(s) at weight = 0, no stray web-2 references — drained member holds"
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
rm -rf "$C3_TMP"

# --- Minimum-cardinality guard (an empty loop must not GREEN with zero coverage) ---
MIN_CASES=72
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
