#!/usr/bin/env bash
# Tests for scripts/tunnel-connector-census.sh (#6425).
#
# The census is the only VANTAGE-INDEPENDENT detector for the #6425 class (a second connector
# making tunnel ingress non-deterministic), so its classifier has to be right about two things
# that are easy to get wrong:
#   1. WHICH number it counts — three countable things exist and two of them make a correct fix
#      read as broken.
#   2. That an unreadable census is NOT a zero — otherwise a token expiry pages the operator
#      every 15 minutes against a healthy tunnel (the #6374 false-positive class).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./tunnel-connector-census.sh
source "$SCRIPT_DIR/tunnel-connector-census.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

# A connector entry with N live conns. Colos are the real ones observed on the live tunnel.
conn_entry() {  # $1=id $2=colo-prefix $3=n-conns
  jq -nc --arg id "$1" --arg colo "$2" --argjson n "$3" \
    '{id:$id, conns:[range($n) | {colo_name:($colo + (.|tostring)), is_pending_reconnect:false}]}'
}
census() {  # $1=JSON array of entries
  jq -nc --argjson r "$1" '{success:true, errors:[], messages:[], result:$r}'
}

echo "=== tunnel-connector-census.sh classifier tests (#6425) ==="

# --- The invariant: exactly one connector ---
ONE=$(census "[$(conn_entry a281fb1b0000000000000000000000ab hel 4)]")
assert_eq "1 connector with live conns → ok 1" "ok 1" "$(classify_connector_census 200 "$ONE")"

# --- The regression this exists to catch: the REAL 2-connector shape, measured live
# 2026-07-15 on tunnel 6410c1ec (a281fb1b = ams*/hel* = web-1; 8c57fcd5 = fra* = web-2).
TWO=$(census "[$(conn_entry a281fb1b0000000000000000000000ab hel 4), $(conn_entry 8c57fcd50000000000000000000000cd fra 4)]")
assert_eq "2 connectors (the live #6425 shape) → multi_connector 2" "multi_connector 2" "$(classify_connector_census 200 "$TWO")"

# THE COUNTING TRAP. On this exact body the two WRONG counts are 8 (total conns) and 4 (per-entry
# conns); the right one is 2. A classifier counting either wrong thing would still say
# "multi_connector" here — but would say it for a CORRECT single-connector tunnel too (4 != 1).
# So pin the count itself, and prove the 1-connector case is not mis-read as multi.
assert_eq "counts CONNECTORS not QUIC conns (1 connector x 4 conns is NOT multi)" \
  "ok 1" "$(classify_connector_census 200 "$(census "[$(conn_entry a281fb1b0000000000000000000000ab hel 4)]")")"

# --- A connector with zero live conns is not a live connector (stale/reconnecting entry) ---
STALE=$(census "[$(conn_entry a281fb1b0000000000000000000000ab hel 4), $(conn_entry deadbeef0000000000000000000000ef fra 0)]")
assert_eq "an entry with 0 live conns is not counted → ok 1" "ok 1" "$(classify_connector_census 200 "$STALE")"

# --- Zero is a real, distinct verdict: Cloudflare answered and said "nothing is serving" ---
assert_eq "well-formed census with no live connectors → zero_connectors 0" \
  "zero_connectors 0" "$(classify_connector_census 200 "$(census '[]')")"

# --- census_unavailable: an unreadable census must NEVER present as a connector verdict.
# Each of these would otherwise jq to length 0 and file a FALSE action-required P1 every 15
# minutes against a healthy tunnel. The -1 count makes "unknown" impossible to mistake for 0.
assert_eq "HTTP 403 (expired/insufficient token) → census_unavailable -1" \
  "census_unavailable -1" "$(classify_connector_census 403 '{"success":false,"errors":[{"code":10000,"message":"Authentication error"}]}')"
assert_eq "HTTP 500 → census_unavailable -1" \
  "census_unavailable -1" "$(classify_connector_census 500 'upstream error')"
assert_eq "HTTP 000 (network blip, empty body) → census_unavailable -1" \
  "census_unavailable -1" "$(classify_connector_census 000 '')"
assert_eq "200 but success:false (CF reports failures in-band) → census_unavailable -1" \
  "census_unavailable -1" "$(classify_connector_census 200 '{"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"result":null}')"
assert_eq "200 with result:null → census_unavailable -1 (NOT zero_connectors)" \
  "census_unavailable -1" "$(classify_connector_census 200 '{"success":true,"result":null}')"
assert_eq "200 with a non-array result → census_unavailable -1" \
  "census_unavailable -1" "$(classify_connector_census 200 '{"success":true,"result":{"id":"x"}}')"
assert_eq "200 with a non-JSON body → census_unavailable -1" \
  "census_unavailable -1" "$(classify_connector_census 200 '<html>502 Bad Gateway</html>')"

# --- describe_connectors: the alert body's evidence. origin_ip is null on both entries (live),
# so colo geography is the only host attribution available from this endpoint.
DESC=$(describe_connectors "$TWO")
if [[ "$DESC" == *"id=a281fb1b"* && "$DESC" == *"id=8c57fcd5"* && "$DESC" == *"colos=hel0,hel1,hel2,hel3"* ]]; then
  echo "  PASS: describe_connectors emits per-connector id + colos for the alert body"; PASS=$((PASS + 1))
else
  echo "  FAIL: describe_connectors output unusable"; echo "    actual: $DESC"; FAIL=$((FAIL + 1))
fi
assert_eq "describe_connectors never fails the census on a garbage body" "" "$(describe_connectors 'not json')"

# describe_connectors output crosses a GITHUB_OUTPUT heredoc and a markdown issue body. A colo
# name carrying a newline + the heredoc delimiter would break out of the `evidence<<CENSUS_EOF`
# block and forge arbitrary step outputs (e.g. flipping `verdict`), turning an alert into a
# silent no-op. Sanitisation is what makes the heredoc safe.
EVIL=$(census "[$(jq -nc '{id:"aaaabbbbccccdddd", conns:[{colo_name:"x\nCENSUS_EOF\nverdict=ok"}]}')]")
EVIL_OUT=$(describe_connectors "$EVIL")
if [[ "$EVIL_OUT" == *"CENSUS_EOF"$'\n'* ]]; then
  echo "  FAIL: a colo name can break out of the GITHUB_OUTPUT heredoc"; FAIL=$((FAIL + 1))
else
  echo "  PASS: injected newline cannot break out of the GITHUB_OUTPUT heredoc"; PASS=$((PASS + 1))
fi
assert_eq "backticks/\$() are stripped from the markdown issue body" \
  "" "$(describe_connectors "$(census "[$(jq -nc '{id:"a", conns:[{colo_name:"`id`$(id)"}]}')]")" | tr -cd '`$()')"

echo ""
echo "=== classify_conn_versions — advisory floor (eMudhra, floor ${CLOUDFLARED_VERSION_FLOOR}) ==="

# A connector entry whose conns each carry a client_version. $1=id $2=colo-prefix
# $3..=per-conn versions (one conn per version arg).
conn_entry_v() {
  local id="$1" colo="$2"; shift 2
  jq -nc --arg id "$id" --arg colo "$colo" \
    --argjson vs "$(printf '%s\n' "$@" | jq -R . | jq -sc .)" \
    '{id:$id, conns:[range($vs|length) | {colo_name:($colo + (.|tostring)), client_version:$vs[.], is_pending_reconnect:false}]}'
}

# MUTATION 1 — a single below-floor live conn pages. 2026.3.0 is the REAL version the prod
# connector ran when the advisory landed.
BELOW=$(census "[$(conn_entry_v a281fb1b0000000000000000000000ab hel 2026.3.0 2026.3.0 2026.3.0 2026.3.0)]")
assert_eq "1 connector, conns at 2026.3.0 → below_floor" \
  "below_floor 4 0" "$(classify_conn_versions "$BELOW")"

# The compliant steady state: every live conn at the pinned provision version.
CURRENT=$(census "[$(conn_entry_v a281fb1b0000000000000000000000ab hel 2026.10.4 2026.10.4 2026.10.4 2026.10.4)]")
assert_eq "1 connector, conns at 2026.10.4 → versions_ok" \
  "versions_ok 0 0" "$(classify_conn_versions "$CURRENT")"

# Boundary: a conn AT the floor is compliant (floor is inclusive: >=).
ATFLOOR=$(census "[$(conn_entry_v a281fb1b0000000000000000000000ab hel "$CLOUDFLARED_VERSION_FLOOR" 2026.10.4 2026.10.4 2026.10.4)]")
assert_eq "a conn AT the floor → versions_ok (floor is inclusive)" \
  "versions_ok 0 0" "$(classify_conn_versions "$ATFLOOR")"

# MUTATION 2 — the check is PER-CONN, not per-connector: one stale conn on an otherwise
# "current" connector still pages (a second member registered after a compliant first).
SPLIT=$(census "[$(conn_entry_v a281fb1b0000000000000000000000ab hel 2026.10.4 2026.9.0 2026.10.4 2026.10.4)]")
assert_eq "split conns 2026.10.4 + 2026.9.0 → below_floor (per-conn, not per-connector)" \
  "below_floor 1 0" "$(classify_conn_versions "$SPLIT")"

# MUTATION 5 — the lexical trap. "2026.9.0" sorts ABOVE "2026.10.2" lexically, so a string or
# non--V compare silently inverts the floor. Field-wise numeric compare must catch it.
LEXTRAP=$(census "[$(conn_entry_v a281fb1b0000000000000000000000ab hel 2026.9.0)]")
assert_eq "lexical-trap pair: 2026.9.0 < floor 2026.10.2 NUMERICALLY → below_floor" \
  "below_floor 1 0" "$(classify_conn_versions "$LEXTRAP")"
assert_eq "  (control) 2026.10.2 vs 2026.9.0 as plain strings DOES order wrong — the trap is real" \
  "2026.9.0" "$(printf '%s\n%s\n' "2026.9.0" "2026.10.2" | sort | tail -1)"

# MUTATION 3 — an absent or malformed client_version on a live conn is a SOFT breadcrumb,
# never a page (mirrors census_unavailable; must-PASS shape, not a below_floor).
ABSENTV=$(census "[$(conn_entry a281fb1b0000000000000000000000ab hel 4)]")
assert_eq "conn with NO client_version field → version_unreadable (soft, no page)" \
  "version_unreadable 0 4" "$(classify_conn_versions "$ABSENTV")"
MALFORMED=$(census "[$(jq -nc '{id:"a281fb1b0000000000000000000000ab", conns:[{colo_name:"hel0", client_version:"v2026.10", is_pending_reconnect:false},{colo_name:"hel1", client_version:null, is_pending_reconnect:false}]}')]")
assert_eq "conn with malformed/null client_version → version_unreadable (soft, no page)" \
  "version_unreadable 0 2" "$(classify_conn_versions "$MALFORMED")"
# below_floor still outranks unreadable when both are present on the same connector.
MIXED=$(census "[$(jq -nc '{id:"a281fb1b0000000000000000000000ab", conns:[{colo_name:"hel0", client_version:"2026.9.0"},{colo_name:"hel1"}]}')]")
assert_eq "below-floor + unreadable on one connector → below_floor wins (the page must not hide)" \
  "below_floor 1 1" "$(classify_conn_versions "$MIXED")"

# A non-census body is version_unreadable, NOT versions_ok — an unreadable read must never
# present as "compliant" (the same lie census_unavailable exists to prevent).
assert_eq "garbage body → version_unreadable (never a false 'compliant')" \
  "version_unreadable -1 -1" "$(classify_conn_versions 'not json')"
assert_eq "result:null → version_unreadable" \
  "version_unreadable -1 -1" "$(classify_conn_versions '{"success":true,"result":null}')"

# MUTATION 4 — a dropped/empty floor constant must refuse to silently pass.
assert_eq "floor constant emptied → version_floor_invalid (detector refuses to pass)" \
  "version_floor_invalid -1 -1" "$(CLOUDFLARED_VERSION_FLOOR='' classify_conn_versions "$CURRENT")"
assert_eq "floor constant malformed → version_floor_invalid" \
  "version_floor_invalid -1 -1" "$(CLOUDFLARED_VERSION_FLOOR='latest' classify_conn_versions "$CURRENT")"
assert_eq "floor constant itself still parses as N.N.N (anti-vacuity: the guard is armed)" \
  "armed" "$( [[ "$CLOUDFLARED_VERSION_FLOOR" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo armed || echo DISARMED )"

# describe_conn_versions — the alert body's per-conn evidence.
VDESC=$(describe_conn_versions "$SPLIT")
if [[ "$VDESC" == *"client_version=2026.9.0"* && "$VDESC" == *"client_version=2026.10.4"* && "$VDESC" == *"colo=hel1"* ]]; then
  echo "  PASS: describe_conn_versions emits per-conn colo + client_version for the alert body"; PASS=$((PASS + 1))
else
  echo "  FAIL: describe_conn_versions output unusable"; echo "    actual: $VDESC"; FAIL=$((FAIL + 1))
fi
assert_eq "describe_conn_versions never fails on a garbage body" "" "$(describe_conn_versions 'not json')"
# An injected newline/backtick is stripped PER FIELD before it can break the GITHUB_OUTPUT
# heredoc or the markdown body — the surviving output is exactly one sanitized record.
assert_eq "describe_conn_versions sanitises an injected field" \
  "conn=connid12 colo=xCENSUS_EOFverdictok client_version=1id" \
  "$(describe_conn_versions "$(census "[$(jq -nc '{id:"a", conns:[{id:"connid1234567", colo_name:"x\nCENSUS_EOF\nverdict=ok", client_version:"1\n`id`"}]}')]")")"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
