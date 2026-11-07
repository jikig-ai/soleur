#!/usr/bin/env bash
# web2-relay-rows.test.sh — offline fixtures for scripts/lib/web2-relay-rows.sh (#12167).
#
# Two halves:
#   J  the PURE judge (wrr_judge <rows.jsonl> <expected_addr>): every refusal has a fixture, and the
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

EXP=10.0.1.11
# row <age_s> <line> [host]  — a row as the real query returns it (JSONEachRow, age_s server-computed)
row() { jq -cn --arg age "$1" --arg l "$2" --arg h "${3:-soleur-web-2}" '{age_s: $age, host_name: $h, line: $l}'; }
line() { # line [state] [addr] [port] [wp]
  printf 'relay_probe proxy_state=%s addr=%s port=%s workspaces_populated=%s' "${1:-listening}" "${2:-$EXP}" "${3:-8443}" "${4:-1}"
}
jv() { # jv <label> <want-prefix> <expected-addr> <rows-on-stdin>
  local label="$1" want="$2" exp="$3" out
  cat > "$WORK/rows.jsonl"
  out="$(wrr_judge "$WORK/rows.jsonl" "$exp")"
  # jv runs at the end of a pipeline (a subshell), so it logs; the log is replayed into the counters below.
  if [[ "$out" == "$want"* ]]; then printf 'ok\t%s\n' "$label -> $out" >> "$WORK/jlog"; else printf 'no\t%s\n' "$label: want '$want...', got '$out'" >> "$WORK/jlog"; fi
}
: > "$WORK/jlog"

# --- J: the judge -------------------------------------------------------------------------------------------
{ row 20 "$(line)"; row 80 "$(line)"; row 140 "$(line)"; } | jv "J01 three healthy rows, newest 20 s" "GREEN" "$EXP"
{ row 119 "$(line)"; row 179 "$(line)"; } | jv "J02 boundary: newest 119 s, oldest 179 s, two rows" "GREEN" "$EXP"
{ row 120 "$(line)"; row 179 "$(line)"; } | jv "J02b boundary: newest exactly 120 s is still fresh" "GREEN" "$EXP"
{ row 121 "$(line)"; row 150 "$(line)"; } | jv "J03 newest 121 s -> stale" "RED reason=newest_stale" "$EXP"
{ row 300 "$(line)"; row 400 "$(line)"; } | jv "J03b every row older than the window -> too few rows" "RED reason=rows_below_floor" "$EXP"
{ row 20 "$(line)"; row 181 "$(line)"; } | jv "J04 a row outside the 180 s window does not count: 1 in-window row" "RED reason=rows_below_floor" "$EXP"
{ row 20 "$(line)"; } | jv "J05 a single row -> below the floor of 2" "RED reason=rows_below_floor" "$EXP"
: | jv "J06 an EMPTY body is zero rows, never a pass" "RED reason=rows_below_floor" "$EXP"
printf '<html>502 Bad Gateway</html>\n' | jv "J07 an HTML body -> unparseable" "RED reason=body_unparseable" "$EXP"
printf '{"age_s":"20","host_name":"soleur-web-2","line":"x"\n' | jv "J07b a truncated JSON line -> unparseable" "RED reason=body_unparseable" "$EXP"
printf '[1,2]\n' | jv "J07c a non-object row -> unparseable" "RED reason=body_unparseable" "$EXP"
for st in disabled no_bind no_allowlist error; do
  { row 20 "$(line listening)"; row 80 "$(line "$st")"; } | jv "J08 one row proxy_state=$st -> refused" "RED reason=proxy_state_not_listening" "$EXP"
done
{ row 20 "$(line)"; row 80 "$(line listening 10.0.1.10)"; } | jv "J09 an in-window row carries web-1's address -> addr mismatch" "RED reason=addr_mismatch" "$EXP"
{ row 20 "$(line listening ::)"; row 80 "$(line listening ::)"; } | jv "J10 addr=:: (wildcard) -> refused" "RED reason=addr_wildcard" "$EXP"
{ row 20 "$(line listening 0.0.0.0)"; row 80 "$(line listening 0.0.0.0)"; } | jv "J10b addr=0.0.0.0 (wildcard) -> refused" "RED reason=addr_wildcard" "$EXP"
{ row 20 "$(line listening none)"; row 80 "$(line listening none)"; } | jv "J10c addr=none while listening -> refused" "RED reason=addr_wildcard" "$EXP"
{ row 20 "$(line listening 10.0.1.12)"; row 80 "$(line listening 10.0.1.12)"; } | jv "J11 addr differs from the state address -> refused" "RED reason=addr_mismatch" "$EXP"
{ row 20 "$(line listening "$EXP" 8444)"; row 80 "$(line listening "$EXP" 8443)"; } | jv "J12 port 8444 -> refused" "RED reason=port_mismatch" "$EXP"
{ row 20 "$(line listening "$EXP" 80)"; row 80 "$(line listening "$EXP" 80)"; } | jv "J12b port 80 -> refused" "RED reason=port_mismatch" "$EXP"
{ row 20 "$(line listening "$EXP" 8443 0)"; row 80 "$(line listening "$EXP" 8443 1)"; } | jv "J13 workspaces_populated=0 on one row -> still GREEN (owner ruling 2026-11-06: web-2 holds no workspaces until it serves; the requirement was circular, volume identity rests on the LUKS markers)" "GREEN" "$EXP"
{ row 20 "$(line listening "$EXP" 8443 0)"; row 80 "$(line listening "$EXP" 8443 0)"; } | jv "J13b workspaces_populated=0 on every row -> GREEN (the field is recorded, not judged)" "GREEN" "$EXP"
{ row 20 "$(line disabled none 0 0)"; row 80 "$(line listening "$EXP" 8443 0)"; } | jv "J13c populated=0 does not rescue a non-listening row -> refused" "RED reason=proxy_state_not_listening" "$EXP"
{ row 20 "$(line)"; row 80 "$(line)" "soleur-web-platform"; } | jv "J14 a row from another host is not counted: 1 row" "RED reason=rows_below_floor" "$EXP"
# the grammar is the WHOLE line: a prefix, a suffix, an unknown state or a wrong field order is malformed
{ row 20 "$(line)"; row 80 "x$(line)"; } | jv "J15 leading junk -> malformed" "RED reason=row_malformed" "$EXP"
{ row 20 "$(line)"; row 80 "$(line) extra=1"; } | jv "J15b trailing junk -> malformed" "RED reason=row_malformed" "$EXP"
{ row 20 "$(line)"; row 80 "$(line)x"; } | jv "J15c trailing junk glued to the last token -> malformed" "RED reason=row_malformed" "$EXP"
{ row 20 "$(line)"; row 80 "$(line weird)"; } | jv "J15d unknown proxy_state -> malformed" "RED reason=row_malformed" "$EXP"
{ row 20 "$(line)"; row 80 "relay_probe addr=$EXP proxy_state=listening port=8443 workspaces_populated=1"; } | jv "J15e reordered fields -> malformed" "RED reason=row_malformed" "$EXP"
{ row 20 "$(line)"; row 80 ""; } | jv "J15f an empty extracted line (the SQL found no match) -> malformed" "RED reason=row_malformed" "$EXP"
{ row 20 "$(line)"; row 80 "$(line listening "$EXP" 8443 2)"; } | jv "J15g workspaces_populated=2 -> malformed" "RED reason=row_malformed" "$EXP"
{ row 20 "$(line)"; jq -cn '{age_s:"abc",host_name:"soleur-web-2",line:"x"}'; } | jv "J16 a non-numeric age -> refused" "RED reason=row_age_malformed" "$EXP"
{ row 20 "$(line)"; jq -cn '{age_s:"-3",host_name:"soleur-web-2",line:"x"}'; } | jv "J16b a negative age -> refused" "RED reason=row_age_malformed" "$EXP"
{ jq -cn --arg l "$(line)" '{age_s:20,host_name:"soleur-web-2",line:$l}'; jq -cn --arg l "$(line)" '{age_s:80,host_name:"soleur-web-2",line:$l}'; } | jv "J17 bare-number ages are accepted" "GREEN" "$EXP"
# the expected address must itself be a usable IPv4, never empty or a wildcard
for bad in "" "::" "0.0.0.0" "none" "web-2" "10.0.1" "10.0.1.11 "; do
  { row 20 "$(line)"; row 80 "$(line)"; } | jv "J18 expected address '$bad' -> refused" "RED reason=expected_addr_invalid" "$bad"
done
# a full page is possibly truncated: never a pass
for i in $(seq 1 200); do row "$((i % 100))" "$(line)"; done | jv "J19 a 200-row page -> truncated, never a pass" "RED reason=rows_truncated" "$EXP"
# the judge never prints a credential or row body: only its closed vocabulary
out="$(printf '%s\n' "$(row 20 "relay_probe SECRET-LOOKING-TEXT")" "$(row 30 "$(line)")" > "$WORK/r"; wrr_judge "$WORK/r" "$EXP")"
if [[ "$out" != *SECRET* ]]; then ok "J20 a malformed row's text is not echoed in the verdict"; else no "J20 verdict echoed row text: $out"; fi

while IFS=$'\t' read -r st msg; do if [[ "$st" == ok ]]; then ok "$msg"; else no "$msg"; fi; done < "$WORK/jlog"
[[ "$(wc -l < "$WORK/jlog")" -ge 42 ]] && ok "J99 the judge fixtures all ran (>= 42 logged)" || no "J99 only $(wc -l < "$WORK/jlog") judge fixtures logged"

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
cat "$FX/rows"
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
    bash -c 'source "$1"; wrr_fetch "$2"' _ "$LIB" "$WORK/q.out" >/dev/null 2>"$WORK/q.err" || rc=$?
  if [[ "$rc" == "$want" ]]; then ok "$label (rc=$rc)"; else no "$label: want rc $want got $rc: $(head -c 200 "$WORK/q.err")"; fi
  if [[ -s "$WORK/leak" ]]; then no "$label: a secret-shaped variable reached the query child: $(tr '\n' ' ' < "$WORK/leak")"; fi
}
{ row 20 "$(line)"; row 80 "$(line)"; } > "$FX/rows"; : > "$FX/mode"
q "Q01 a healthy answer is rc 0" 0
if [[ "$(wrr_judge "$WORK/q.out" "$EXP")" == GREEN* ]]; then ok "Q01b the fetched body judges GREEN"; else no "Q01b fetched body did not judge GREEN"; fi
sql="$(cat "$WORK/sql")"
[[ "$sql" == *"= 'soleur-web-2'"* ]] && ok "Q02 the SQL pins host_name = 'soleur-web-2'" || no "Q02 SQL lacks the host pin: $sql"
[[ "$sql" == *"INTERVAL 180 SECOND"* ]] && ok "Q03 the SQL asks for the last 180 s" || no "Q03 SQL lacks the 180 s window: $sql"
[[ "$sql" == *"relay_probe proxy_state="* ]] && ok "Q04 the SQL selects on the relay_probe line prefix" || no "Q04 SQL lacks the prefix: $sql"
[[ "$sql" == *'$BS_TABLE'* || "$sql" == *remote* ]] && ok "Q05 the SQL reads the hot table" || no "Q05 SQL lacks the table: $sql"
printf '503' > "$FX/mode"; q "Q06 a 5xx is a failed read: rc 1, no verdict" 1
printf 'timeout' > "$FX/mode"; q "Q07 a timeout is a failed read: rc 1" 1
: > "$FX/mode"
q "Q08 credentials absent: rc 1" 1 BETTERSTACK_QUERY_PASSWORD=
echo ""
echo "=== web2-relay-rows.test.sh: ${pass} passed, ${fail} failed ==="
MIN=50
if [[ $((pass + fail)) -lt "$MIN" ]]; then echo "GUARD FAIL: ran $((pass + fail)) assertions, expected >= $MIN" >&2; exit 2; fi
[[ "$fail" -eq 0 ]]
