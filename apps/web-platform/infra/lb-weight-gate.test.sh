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
# Gated-variable weight term (serve-arm prep): web-2's weight may be the literal 0 OR exactly
# var.web2_lb_weight (whose default is 0 and whose only feeder is the serve arm — C.4 below).
# Any other expression is not a drained member.
c3_fixture varok 'resource "cloudflare_load_balancer_pool" "web_1" {
  origins {
    name    = "web-2"
    weight  = var.web2_lb_weight
  }
}'
assert_c3 "C.3-fixture: weight = var.web2_lb_weight scans clean (default-0 gated variable)" "0 1 0"
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
#   V   the variable's DEFAULT is 0 (the default plan is a no-op) and it admits only {0,1};
#   F   the ONLY feeder in the whole tree is the ga_pool_update plan step of cf-lb-overlay.yml, and
#       its value is 1 only when mode=serve; every other path (routine apply, drift plan, laptop
#       plan, drain mode) therefore sees 0;
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
c4_assert "C.4-V2: web2_lb_weight is type = number with default = 0 (default plan is a no-op)" \
  "$(grep -qE '^[[:space:]]*type[[:space:]]*=[[:space:]]*number[[:space:]]*$' <<<"$V_BLOCK" && grep -qE '^[[:space:]]*default[[:space:]]*=[[:space:]]*0[[:space:]]*$' <<<"$V_BLOCK" && echo 1 || echo 0)"
c4_assert "C.4-V3: web2_lb_weight has a validation admitting ONLY 0 or 1" \
  "$(grep -qE 'validation[[:space:]]*\{' <<<"$V_BLOCK" && grep -qE 'condition[[:space:]]*=[[:space:]]*var\.web2_lb_weight[[:space:]]*==[[:space:]]*0[[:space:]]*\|\|[[:space:]]*var\.web2_lb_weight[[:space:]]*==[[:space:]]*1[[:space:]]*$' <<<"$V_BLOCK" && echo 1 || echo 0)"
c4_assert "C.4-V4: web2_lb_weight is declared exactly once in the tree's .tf files" \
  "$([[ "$(grep -hE '^variable[[:space:]]+"web2_lb_weight"' "$SCRIPT_DIR"/*.tf | wc -l)" -eq 1 ]] && echo 1 || echo 0)"
c4_assert "C.4-V5: cloudflare-lb.tf feeds web-2's origin weight from var.web2_lb_weight" \
  "$(grep -qE '^[[:space:]]*weight[[:space:]]*=[[:space:]]*var\.web2_lb_weight[[:space:]]*$' "$SCRIPT_DIR/cloudflare-lb.tf" && echo 1 || echo 0)"
c4_assert "C.4-V6: web-1's origin weight stays the literal 1 (no variable on the serving member)" \
  "$(awk '/name[[:space:]]*=[[:space:]]*"web-1"/ {on=1} on && /weight/ {print; exit}' "$SCRIPT_DIR/cloudflare-lb.tf" | grep -qE 'weight[[:space:]]*=[[:space:]]*1[[:space:]]*$' && echo 1 || echo 0)"

# --- F: the feeder census ---------------------------------------------------------------------
# Every file in the live tree that names the variable, minus this test and the knowledge base.
FEEDERS="$(cd "$REPO_ROOT" && grep -rIl 'web2_lb_weight' .github apps scripts plugins tests 2>/dev/null \
  | grep -vE '(^|/)node_modules/' | grep -vE '^apps/web-platform/infra/lb-weight-gate\.test\.sh$' | LC_ALL=C sort | tr '\n' ' ' || true)"
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
  local n; n="$(grep -nE "^      - name:.*($1)" <<<"$JOB" | head -1 | cut -d: -f1)"; echo "${n:-0}"
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
c4_assert "C.4-F6: web2_lb_weight appears on exactly ONE non-comment line of cf-lb-overlay.yml (no other arm / job feeds it)" \
  "$([[ "$(c4_nocomment "$WF" | grep -c 'web2_lb_weight')" -eq 1 ]] && echo 1 || echo 0)"
c4_assert "C.4-F7: no other workflow names web2_lb_weight (routine apply, drift and validation plans stay at default 0)" \
  "$([[ -z "$(cd "$REPO_ROOT" && grep -lE 'web2_lb_weight|WEB2_LB_WEIGHT' .github/workflows/*.yml | grep -v 'cf-lb-overlay.yml')" ]] && echo 1 || echo 0)"

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

# --- P: the synthetic per-host bind never leaves the gate's own check -------------------------
BIND_VAL="$(grep -oE 'SOLEUR_PROXY_BIND="[^"]+"' <<<"$GATE_STEP" | head -1 | sed -E 's/^SOLEUR_PROXY_BIND="(.*)"$/\1/' || true)"
ROT_VAL="$(grep -oE 'SOLEUR_SERVING_ROTATION="[^"]+"' <<<"$GATE_STEP" | head -1 | sed -E 's/^SOLEUR_SERVING_ROTATION="(.*)"$/\1/' || true)"
c4_assert "C.4-P1: the gate chain injects a non-empty synthetic SOLEUR_PROXY_BIND and a rotation naming web-2 (got bind='${BIND_VAL}' rotation='${ROT_VAL}')" \
  "$([[ -n "$BIND_VAL" && "$ROT_VAL" == *web-2* ]] && echo 1 || echo 0)"
c4_assert "C.4-P2: SOLEUR_PROXY_BIND is named on exactly one non-comment line of the workflow (never exported to GITHUB_ENV, never written to Doppler)" \
  "$([[ "$(c4_nocomment "$WF" | grep -c 'SOLEUR_PROXY_BIND')" -eq 1 ]] && echo 1 || echo 0)"
c4_assert "C.4-P3: the ga_pool_update job never writes Doppler (no 'doppler secrets set|upload|delete')" \
  "$([[ -z "$(c4_nocomment <(printf '%s\n' "$JOB") | grep -E 'doppler[[:space:]]+secrets[[:space:]]+(set|upload|delete)')" ]] && echo 1 || echo 0)"
c4_assert "C.4-P4: the three injected inputs are assigned AFTER the doppler run (they override any ambient prd value)" \
  "$([[ "$(grep -nE 'doppler run' <<<"$GATE_STEP" | head -1 | cut -d: -f1)" -lt "$(grep -nE 'SOLEUR_PROXY_BIND=' <<<"$GATE_STEP" | head -1 | cut -d: -f1)" ]] && echo 1 || echo 0)"

# --- G: the gate, fed exactly what the arm injects, keeps every fail-closed condition ----------
# Weight comes from the pin step's serve branch (1); rotation and bind from the gate-chain step.
SERVE_W="$(grep -oE 'then WEB2_LB_WEIGHT=[0-9]+' <<<"$PIN_STEP" | head -1 | grep -oE '[0-9]+$' || true)"
arm_env() { # the injected trio, as the workflow sets them in serve mode
  reset_def
  DEF[SOLEUR_WEB2_SERVING_WEIGHT]="${SERVE_W:-}"
  DEF[SOLEUR_SERVING_ROTATION]="$ROT_VAL"
  DEF[SOLEUR_PROXY_BIND]="$BIND_VAL"
}
arm_env; run_with_def
assert_zero "C.4-G1: arm-injected trio + every precondition met → gate passes"
assert_stdout_contains "C.4-G1b: …and prints the flip-authorization marker the step greps for" "requires_runtime_bind_probe=true"
arm_env; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
assert_rejects_with "C.4-G2: arm-injected trio + git-data store disabled → refused" "B_git_data_store_disabled"
arm_env; unset 'DEF[GIT_DATA_LUKS_CUTOVER_AT]'; run_with_def
assert_rejects_with "C.4-G3: arm-injected trio + GIT_DATA_LUKS_CUTOVER_AT absent → refused" "B_luks_cutover_marker_absent"
arm_env; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_rejects_with "C.4-G4: arm-injected trio + git-data soak not elapsed → refused" "B_luks_soak_not_elapsed"
arm_env; unset 'DEF[WORKSPACES_LUKS_CUTOVER_AT]'; run_with_def
assert_rejects_with "C.4-G5: arm-injected trio + WORKSPACES_LUKS_CUTOVER_AT absent (today's Doppler state) → refused" "B_workspaces_luks_marker_absent"
arm_env; DEF[WORKSPACES_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_rejects_with "C.4-G6: arm-injected trio + workspaces soak not elapsed → refused" "B_workspaces_luks_soak_not_elapsed"
arm_env; DEF[GIT_DATA_LUKS_SOAK_DAYS]='0'; run_with_def
assert_rejects_with "C.4-G7: arm-injected trio + soak days 0 → refused (0 is rejected, not 'no soak')" "B_luks_soak_days_invalid"
arm_env; DEF[WORKSPACES_LUKS_SOAK_DAYS]='0'; run_with_def
assert_rejects_with "C.4-G8: arm-injected trio + workspaces soak days 0 → refused" "B_workspaces_luks_soak_days_invalid"
arm_env; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10"}'; run_with_def
assert_rejects_with "C.4-G9: arm-injected trio + roster omits web-2 → refused" "A_web2_not_in_roster"
arm_env; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.10'; run_with_def
assert_rejects_with "C.4-G10: arm-injected trio + web-2 addr not in allowlist → refused" "A_web2_addr_not_in_allowlist"
# The drain value is NOT authorization: weight 0 without web-2 in rotation is the standby branch,
# which prints the SHAPE-ONLY banner and NOT the marker the serve step requires.
arm_env; DEF[SOLEUR_WEB2_SERVING_WEIGHT]='0'; DEF[SOLEUR_SERVING_ROTATION]=''; run_with_def
assert_zero "C.4-G11: standby inputs pass the gate…"
c4_assert "C.4-G11b: …but WITHOUT requires_runtime_bind_probe=true (the serve step would refuse it)" \
  "$([[ "$GATE_OUT" != *requires_runtime_bind_probe=true* ]] && echo 1 || echo 0)"

# --- R: the relay bind probe (serve only) — #12167 -------------------------------------------------
# The gate chain's A.1 shape check is VACUOUS for the real bind (it is fed a synthetic value), and the
# pool-health read proves origin HEALTH, not that the relay listens on web-2's private address. This step
# closes that: it reads web-2's OWN relay report from Better Stack (scripts/lib/web2-relay-rows.sh, the
# credentials ride the environment, never argv) and refuses unless >= 2 rows in the last 180 s, newest <= 120 s,
# every row proxy_state=listening on the address Terraform STATE holds for web-2, port 8443, workspaces_populated=1.
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
c4_assert "C.4-R5: the expected address is READ FROM STATE (terraform show -json, hcloud_server_network.web[\"web-2\"]) and handed to the judge as a variable" \
  "$(grep -qF 'terraform show -json' <<<"$PROBE_RUN_NC" && grep -qF 'hcloud_server_network.web[\"web-2\"]' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_judge[[:space:]]+"[^"]+"[[:space:]]+"\$\{?[A-Z_0-9]+\}?"' <<<"$PROBE_RUN_NC" && echo 1 || echo 0)"
c4_assert "C.4-R5b: no literal IPv4 address anywhere in the probe step" \
  "$([[ -n "$PROBE_NC" && -z "$(grep -E '(^|[^0-9.])[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)' <<<"$PROBE_NC")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R6: the step never names SOLEUR_PROXY_BIND, never writes Doppler or GITHUB_ENV" \
  "$([[ -n "$PROBE_NC" && -z "$(grep -E 'SOLEUR_PROXY_BIND|doppler[[:space:]]+secrets|GITHUB_ENV' <<<"$PROBE_NC")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R7: the three BETTERSTACK_QUERY_* credentials ride the step env, each refused when empty, none on a command line" \
  "$([[ "$(grep -cE '^          BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD): \$\{\{ secrets\.BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD) \}\}$' <<<"$PROBE_STEP")" -eq 3 ]] && grep -qE 'for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD' <<<"$PROBE_RUN_NC" && grep -qE '\-z "\$\{!v:-\}"' <<<"$PROBE_RUN_NC" && [[ -z "$(grep -E 'BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD)[^ ]*[[:space:]]*(=|\))' <<<"$(grep -vE 'for v in|^[[:space:]]*(if|echo)' <<<"$PROBE_RUN_NC")")" ]] && echo 1 || echo 0)"
c4_assert "C.4-R8: the step uses the shared helper (wrr_fetch, wrr_judge) and passes ONLY on a GREEN verdict" \
  "$(grep -qF 'scripts/lib/web2-relay-rows.sh' <<<"$PROBE_RUN_NC" && grep -qE '^wrr_fetch|[[:space:]]wrr_fetch ' <<<"$PROBE_RUN_NC" && grep -qE 'wrr_judge' <<<"$PROBE_RUN_NC" && grep -qE 'VERDICT.*!=.*GREEN' <<<"$PROBE_RUN_NC" && echo 1 || echo 0)"

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
case "$(cat "$FX/mode" 2>/dev/null)" in 503) printf '{"error":"x"}'; exit 22 ;; timeout) exit 28 ;; esac
cat "$FX/rows"
STUB
chmod +x "$R_BIN/terraform" "$R_BIN/curl"
r_state() { printf '{"values":{"root_module":{"resources":[{"address":"hcloud_server_network.web[\\"web-1\\"]","values":{"ip":"10.0.1.10"}},{"address":"hcloud_server_network.web[\\"web-2\\"]","values":{"ip":"%s"}}]}}}' "$1" > "$R_FX/state"; }
r_line() { printf 'relay_probe proxy_state=%s addr=%s port=%s workspaces_populated=%s' "${1:-listening}" "${2:-10.0.1.11}" "${3:-8443}" "${4:-1}"; }
r_row() { jq -cn --arg a "$1" --arg l "$2" --arg h "${3:-soleur-web-2}" '{age_s:$a,host_name:$h,line:$l}'; }
R_OUT=""; R_RC=0
r_exec() { # r_exec [ENV=VAL ...] — run the step body in a clean env; output -> R_OUT, rc -> R_RC
  : > "$R_WORK/leak"; : > "$R_WORK/calls"; : > "$R_WORK/summary"
  R_OUT="$(cd "$R_WORK" && env -i PATH="$R_BIN:/usr/bin:/bin" HOME="$R_WORK" TMPDIR="$R_WORK" FX="$R_FX" LEAK="$R_WORK/leak" CALLS="$R_WORK/calls" \
    GITHUB_WORKSPACE="$REPO_ROOT" GITHUB_STEP_SUMMARY="$R_WORK/summary" GH_TOKEN=decoy-gh DOPPLER_TOKEN=decoy-doppler AWS_SECRET_ACCESS_KEY=decoy-aws \
    BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass \
    "$@" bash "$R_WORK/probe-run.sh" 2>&1)" && R_RC=0 || R_RC=$?
}
e_refuse() { # e_refuse <desc> <needle> [ENV=VAL ...] — exit 1 with an ::error:: line that NAMES the reason (a refusal for the wrong reason is red)
  r_exec "${@:3}"
  c4_assert "$1 → exit 1, refused for: $2" "$([[ "$R_RC" -eq 1 && "$R_OUT" == *"::error::"* && "$R_OUT" == *"$2"* && ! -s "$R_WORK/leak" ]] && echo 1 || echo 0)"
}
e_reset() { : > "$R_FX/mode"; rm -f "$R_FX/tf.fail"; r_state 10.0.1.11; { r_row 20 "$(r_line)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; }

if [[ -n "$PROBE_RUN" ]]; then
e_reset; r_exec
c4_assert "C.4-E1: two healthy rows on the state address → exit 0 and a GREEN line in the run summary" \
  "$([[ "$R_RC" -eq 0 && "$(cat "$R_WORK/summary")" == *GREEN* ]] && echo 1 || echo 0)"
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
e_reset; { r_row 20 "$(r_line listening ::)"; r_row 80 "$(r_line listening ::)"; } > "$R_FX/rows"; e_refuse "C.4-E9: addr=:: (wildcard)" "reason=addr_wildcard"
e_reset; { r_row 20 "$(r_line listening 0.0.0.0)"; r_row 80 "$(r_line listening 0.0.0.0)"; } > "$R_FX/rows"; e_refuse "C.4-E9b: addr=0.0.0.0 (wildcard)" "reason=addr_wildcard"
e_reset; r_state 10.0.1.12; e_refuse "C.4-E10: rows say 10.0.1.11 but STATE says 10.0.1.12 (address compared against state, not a literal)" "reason=addr_mismatch"
e_reset; { r_row 20 "$(r_line listening 10.0.1.11 8444)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E11: port 8444" "reason=port_mismatch"
e_reset; { r_row 20 "$(r_line listening 10.0.1.11 8443 0)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E12: workspaces_populated=0" "reason=workspaces_unpopulated"
e_reset; { r_row 20 "$(r_line) extra=1"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E13: trailing text after the grammar (substring match must not pass)" "reason=row_malformed"
e_reset; { r_row 20 "x$(r_line)"; r_row 80 "$(r_line)"; } > "$R_FX/rows"; e_refuse "C.4-E13b: leading text before the grammar" "reason=row_malformed"
e_reset; { r_row 20 "$(r_line)" soleur-web-platform; r_row 80 "$(r_line)" soleur-web-platform; } > "$R_FX/rows"; e_refuse "C.4-E14: rows from another host do not count" "reason=rows_below_floor"
e_reset; touch "$R_FX/tf.fail"; e_refuse "C.4-E15: terraform show -json fails" "terraform show -json failed"
e_reset; printf '{"values":{"root_module":{"resources":[]}}}' > "$R_FX/state"; e_refuse "C.4-E16: web-2's private address absent from state" "private IPv4 is absent from state"
e_reset; printf '{"values":{"root_module":{"resources":[{"address":"hcloud_server_network.web[\\"web-2\\"]","values":{"ip":"not-an-ip"}}]}}}' > "$R_FX/state"; e_refuse "C.4-E16b: web-2's state address is not a private IPv4" "private IPv4 is absent from state"
else
  c4_bad "C.4-E*: the probe step has no run body — the execute-the-step fixtures cannot run (vacuity refused)"
fi

# --- Minimum-cardinality guard (an empty loop must not GREEN with zero coverage) ---
MIN_CASES=204
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
