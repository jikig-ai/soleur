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
jv() { # jv <label> <want-prefix> <peer-ip or ""> <rows-on-stdin> — a 3rd arg of peer:<dialer-host>:<ip> selects the PEER judge
  local label="$1" want="$2" pip="$3" out pr
  cat > "$WORK/rows.jsonl"
  if [[ "$pip" == peer:* ]]; then pr="${pip#peer:}"; out="$(wrr_peer_judge "$WORK/rows.jsonl" "${pr%%:*}" "${pr#*:}")"; else out="$(wrr_judge "$WORK/rows.jsonl")"; fi
  # jv runs at the end of a pipeline (a subshell), so it logs; the log is replayed into the counters below.
  if [[ "$out" == "$want"* ]]; then printf 'ok\t%s\n' "$label -> $out" >> "$WORK/jlog"; else printf 'no\t%s\n' "$label: want '$want...', got '$out'" >> "$WORK/jlog"; fi
}
: > "$WORK/jlog"

# --- J: the judge -------------------------------------------------------------------------------------------
{ row 20 "$(line)"; row 80 "$(line)"; row 140 "$(line)"; } | jv "J01 three healthy rows, newest 20 s" "GREEN" ""
{ row 119 "$(line)"; row 179 "$(line)"; } | jv "J02 boundary: newest 119 s, oldest 179 s, two rows" "GREEN" ""
{ row 120 "$(line)"; row 179 "$(line)"; } | jv "J02b boundary: newest exactly 120 s is still fresh" "GREEN" ""
{ row 20 "$(line)"; row 180 "$(line)"; } | jv "J02c boundary: a row at EXACTLY 180 s is inside the window (>= 2 rows -> GREEN; 'a <= win' must not become 'a < win')" "GREEN" ""
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
W1H=soleur-web-platform; W2H=soleur-web-2; W1IP=10.0.1.10
prow() { jq -cn --arg age "$1" --arg l "$2" --arg h "${3:-soleur-web-platform}" '{age_s: $age, host_name: $h, line: $l}'; }
pline() { printf 'relay_peer_probe peer=%s %s' "${1:-$PEERIP}" "${2:-result=ok}"; }
prow 100 "$(pline)" | jv "JP01 the only row says result=ok -> GREEN" "GREEN peer_age_s=100 peer=$PEERIP dir=w1_to_w2" "peer:$W1H:$PEERIP"
{ prow 5000 "$(pline "$PEERIP" result=refused)"; prow 100 "$(pline)"; } | jv "JP02 an older refused row is superseded by a newer ok" "GREEN" "peer:$W1H:$PEERIP"
{ prow 5000 "$(pline)"; prow 100 "$(pline "$PEERIP" result=refused)"; } | jv "JP03 a NEWER refused row beats an older ok: refused" "RED reason=peer_refused" "peer:$W1H:$PEERIP"
for r in refused timeout tls denied; do
  prow 100 "$(pline "$PEERIP" "result=$r")" | jv "JP04 newest result=$r -> refused" "RED reason=peer_$r" "peer:$W1H:$PEERIP"
done
prow 100 "$(pline "$PEERIP" skipped=exec_failed)" | jv "JP05 newest is skipped=exec_failed -> refused" "RED reason=peer_skipped" "peer:$W1H:$PEERIP"
: | jv "JP06 an EMPTY body is no row, never a pass" "RED reason=peer_rows_none" "peer:$W1H:$PEERIP"
prow 86401 "$(pline)" | jv "JP07 an ok row older than the 24 h lookback does not count" "RED reason=peer_rows_none" "peer:$W1H:$PEERIP"
prow 86400 "$(pline)" | jv "JP07b an ok row exactly at the lookback edge counts" "GREEN" "peer:$W1H:$PEERIP"
prow 100 "$(pline "$PEERIP")" soleur-web-2 | jv "JP08 a row from web-2 itself is not web-1's probe" "RED reason=peer_rows_none" "peer:$W1H:$PEERIP"
prow 100 "$(pline 10.0.1.12)" | jv "JP09 the newest row is about ANOTHER peer -> malformed, never a pass" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
prow 100 "$(pline) extra=1" | jv "JP10 trailing junk -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
prow 100 "x$(pline)" | jv "JP10b leading junk -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
prow 100 "$(pline "$PEERIP" result=weird)" | jv "JP10c unknown result word -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
prow 100 "" | jv "JP10d an empty extracted line -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline)"; prow 100 "$(pline "$PEERIP" result=denied)"; } | jv "JP11 two rows tied at the newest age, one denied -> refused" "RED reason=peer_denied" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline "$PEERIP" result=denied)"; prow 100 "$(pline)"; } | jv "JP11b the same tie in the OTHER order (denied first, ok second) -> refused (a first-only or last-only check must red)" "RED reason=peer_denied dir=w1_to_w2" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline) extra=1"; prow 100 "$(pline)"; } | jv "JP11c tied: malformed row first, ok second -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline)"; prow 100 "$(pline) extra=1"; } | jv "JP11d tied: ok first, malformed row second -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline 10.0.1.12)"; prow 100 "$(pline)"; } | jv "JP11e tied: a row about ANOTHER peer first, ok second -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline)"; prow 100 "$(pline 10.0.1.12)"; } | jv "JP11f tied: ok first, a row about ANOTHER peer second -> malformed" "RED reason=peer_row_malformed" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline "$PEERIP" skipped=exec_failed)"; prow 100 "$(pline)"; } | jv "JP11g tied: skipped first, ok second -> refused" "RED reason=peer_skipped" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline)"; prow 100 "$(pline "$PEERIP" skipped=exec_failed)"; } | jv "JP11h tied: ok first, skipped second -> refused" "RED reason=peer_skipped" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline)"; prow 100 "$(pline)"; } | jv "JP11i two tied ok rows -> GREEN (the tie rule refuses only on a bad tied row)" "GREEN peer_age_s=100" "peer:$W1H:$PEERIP"
# A HOT/ARCHIVE overlap returns the same row twice (UNION ALL does not dedupe). Same dt -> same server-computed age_s.
{ prow 100 "$(pline)"; prow 100 "$(pline)"; } | jv "JP11j a hot+archive DUPLICATE of the newest ok row is GREEN (age and verdict identical)" "GREEN peer_age_s=100 peer=$PEERIP dir=w1_to_w2" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline)"; prow 101 "$(pline)"; } | jv "JP11k a duplicate whose age differs by 1 s (skew between arms) is still GREEN at the newer age" "GREEN peer_age_s=100 peer=$PEERIP dir=w1_to_w2" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline)"; prow 100 "$(pline)"; prow 5000 "$(pline)"; prow 5000 "$(pline)"; } | jv "JP11l two duplicated ok pairs (newest, and older) -> GREEN at the newest age" "GREEN peer_age_s=100 peer=$PEERIP dir=w1_to_w2" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline "$PEERIP" result=refused)"; prow 100 "$(pline "$PEERIP" result=refused)"; } | jv "JP11m a duplicated REFUSED newest row is still refused (a duplicate never launders a bad verdict)" "RED reason=peer_refused dir=w1_to_w2" "peer:$W1H:$PEERIP"
{ prow 100 "$(pline "$W1IP")" "$W2H"; prow 100 "$(pline "$W1IP")" "$W2H"; } | jv "JR13 a duplicated web-2 -> web-1 ok row is GREEN under the web-2 dialer" "GREEN peer_age_s=100 peer=$W1IP dir=w2_to_w1" "peer:$W2H:$W1IP"
# the live defect, as rows: only an OLD (archive-only) ok row exists. The judge GREENs it; the SQL (S05) is what must reach it.
prow 20000 "$(pline)" | jv "JP11n an ok row 5.5 h old (archive-only) judges GREEN: the judge has no hot-window assumption" "GREEN peer_age_s=20000 peer=$PEERIP dir=w1_to_w2" "peer:$W1H:$PEERIP"
printf '<html>502</html>\n' | jv "JP12 an HTML body -> unparseable" "RED reason=body_unparseable" "peer:$W1H:$PEERIP"
jq -cn '{age_s:"abc",host_name:"soleur-web-platform",line:"x"}' | jv "JP13 a non-numeric age -> refused" "RED reason=peer_row_age_malformed" "peer:$W1H:$PEERIP"
for bad in "::" "0.0.0.0" "none" "web-2" "10.0.1" "10.0.1.11 " "192.168.1.5" ""; do
  prow 100 "$(pline)" | jv "JP14 peer address '$bad' -> refused" "RED reason=peer_addr_invalid" "peer:$W1H:$bad"
done
# --- JR: the REVERSE direction (web-2 dials web-1; web-2's own deploy journals host_name soleur-web-2) -------
# The owner-recorded gate is 'ok in both directions': existing sessions are owned by web-1, so web-2's relay client
# must reach web-1:8443. The judge is parameterised on the dialing host; each direction has its own distinct label.
prow 100 "$(pline "$W1IP")" "$W2H" | jv "JR01 web-2's own row says peer=web-1 result=ok -> GREEN, labelled w2_to_w1" "GREEN peer_age_s=100 peer=$W1IP dir=w2_to_w1" "peer:$W2H:$W1IP"
prow 100 "$(pline "$W1IP")" "$W1H" | jv "JR02 the same row from WEB-1 does not satisfy the web-2 dialer (direction is the host)" "RED reason=peer_rows_none dir=w2_to_w1" "peer:$W2H:$W1IP"
prow 100 "$(pline "$PEERIP")" "$W2H" | jv "JR03 a web-2 row about web-2's own address is not the w2->w1 proof" "RED reason=peer_row_malformed dir=w2_to_w1" "peer:$W2H:$W1IP"
prow 100 "$(pline "$W1IP" result=refused)" "$W2H" | jv "JR04 web-2 -> web-1 result=refused -> refused, labelled w2_to_w1" "RED reason=peer_refused dir=w2_to_w1" "peer:$W2H:$W1IP"
prow 100 "$(pline "$W1IP" result=denied)" "$W2H" | jv "JR05 web-2 -> web-1 result=denied -> refused" "RED reason=peer_denied dir=w2_to_w1" "peer:$W2H:$W1IP"
prow 100 "$(pline "$W1IP" skipped=exec_failed)" "$W2H" | jv "JR06 web-2 -> web-1 skipped=exec_failed -> refused" "RED reason=peer_skipped dir=w2_to_w1" "peer:$W2H:$W1IP"
: | jv "JR07 no web-2 row at all -> RED rows_none, labelled w2_to_w1 (a missing direction is never GREEN)" "RED reason=peer_rows_none dir=w2_to_w1" "peer:$W2H:$W1IP"
prow 100 "$(pline)" "$W1H" | jv "JR08 a forward ok row alone: the forward judge is GREEN labelled w1_to_w2 (distinct from JR02's reverse verdict)" "GREEN peer_age_s=100 peer=$PEERIP dir=w1_to_w2" "peer:$W1H:$PEERIP"
{ prow 5000 "$(pline "$W1IP")" "$W2H"; prow 100 "$(pline "$W1IP" result=timeout)" "$W2H"; } | jv "JR09 a NEWER web-2 timeout beats an older ok" "RED reason=peer_timeout dir=w2_to_w1" "peer:$W2H:$W1IP"
prow 100 "$(pline "$W1IP")" "$W2H" | jv "JR10 an unknown dialing host is refused, never GREEN" "RED reason=peer_dialer_invalid" "peer:soleur-web-9:$W1IP"
prow 100 "$(pline "$W1IP")" "$W2H" | jv "JR11 an empty dialing host is refused" "RED reason=peer_dialer_invalid" "peer::$W1IP"
prow 90000 "$(pline "$W1IP")" "$W2H" | jv "JR12 a web-2 ok row older than the 24 h lookback does not count" "RED reason=peer_rows_none dir=w2_to_w1" "peer:$W2H:$W1IP"
# a full page is possibly truncated: never a pass
for i in $(seq 1 200); do row "$((i % 100))" "$(line)"; done | jv "J19 a 200-row page -> truncated, never a pass" "RED reason=rows_truncated" ""
# the judge never prints a credential or row body: only its closed vocabulary
out="$(printf '%s\n' "$(row 20 "relay_probe SECRET-LOOKING-TEXT")" "$(row 30 "$(line)")" > "$WORK/r"; wrr_judge "$WORK/r")"
if [[ "$out" != *SECRET* ]]; then ok "J20 a malformed row's text is not echoed in the verdict"; else no "J20 verdict echoed row text: $out"; fi

while IFS=$'\t' read -r st msg; do if [[ "$st" == ok ]]; then ok "$msg"; else no "$msg"; fi; done < "$WORK/jlog"
J_EXPECTED=92   # recomputed from the green run: the exact number of judge fixtures logged
J_LOGGED="$(wc -l < "$WORK/jlog")"
if [[ "$J_LOGGED" -eq "$J_EXPECTED" ]]; then ok "J99 the judge fixtures ran exactly as many times as declared ($J_LOGGED)"; else no "J99 $J_LOGGED judge fixtures logged, $J_EXPECTED declared"; fi

# --- S: the SQL text (S-P2-1: forged-evidence defence) ---------------------------------------------------------
# Both queries filter on STRUCTURED fields, never on the whole raw row: a log line from the host that merely ECHOES a probe
# sentence (a user-influenced message, a debug dump) carries a different SYSLOG_IDENTIFIER / CONTAINER_NAME / message prefix and
# cannot become the newest row. The line is selected FROM the same field the prefix test anchors on. These are the shipped
# alerts' own filters (apps/web-platform/infra/betterstack-logs-alerts.tf relay_* locals). Every guard line is checked as an
# EXACT line of the comment-stripped SQL, and each is mutation-proved on a sandbox copy of the text (control green first, the
# mutant verified to have LANDED against the pristine text, then the guard must go red).
sql_clean() { sed -E 's/[[:space:]]*--.*$//' <<<"$1"; }
sqlg_own() { # sqlg_own <sql> -> 0 iff every own-line guard line is present exactly and no whole-row matcher exists
  local c; c="$(sql_clean "$1")"
  grep -qxF "SELECT dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'host_name') AS host_name, JSONExtractString(raw,'message','msg') AS line" <<<"$c" \
    && grep -qxF "  AND JSONExtractString(raw,'host_name') = 'soleur-web-2'" <<<"$c" \
    && grep -qxF "  AND JSONExtractString(raw,'CONTAINER_NAME') = 'soleur-web-platform'" <<<"$c" \
    && grep -qxF "  AND startsWith(JSONExtractString(raw,'message','msg'), 'relay_probe proxy_state=')" <<<"$c" \
    && grep -qxF 'FROM remote($BS_TABLE)' <<<"$c" \
    && ! grep -qE 'position[(]raw|extract[(]raw' <<<"$c"
}
sqlg_peer() { # sqlg_peer <sql> <dialing-host> <peer-ip>
  local c; c="$(sql_clean "$1")"
  grep -qxF "SELECT dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'host_name') AS host_name, JSONExtractString(raw,'message') AS line" <<<"$c" \
    && grep -qxF "  AND JSONExtractString(raw,'host_name') = '$2'" <<<"$c" \
    && grep -qxF "  AND JSONExtractString(raw,'SYSLOG_IDENTIFIER') = 'ci-deploy'" <<<"$c" \
    && grep -qxF "  AND startsWith(JSONExtractString(raw,'message'), 'relay_peer_probe peer=$3 ')" <<<"$c" \
    && grep -qxF 'FROM (SELECT dt, raw FROM remote($BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)' <<<"$c" \
    && grep -qxF 'ORDER BY dt DESC LIMIT 50' <<<"$c" \
    && ! grep -qE 'position[(]raw|extract[(]raw' <<<"$c"
}
# The peer row is written ONCE per web-1/web-2 deploy (sparse), so it is usually OLDER than the ~40-minute hot window:
# a remote()-only read answers zero rows and the serve evidence step refuses RED reason=peer_rows_none (measured live, run
# 42457219868). sqlg_peer_arms checks each arm of the union on its own, so a mutant names WHICH arm it lost.
sqlg_peer_arms() { # sqlg_peer_arms <sql> -> 0 iff the comment-stripped SQL has the hot arm, the archive arm and its _row_type filter
  local c; c="$(sql_clean "$1")"
  grep -qF 'SELECT dt, raw FROM remote($BS_TABLE)' <<<"$c" \
    && grep -qF 'UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)' <<<"$c"
}
S_OWN="$(wrr_sql)"; S_PEER="$(wrr_peer_sql "$W1H" "$PEERIP")"; S_REV="$(wrr_peer_sql "$W2H" "$W1IP")"
if sqlg_own "$S_OWN"; then ok "S01 control: the own-line SQL carries the structured filters (host_name, CONTAINER_NAME, startsWith on message.msg) and no whole-row matcher"; else no "S01 own-line SQL fails its own guard: $S_OWN"; fi
if sqlg_peer "$S_PEER" "$W1H" "$PEERIP"; then ok "S02 control: the web-1 -> web-2 peer SQL carries SYSLOG_IDENTIFIER = 'ci-deploy' and startsWith on message, and no whole-row matcher"; else no "S02 forward peer SQL fails its own guard: $S_PEER"; fi
if sqlg_peer "$S_REV" "$W2H" "$W1IP"; then ok "S03 control: the web-2 -> web-1 peer SQL passes the same guard under the web-2 dialer"; else no "S03 reverse peer SQL fails its own guard: $S_REV"; fi
if sqlg_peer_arms "$S_PEER" && sqlg_peer_arms "$S_REV"; then ok "S05 control: BOTH peer SQLs read the hot remote(\$BS_TABLE) arm AND the s3Cluster(primary, \$BS_TABLE_S3) archive arm with _row_type = 1"; else no "S05 a peer SQL lacks the hot or the archive arm: $S_PEER"; fi
# the OWN-LINE read is one row a minute over 180 s, far inside the hot window: it stays hot-only and cheap
if [[ "$(sql_clean "$S_OWN")" != *s3Cluster* ]]; then ok "S06 the own-line SQL stays hot-only (180 s window)"; else no "S06 the own-line SQL grew an archive arm"; fi
# a comment cannot stand in for a guard line (comment-stripped before matching)
c_own="$(sed "s|^  AND JSONExtractString(raw,'CONTAINER_NAME') = 'soleur-web-platform'\$|  -- AND JSONExtractString(raw,'CONTAINER_NAME') = 'soleur-web-platform'|" <<<"$S_OWN")"
if [[ "$c_own" != "$S_OWN" ]] && ! sqlg_own "$c_own"; then ok "S04 a COMMENTED-OUT CONTAINER_NAME line does not satisfy the guard"; else no "S04 commented-out guard line accepted (or the edit did not land)"; fi
smut() { # smut <label> <which: own|peer|rev> <sed-expr> — mutate the SQL text, verify the mutation LANDED, require the guard to go red
  local label="$1" which="$2" expr="$3" pristine mutant
  case "$which" in own) pristine="$S_OWN" ;; peer|peerarms) pristine="$S_PEER" ;; rev) pristine="$S_REV" ;; esac
  mutant="$(sed -E "$expr" <<<"$pristine")"
  if [[ "$mutant" == "$pristine" ]]; then no "$label: the mutation did not land (text identical to pristine)"; return; fi
  case "$which" in
    own) sqlg_own "$mutant" && no "$label stayed GREEN: the own-line guard cannot see this defect" || ok "$label -> RED" ;;
    peer) sqlg_peer "$mutant" "$W1H" "$PEERIP" && no "$label stayed GREEN: the peer guard cannot see this defect" || ok "$label -> RED" ;;
    rev) sqlg_peer "$mutant" "$W2H" "$W1IP" && no "$label stayed GREEN: the reverse peer guard cannot see this defect" || ok "$label -> RED" ;;
    # arm-level guard: it must see the defect on its own, not only the whole-text guard
    peerarms) sqlg_peer_arms "$mutant" && no "$label stayed GREEN: the arm guard cannot see this defect" || ok "$label -> RED (arm guard)" ;;
  esac
}
smut "SM01 own: drop the CONTAINER_NAME filter" own "/CONTAINER_NAME/d"
smut "SM02 own: drop the startsWith prefix filter" own "/startsWith[(]/d"
smut "SM03 own: revert the prefix filter to position(raw, ...)" own "s/^  AND startsWith.*\$/  AND position(raw, 'relay_probe proxy_state=') > 0/"
smut "SM04 own: select the line with extract(raw, ...) over the whole row" own "s/JSONExtractString[(]raw,'message','msg'[)] AS line/extract(raw, 'relay_probe [^\"]*') AS line/"
smut "SM05 own: loosen the CONTAINER_NAME equality to a substring test" own "s/CONTAINER_NAME'[)] = 'soleur-web-platform'/CONTAINER_NAME') LIKE '%web%'/"
smut "SM06 own: drop the host_name pin" own "/'host_name') = /d"
smut "SM07 peer: drop the SYSLOG_IDENTIFIER filter" peer "/SYSLOG_IDENTIFIER/d"
smut "SM08 peer: drop the startsWith prefix filter" peer "/startsWith[(]/d"
smut "SM09 peer: revert the prefix filter to position(raw, ...)" peer "s/^  AND startsWith.*\$/  AND position(raw, 'relay_peer_probe peer=$PEERIP ') > 0/"
smut "SM10 peer: select the line with extract(raw, ...) over the whole row" peer "s/JSONExtractString[(]raw,'message'[)] AS line/extract(raw, 'relay_peer_probe peer=[0-9.]+ [a-z_]+=[a-z_]+') AS line/"
smut "SM11 peer: widen the identifier to another unit" peer "s/= 'ci-deploy'/= 'sshd'/"
smut "SM12 peer: drop the peer-address anchor from the prefix" peer "s/peer=$PEERIP '/peer='/"
smut "SM13 reverse: drop the SYSLOG_IDENTIFIER filter" rev "/SYSLOG_IDENTIFIER/d"
smut "SM14 reverse: revert the prefix filter to position(raw, ...)" rev "s/^  AND startsWith.*\$/  AND position(raw, 'relay_peer_probe peer=$W1IP ') > 0/"
# ORDER BY dt DESC is what puts the NEWEST probe row first; LIMIT 50 is the page. UNION ALL may return an overlap twice, so 50
# rows cover >= 25 distinct probes, far more than the judge reads (it reads only the newest age). An ASC order would hide the
# newest row behind the 50 oldest in the 24 h window; a tiny LIMIT could cut a tied newest row off.
smut "SM24 peer: ORDER BY dt ASC (the 50 OLDEST rows, newest hidden)" peer "s/^ORDER BY dt DESC/ORDER BY dt ASC/"
smut "SM25 peer: LIMIT 1 (a tied newest row can be cut off)" peer "s/LIMIT 50\$/LIMIT 1/"
smut "SM26 reverse: ORDER BY dt ASC" rev "s/^ORDER BY dt DESC/ORDER BY dt ASC/"
smut "SM27 reverse: LIMIT 1" rev "s/LIMIT 50\$/LIMIT 1/"
# the own-line read is hot-only on purpose: pin its exact FROM so an archive-only or union form reds
smut "SM28 own: read remote(\$BS_TABLE_S3) instead of the hot table" own "s/^FROM .*\$/FROM remote(\\\$BS_TABLE_S3)/"
smut "SM29 own: archive-only FROM s3Cluster(primary, \$BS_TABLE_S3)" own "s/^FROM .*\$/FROM s3Cluster(primary, \\\$BS_TABLE_S3)/"
smut "SM30 own: a hot+archive union FROM (own line is pinned hot-only)" own "s/^FROM .*\$/FROM (SELECT dt, raw FROM remote(\\\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \\\$BS_TABLE_S3) WHERE _row_type = 1)/"
smut "SM15 peer: drop the archive arm (hot arm only, still wrapped in the subquery)" peer "s/ UNION ALL SELECT dt, raw FROM s3Cluster[(]primary, \\\$BS_TABLE_S3[)] WHERE _row_type = 1//"
smut "SM16 peer: drop _row_type = 1 from the archive arm (every archive row type, incl. non-log rows)" peer "s/ WHERE _row_type = 1[)]/)/"
smut "SM17 peer: hot-only revert of the whole FROM (remote(\$BS_TABLE) alone)" peer "s/^FROM .*\$/FROM remote(\\\$BS_TABLE)/"
smut "SM18 reverse: hot-only revert of the whole FROM" rev "s/^FROM .*\$/FROM remote(\\\$BS_TABLE)/"
smut "SM19 reverse: drop the archive arm" rev "s/ UNION ALL SELECT dt, raw FROM s3Cluster[(]primary, \\\$BS_TABLE_S3[)] WHERE _row_type = 1//"
smut "SM20 peer-arms: drop the archive arm" peerarms "s/ UNION ALL SELECT dt, raw FROM s3Cluster[(]primary, \\\$BS_TABLE_S3[)] WHERE _row_type = 1//"
smut "SM21 peer-arms: drop _row_type = 1" peerarms "s/ WHERE _row_type = 1[)]/)/"
smut "SM22 peer-arms: drop the hot arm (archive only)" peerarms "s/SELECT dt, raw FROM remote[(]\\\$BS_TABLE[)] UNION ALL //"
# the archive arm moved into a COMMENT does not count (comment-stripped before matching)
c_arm="$(sed -E "s/^FROM .*\$/FROM remote(\\\$BS_TABLE) -- UNION ALL SELECT dt, raw FROM s3Cluster(primary, \\\$BS_TABLE_S3) WHERE _row_type = 1/" <<<"$S_PEER")"
if [[ "$c_arm" != "$S_PEER" ]] && ! sqlg_peer "$c_arm" "$W1H" "$PEERIP" && ! sqlg_peer_arms "$c_arm"; then ok "SM23 an archive arm hidden in a trailing COMMENT satisfies neither guard"; else no "SM23 a commented-out archive arm was accepted (or the edit did not land)"; fi

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
    bash -c 'source "$1"; if [ "${3:-}" = peer ]; then wrr_peer_fetch "$2" "${5:-soleur-web-platform}" "${4:-}"; else wrr_fetch "$2"; fi' _ "$LIB" "$WORK/q.out" "${QMODE:-own}" "${QPEER:-}" "${QHOST:-soleur-web-platform}" >/dev/null 2>"$WORK/q.err" || rc=$?
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
if [[ "$(wrr_peer_judge "$WORK/q.out" "$W1H" "$PEERIP")" == GREEN* ]]; then ok "QP01b the fetched peer body judges GREEN"; else no "QP01b fetched peer body did not judge GREEN"; fi
sql="$(cat "$WORK/sql")"
[[ "$sql" == *"= 'soleur-web-platform'"* ]] && ok "QP02 the peer SQL pins host_name = 'soleur-web-platform' (web-1)" || no "QP02 peer SQL lacks the host pin: $sql"
[[ "$sql" == *"INTERVAL 86400 SECOND"* ]] && ok "QP03 the peer SQL asks for the last 24 h" || no "QP03 peer SQL lacks the 24 h window: $sql"
[[ "$sql" == *"relay_peer_probe peer=$PEERIP "* ]] && ok "QP04 the peer SQL selects on the state address" || no "QP04 peer SQL lacks the peer address: $sql"
[[ "$sql" == *'$BS_TABLE'* || "$sql" == *remote* ]] && ok "QP05 the peer SQL reads the hot table" || no "QP05 peer SQL lacks the table: $sql"
# As SENT by the REAL scripts/betterstack-query.sh from the three BETTERSTACK_QUERY_* variables alone (no BS_TABLE /
# BS_TABLE_S3 in the env): both tokens substituted, the archive name derived from the default hot table.
[[ "$sql" == *"remote(t520508_soleur_inngest_vector_prd_3_logs)"* ]] && ok "QP05b the sent peer SQL reads the hot table remote(<default>_logs)" || no "QP05b sent SQL lacks the substituted hot table: $sql"
[[ "$sql" == *"s3Cluster(primary, t520508_soleur_inngest_vector_prd_3_s3) WHERE _row_type = 1"* ]] && ok "QP05c the sent peer SQL reads the ARCHIVE arm s3Cluster(primary, <default>_s3) WHERE _row_type = 1, derived with no BS_TABLE_S3 in the env" || no "QP05c sent SQL lacks the archive arm: $sql"
[[ "$sql" != *'$BS_TABLE'* ]] && ok "QP05d no unsubstituted \$BS_TABLE token reached the wire" || no "QP05d an unsubstituted token reached the wire: $sql"
printf '503' > "$FX/mode"; QMODE=peer QPEER=$PEERIP q "QP06 a peer 5xx is a failed read: rc 1" 1
: > "$FX/mode"
QMODE=peer QPEER="x' OR 1=1 --" q "QP07 a non-IPv4 peer address is refused before any query: rc 1" 1
[[ ! -s "$WORK/sql" ]] && ok "QP07b …and no query was sent" || no "QP07b a query was sent for an invalid peer address"
# reverse direction: the SQL pins the dialing host web-2 (and not web-1) and the web-1 address
printf '%s\n' "$(prow 100 "$(pline "$W1IP")" "$W2H")" > "$FX/peer_rows"
QMODE=peer QPEER=$W1IP QHOST=$W2H q "QP08 the reverse (web-2 dialer) peer answer is rc 0" 0
sql="$(cat "$WORK/sql")"
[[ "$sql" == *"= 'soleur-web-2'"* && "$sql" != *"= 'soleur-web-platform'"* ]] && ok "QP09 the reverse peer SQL pins host_name = 'soleur-web-2' only" || no "QP09 reverse SQL host pin wrong: $sql"
[[ "$sql" == *"relay_peer_probe peer=$W1IP "* ]] && ok "QP10 the reverse peer SQL selects on web-1's address" || no "QP10 reverse SQL lacks web-1's address: $sql"
if [[ "$(wrr_peer_judge "$WORK/q.out" "$W2H" "$W1IP")" == "GREEN peer_age_s=100 peer=$W1IP dir=w2_to_w1" ]]; then ok "QP11 the fetched reverse body judges GREEN under the web-2 dialer"; else no "QP11 reverse fetched body did not judge GREEN"; fi
QMODE=peer QPEER=$W1IP QHOST=soleur-web-9 q "QP12 an unknown dialing host is refused before any query: rc 1" 1
[[ ! -s "$WORK/sql" ]] && ok "QP12b …and no query was sent" || no "QP12b a query was sent for an unknown dialing host"
echo ""
echo "=== web2-relay-rows.test.sh: ${pass} passed, ${fail} failed ==="
_ran=$((pass + fail))
if [ "$_ran" -lt 157 ]; then
  printf 'GUARD FAIL: ran only %d assertion(s) (floor 157) — the suite did not execute fully\n' "$_ran" >&2
  exit 2
fi
if [ "$_ran" -gt 157 ]; then
  printf 'GUARD FAIL: ran %d assertion(s), more than the declared 157 — raise BOTH halves of the floor to the new exact count\n' "$_ran" >&2
  exit 2
fi
[[ "$fail" -eq 0 ]]
