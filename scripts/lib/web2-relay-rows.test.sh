#!/usr/bin/env bash
# web2-relay-rows.test.sh — offline fixtures for scripts/lib/web2-relay-rows.sh (#12167).
#
# Two halves:
#   J  the PURE judges: wrr_judge <rows.jsonl> (web-2's own line: addr=0.0.0.0 port=8443, the in-container wildcard
#      the shipped design binds; docker publishes the private IP) and wrr_peer_judge <rows.jsonl> <web2-ip> (web-1's
#      deploy-time relay_peer_probe row for web-2: newest must be result=ok). Every refusal has a fixture, and the
#      GREEN arm is the only one that may print GREEN. Ages are stated in the rows (the server computes
#      them), so there is no clock and no date-faking. Fixture boundaries sit one second either side.
#   Q  the query function (wrr_fetch): a PATH-stubbed `curl` serves the answer through the REAL
#      scripts/betterstack-query.sh. It asserts the credentials ride stdin (never argv), that no
#      secret-shaped variable but the three BETTERSTACK_QUERY_* reaches the query child, and that the SQL
#      pins the host, the 180 s window and the line prefix. An unanswered read is rc 1, never a verdict.
# Every row is synthesized.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/web2-relay-rows.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

if [[ ! -f "$LIB" ]]; then no "helper $LIB exists"; echo "=== ${pass} passed, ${fail} failed ==="; exit 1; fi
# shellcheck source=scripts/lib/web2-relay-rows.sh
source "$LIB"

EXP=0.0.0.0   # the container wildcard (ci-deploy.sh -e SOLEUR_PROXY_BIND=0.0.0.0)
PEERIP=10.0.1.11
# row <age_s> <line> [host]  — a row as the real query returns it (JSONEachRow, age_s server-computed)
row() { jq -cn --arg age "$1" --arg l "$2" --arg h "${3:-soleur-web-2}" '{age_s: $age, host_name: $h, line: $l}'; }
line() { # line [state] [addr] [port] [wp]
  printf 'relay_probe proxy_state=%s addr=%s port=%s workspaces_populated=%s' "${1:-listening}" "${2:-$EXP}" "${3:-8443}" "${4:-1}"
}
jv() { # jv <label> <want-prefix> <peer-ip or ""> <rows-on-stdin> — a 3rd arg of peer:<ip> selects the PEER judge
  local label="$1" want="$2" pip="$3" out
  cat > "$WORK/rows.jsonl"
  if [[ "$pip" == peer:* ]]; then out="$(wrr_peer_judge "$WORK/rows.jsonl" "${pip#peer:}")"; else out="$(wrr_judge "$WORK/rows.jsonl")"; fi
  # jv runs at the end of a pipeline (a subshell), so it logs; the log is replayed into the counters below.
  if [[ "$out" == "$want"* ]]; then printf 'ok\t%s\n' "$label -> $out" >> "$WORK/jlog"; else printf 'no\t%s\n' "$label: want '$want...', got '$out'" >> "$WORK/jlog"; fi
}
: > "$WORK/jlog"

# --- J: the judge -------------------------------------------------------------------------------------------
{ row 20 "$(line)"; row 80 "$(line)"; row 140 "$(line)"; } | jv "J01 three healthy rows, newest 20 s" "GREEN" ""
{ row 119 "$(line)"; row 179 "$(line)"; } | jv "J02 boundary: newest 119 s, oldest 179 s, two rows" "GREEN" ""
{ row 120 "$(line)"; row 179 "$(line)"; } | jv "J02b boundary: newest exactly 120 s is still fresh" "GREEN" ""
{ row 121 "$(line)"; row 150 "$(line)"; } | jv "J03 newest 121 s -> stale" "RED reason=newest_stale" ""
{ row 300 "$(line)"; row 400 "$(line)"; } | jv "J03b every row older than the window -> too few rows" "RED reason=rows_below_floor" ""
{ row 20 "$(line)"; row 181 "$(line)"; } | jv "J04 a row outside the 180 s window does not count: 1 in-window row" "RED reason=rows_below_floor" ""
{ row 20 "$(line)"; } | jv "J05 a single row -> below the floor of 2" "RED reason=rows_below_floor" ""
: | jv "J06 an EMPTY body is zero rows, never a pass" "RED reason=rows_below_floor" ""
printf '<html>502 Bad Gateway</html>\n' | jv "J07 an HTML body -> unparseable" "RED reason=body_unparseable" ""
printf '{"age_s":"20","host_name":"soleur-web-2","line":"x"\n' | jv "J07b a truncated JSON line -> unparseable" "RED reason=body_unparseable" ""
printf '[1,2]\n' | jv "J07c a non-object row -> unparseable" "RED reason=body_unparseable" ""
for st in disabled no_bind no_allowlist error; do
  { row 20 "$(line listening)"; row 80 "$(line "$st")"; } | jv "J08 one row proxy_state=$st -> refused" "RED reason=proxy_state_not_listening" ""
done
{ row 20 "$(line)"; row 80 "$(line listening 10.0.1.10)"; } | jv "J09 an in-window row binds a host private address (not the container wildcard) -> addr mismatch" "RED reason=addr_mismatch" ""
{ row 20 "$(line listening ::)"; row 80 "$(line listening ::)"; } | jv "J10 addr=:: (the IPv6 wildcard is not the shipped IPv4 bind) -> refused" "RED reason=addr_mismatch" ""
{ row 20 "$(line listening 0.0.0.0)"; row 80 "$(line listening 0.0.0.0)"; } | jv "J10b addr=0.0.0.0 on every row, port 8443 -> GREEN (the shipped in-container bind)" "GREEN" ""
{ row 20 "$(line listening none)"; row 80 "$(line listening none)"; } | jv "J10c addr=none while listening -> refused" "RED reason=addr_mismatch" ""
{ row 20 "$(line listening 0.0.0.0)"; row 80 "$(line listening 10.0.1.11)"; } | jv "J11 one row with a private address among wildcard rows -> refused" "RED reason=addr_mismatch" ""
{ row 20 "$(line listening "$EXP" 8444)"; row 80 "$(line listening "$EXP" 8443)"; } | jv "J12 port 8444 -> refused" "RED reason=port_mismatch" ""
{ row 20 "$(line listening "$EXP" 80)"; row 80 "$(line listening "$EXP" 80)"; } | jv "J12b port 80 -> refused" "RED reason=port_mismatch" ""
{ row 20 "$(line listening "$EXP" 8443 0)"; row 80 "$(line listening "$EXP" 8443 1)"; } | jv "J13 workspaces_populated=0 on one row -> still GREEN (owner ruling 2026-11-06: web-2 holds no workspaces until it serves; the requirement was circular, volume identity rests on the LUKS markers)" "GREEN" ""
{ row 20 "$(line listening "$EXP" 8443 0)"; row 80 "$(line listening "$EXP" 8443 0)"; } | jv "J13b workspaces_populated=0 on every row -> GREEN (the field is recorded, not judged)" "GREEN" ""
{ row 20 "$(line disabled none 0 0)"; row 80 "$(line listening "$EXP" 8443 0)"; } | jv "J13c populated=0 does not rescue a non-listening row -> refused" "RED reason=proxy_state_not_listening" ""
{ row 20 "$(line)"; row 80 "$(line)" "soleur-web-platform"; } | jv "J14 a row from another host is not counted: 1 row" "RED reason=rows_below_floor" ""
# the grammar is the WHOLE line: a prefix, a suffix, an unknown state or a wrong field order is malformed
{ row 20 "$(line)"; row 80 "x$(line)"; } | jv "J15 leading junk -> malformed" "RED reason=row_malformed" ""
{ row 20 "$(line)"; row 80 "$(line) extra=1"; } | jv "J15b trailing junk -> malformed" "RED reason=row_malformed" ""
{ row 20 "$(line)"; row 80 "$(line)x"; } | jv "J15c trailing junk glued to the last token -> malformed" "RED reason=row_malformed" ""
{ row 20 "$(line)"; row 80 "$(line weird)"; } | jv "J15d unknown proxy_state -> malformed" "RED reason=row_malformed" ""
{ row 20 "$(line)"; row 80 "relay_probe addr=$EXP proxy_state=listening port=8443 workspaces_populated=1"; } | jv "J15e reordered fields -> malformed" "RED reason=row_malformed" ""
{ row 20 "$(line)"; row 80 ""; } | jv "J15f an empty extracted line (the SQL found no match) -> malformed" "RED reason=row_malformed" ""
{ row 20 "$(line)"; row 80 "$(line listening "$EXP" 8443 2)"; } | jv "J15g workspaces_populated=2 -> malformed" "RED reason=row_malformed" ""
{ row 20 "$(line)"; jq -cn '{age_s:"abc",host_name:"soleur-web-2",line:"x"}'; } | jv "J16 a non-numeric age -> refused" "RED reason=row_age_malformed" ""
{ row 20 "$(line)"; jq -cn '{age_s:"-3",host_name:"soleur-web-2",line:"x"}'; } | jv "J16b a negative age -> refused" "RED reason=row_age_malformed" ""
{ jq -cn --arg l "$(line)" '{age_s:20,host_name:"soleur-web-2",line:$l}'; jq -cn --arg l "$(line)" '{age_s:80,host_name:"soleur-web-2",line:$l}'; } | jv "J17 bare-number ages are accepted" "GREEN" ""
# --- JP: the peer judge (web-1's relay_peer_probe rows about web-2) ---------------------------------------
prow() { jq -cn --arg age "$1" --arg l "$2" --arg h "${3:-soleur-web-platform}" '{age_s: $age, host_name: $h, line: $l}'; }
pline() { printf 'relay_peer_probe peer=%s %s' "${1:-$PEERIP}" "${2:-result=ok}"; }
prow 100 "$(pline)" | jv "JP01 the only row says result=ok -> GREEN" "GREEN peer_age_s=100 peer=$PEERIP" "peer:$PEERIP"
{ prow 5000 "$(pline "$PEERIP" result=refused)"; prow 100 "$(pline)"; } | jv "JP02 an older refused row is superseded by a newer ok" "GREEN" "peer:$PEERIP"
{ prow 5000 "$(pline)"; prow 100 "$(pline "$PEERIP" result=refused)"; } | jv "JP03 a NEWER refused row beats an older ok: refused" "RED reason=peer_refused" "peer:$PEERIP"
for r in refused timeout tls denied; do
  prow 100 "$(pline "$PEERIP" "result=$r")" | jv "JP04 newest result=$r -> refused" "RED reason=peer_$r" "peer:$PEERIP"
done
prow 100 "$(pline "$PEERIP" skipped=exec_failed)" | jv "JP05 newest is skipped=exec_failed -> refused" "RED reason=peer_skipped" "peer:$PEERIP"
: | jv "JP06 an EMPTY body is no row, never a pass" "RED reason=peer_rows_none" "peer:$PEERIP"
prow 86401 "$(pline)" | jv "JP07 an ok row older than the 24 h lookback does not count" "RED reason=peer_rows_none" "peer:$PEERIP"
prow 86400 "$(pline)" | jv "JP07b an ok row exactly at the lookback edge counts" "GREEN" "peer:$PEERIP"
prow 100 "$(pline "$PEERIP")" soleur-web-2 | jv "JP08 a row from web-2 itself is not web-1's probe" "RED reason=peer_rows_none" "peer:$PEERIP"
prow 100 "$(pline 10.0.1.12)" | jv "JP09 the newest row is about ANOTHER peer -> malformed, never a pass" "RED reason=peer_row_malformed" "peer:$PEERIP"
prow 100 "$(pline) extra=1" | jv "JP10 trailing junk -> malformed" "RED reason=peer_row_malformed" "peer:$PEERIP"
prow 100 "x$(pline)" | jv "JP10b leading junk -> malformed" "RED reason=peer_row_malformed" "peer:$PEERIP"
prow 100 "$(pline "$PEERIP" result=weird)" | jv "JP10c unknown result word -> malformed" "RED reason=peer_row_malformed" "peer:$PEERIP"
prow 100 "" | jv "JP10d an empty extracted line -> malformed" "RED reason=peer_row_malformed" "peer:$PEERIP"
{ prow 100 "$(pline)"; prow 100 "$(pline "$PEERIP" result=denied)"; } | jv "JP11 two rows tied at the newest age, one denied -> refused" "RED reason=peer_denied" "peer:$PEERIP"
printf '<html>502</html>\n' | jv "JP12 an HTML body -> unparseable" "RED reason=body_unparseable" "peer:$PEERIP"
jq -cn '{age_s:"abc",host_name:"soleur-web-platform",line:"x"}' | jv "JP13 a non-numeric age -> refused" "RED reason=peer_row_age_malformed" "peer:$PEERIP"
for bad in "::" "0.0.0.0" "none" "web-2" "10.0.1" "10.0.1.11 " "192.168.1.5" ""; do
  prow 100 "$(pline)" | jv "JP14 peer address '$bad' -> refused" "RED reason=peer_addr_invalid" "peer:$bad"
done
# a full page is possibly truncated: never a pass
for i in $(seq 1 200); do row "$((i % 100))" "$(line)"; done | jv "J19 a 200-row page -> truncated, never a pass" "RED reason=rows_truncated" ""
# the judge never prints a credential or row body: only its closed vocabulary
out="$(printf '%s\n' "$(row 20 "relay_probe SECRET-LOOKING-TEXT")" "$(row 30 "$(line)")" > "$WORK/r"; wrr_judge "$WORK/r")"
if [[ "$out" != *SECRET* ]]; then ok "J20 a malformed row's text is not echoed in the verdict"; else no "J20 verdict echoed row text: $out"; fi

while IFS=$'\t' read -r st msg; do if [[ "$st" == ok ]]; then ok "$msg"; else no "$msg"; fi; done < "$WORK/jlog"
[[ "$(wc -l < "$WORK/jlog")" -ge 65 ]] && ok "J99 the judge fixtures all ran (>= 65 logged)" || no "J99 only $(wc -l < "$WORK/jlog") judge fixtures logged"

# --- Q: the query function ----------------------------------------------------------------------------------
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
url=""; data=""; user=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) data="$2"; shift 2 ;;
    --data-binary) data="$2"; shift 2 ;;
    --config) if [ "$2" = - ]; then cfg="$(cat)"; user="${cfg#user = \"}"; user="${user%%\"*}"; fi; shift 2 ;;
    -u) echo "curl stub: credentials on ARGV (-u)" >&2; exit 64 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
leak="$(env | cut -d= -f1 | grep -E 'TOKEN|SECRET|PASSWORD|KEY|CREDENTIAL|AUTH|DOPPLER' | grep -vxE 'BETTERSTACK_QUERY_PASSWORD' || true)"
if [ -n "$leak" ]; then printf '%s\n' "$leak" >> "$LEAK"; exit 64; fi
case "$url" in "https://fixture-connect.betterstackdata.com?"*) : ;; *) echo "curl stub: REFUSED destination" >&2; exit 64 ;; esac
[ "$user" = fixture-user:fixture-pass ] || { echo "curl stub: REFUSED credentials" >&2; exit 64; }
printf '%s' "$data" | tr '\n' ' ' >> "$SQLLOG"
case "$(cat "$FX/mode" 2>/dev/null)" in 503) printf '{"error":"x"}'; exit 22 ;; timeout) exit 28 ;; esac
case "$data" in *relay_peer_probe*) cat "$FX/peer_rows" ;; *) cat "$FX/rows" ;; esac
exit 0
STUB
chmod +x "$BIN/curl"
FX="$WORK/fx"; mkdir -p "$FX"
q() { # q <label> <want-rc> [ENV=VAL...] — runs wrr_fetch in a clean env, output in $WORK/q.out
  local label="$1" want="$2" rc=0; shift 2
  : > "$WORK/sql"; : > "$WORK/leak"; rm -f "$WORK/q.out"
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$FX" SQLLOG="$WORK/sql" LEAK="$WORK/leak" \
    GH_TOKEN=decoy-gh DOPPLER_TOKEN=decoy-doppler \
    BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user \
    BETTERSTACK_QUERY_PASSWORD=fixture-pass "$@" \
    bash -c 'source "$1"; if [ "${3:-}" = peer ]; then wrr_peer_fetch "$2" "${4:-}"; else wrr_fetch "$2"; fi' _ "$LIB" "$WORK/q.out" "${QMODE:-own}" "${QPEER:-}" >/dev/null 2>"$WORK/q.err" || rc=$?
  if [[ "$rc" == "$want" ]]; then ok "$label (rc=$rc)"; else no "$label: want rc $want got $rc: $(head -c 200 "$WORK/q.err")"; fi
  if [[ -s "$WORK/leak" ]]; then no "$label: a secret-shaped variable reached the query child: $(tr '\n' ' ' < "$WORK/leak")"; fi
}
{ row 20 "$(line)"; row 80 "$(line)"; } > "$FX/rows"; : > "$FX/mode"
q "Q01 a healthy answer is rc 0" 0
if [[ "$(wrr_judge "$WORK/q.out")" == GREEN* ]]; then ok "Q01b the fetched body judges GREEN"; else no "Q01b fetched body did not judge GREEN"; fi
sql="$(cat "$WORK/sql")"
[[ "$sql" == *"= 'soleur-web-2'"* ]] && ok "Q02 the SQL pins host_name = 'soleur-web-2'" || no "Q02 SQL lacks the host pin: $sql"
[[ "$sql" == *"INTERVAL 180 SECOND"* ]] && ok "Q03 the SQL asks for the last 180 s" || no "Q03 SQL lacks the 180 s window: $sql"
[[ "$sql" == *"relay_probe proxy_state="* ]] && ok "Q04 the SQL selects on the relay_probe line prefix" || no "Q04 SQL lacks the prefix: $sql"
[[ "$sql" == *'$BS_TABLE'* || "$sql" == *remote* ]] && ok "Q05 the SQL reads the hot table" || no "Q05 SQL lacks the table: $sql"
printf '503' > "$FX/mode"; q "Q06 a 5xx is a failed read: rc 1, no verdict" 1
printf 'timeout' > "$FX/mode"; q "Q07 a timeout is a failed read: rc 1" 1
: > "$FX/mode"
q "Q08 credentials absent: rc 1" 1 BETTERSTACK_QUERY_PASSWORD=
# --- Q-peer: wrr_peer_fetch -----------------------------------------------------------------------------------
{ prow 100 "$(pline)"; } > "$FX/peer_rows"
QMODE=peer QPEER=$PEERIP q "QP01 a healthy peer answer is rc 0" 0
if [[ "$(wrr_peer_judge "$WORK/q.out" "$PEERIP")" == GREEN* ]]; then ok "QP01b the fetched peer body judges GREEN"; else no "QP01b fetched peer body did not judge GREEN"; fi
sql="$(cat "$WORK/sql")"
[[ "$sql" == *"= 'soleur-web-platform'"* ]] && ok "QP02 the peer SQL pins host_name = 'soleur-web-platform' (web-1)" || no "QP02 peer SQL lacks the host pin: $sql"
[[ "$sql" == *"INTERVAL 86400 SECOND"* ]] && ok "QP03 the peer SQL asks for the last 24 h" || no "QP03 peer SQL lacks the 24 h window: $sql"
[[ "$sql" == *"relay_peer_probe peer=$PEERIP "* ]] && ok "QP04 the peer SQL selects on the state address" || no "QP04 peer SQL lacks the peer address: $sql"
[[ "$sql" == *'$BS_TABLE'* || "$sql" == *remote* ]] && ok "QP05 the peer SQL reads the hot table" || no "QP05 peer SQL lacks the table: $sql"
printf '503' > "$FX/mode"; QMODE=peer QPEER=$PEERIP q "QP06 a peer 5xx is a failed read: rc 1" 1
: > "$FX/mode"
QMODE=peer QPEER="x' OR 1=1 --" q "QP07 a non-IPv4 peer address is refused before any query: rc 1" 1
[[ ! -s "$WORK/sql" ]] && ok "QP07b …and no query was sent" || no "QP07b a query was sent for an invalid peer address"
echo ""
echo "=== web2-relay-rows.test.sh: ${pass} passed, ${fail} failed ==="
_ran=$((pass + fail))
if [ "$_ran" -lt 85 ]; then
  printf 'GUARD FAIL: ran only %d assertion(s) (floor 85) — the suite did not execute fully\n' "$_ran" >&2
  exit 2
fi
[[ "$fail" -eq 0 ]]
