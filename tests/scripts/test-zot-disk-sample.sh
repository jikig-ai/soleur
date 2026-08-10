#!/usr/bin/env bash
# Suite for scripts/zot-disk-sample.sh (#7278).
#
# This logic previously lived TWICE inside registry-zot-inventory.yml as workflow `run:` bodies,
# where the guard suite could assert its SHAPE (jobs, if:, with:) but never EXECUTE it. So none
# of the behaviour below — the envelope anchor, the double decode, the four-way exit taxonomy —
# had a single assertion against it. Extracting it is what makes these tests possible.
#
# The query is stubbed through ZOT_DISK_SAMPLE_QUERY_CMD. The stub emits rows verbatim and
# derives NOTHING from what the SUT is being asked to prove — it supplies stimulus only, so a
# verdict the SUT computes cannot be smuggled in from the fixture.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="${ROOT}/scripts/zot-disk-sample.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  ok   $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL $1"; [[ -n "${2:-}" ]] && echo "       $2"; FAIL=$((FAIL + 1)); }

# A real Better Stack row: `raw` is DOUBLE-encoded JSON whose inner .message is the marker line.
mk_row() {  # $1 marker line, $2 dt
  # COMPACT separators are load-bearing. The envelope anchor matches the literal
  # `"raw":"{\"message\":\"SOLEUR_ZOT_DISK ` with no spaces, which is what the ingest actually
  # stores; json.dumps' default `": "` would build a row no production emission ever produces
  # and the anchor would correctly refuse it — a fixture testing its own shape, not the SUT.
  python3 -c '
import json,sys
S = (",", ":")
inner = json.dumps({"message": sys.argv[1]}, separators=S)
print(json.dumps({"raw": inner, "dt": sys.argv[2]}, separators=S))
' "$1" "$2"
}

# $1 = file of rows to emit, $2 = exit code for the stub
mk_stub() {
  cat > "$TMP/stub.sh" <<EOF
#!/usr/bin/env bash
cat "$1"
exit ${2:-0}
EOF
  chmod +x "$TMP/stub.sh"
}

run_sut() {
  OUT="$(ZOT_DISK_SAMPLE_QUERY_CMD="$TMP/stub.sh" bash "$SUT" 2>"$TMP/err")"
  RC=$?
}

fld() { printf '%s\n' "$OUT" | awk -F= -v k="$1" '$1==k {print $2; exit}'; }

GOOD='SOLEUR_ZOT_DISK fs_size_gb=59 pcent=100 boot_id=6f1b2c3d zot_restarts=15640 zot_last_err=some text here'

echo "== 1 — the happy path decodes every field =="
mk_row "$GOOD" "2026-08-09 12:00:00.000 UTC" > "$TMP/rows"
mk_stub "$TMP/rows" 0
run_sut
[[ "$RC" -eq 0 ]] && pass "a decodable emission exits 0" || fail "want rc 0 got $RC" "$(cat "$TMP/err")"
[[ "$(fld fs_size_gb)"   == "59"       ]] && pass "fs_size_gb"   || fail "fs_size_gb='$(fld fs_size_gb)'"
[[ "$(fld pcent)"        == "100"      ]] && pass "pcent"        || fail "pcent='$(fld pcent)'"
[[ "$(fld boot_id)"      == "6f1b2c3d" ]] && pass "boot_id"      || fail "boot_id='$(fld boot_id)'"
[[ "$(fld zot_restarts)" == "15640"    ]] && pass "zot_restarts" || fail "zot_restarts='$(fld zot_restarts)'"
# zot_last_err carries spaces and is LAST; every field ahead of it must survive the split.
[[ "$(fld fs_size_gb)" == "59" && "$(fld zot_restarts)" == "15640" ]] \
  && pass "a trailing space-bearing field does not corrupt the fields ahead of it" \
  || fail "the whitespace split was corrupted by zot_last_err"

echo "== 2 — the exit taxonomy distinguishes could-not-measure from measured-absent =="
mk_stub "$TMP/rows" 7
run_sut
[[ "$RC" -eq 2 ]] && pass "a query transport failure is rc 2, never 'absent'" || fail "want rc 2 got $RC"
grep -q 'NOT evidence' "$TMP/err" && pass "the transport failure says it is not evidence of absence" \
  || fail "the transport message does not distinguish itself from a measured absence"

: > "$TMP/empty"; mk_stub "$TMP/empty" 0
run_sut
[[ "$RC" -eq 3 ]] && pass "an answered query with no matching row is rc 3 (measured absence)" || fail "want rc 3 got $RC"

echo "== 3 — the envelope anchor rejects an echo of the marker NAME =="
# A GitHub webhook payload quoting the marker name. Contaminated exactly this query before
# (2026-07-15, sibling SOLEUR_PRIVATE_NIC stream: 3 rows returned, 0 of them emissions).
python3 -c '
import json
print(json.dumps({"raw": json.dumps({"PRIORITY":"6","MESSAGE":"webhook mentioning SOLEUR_ZOT_DISK "}), "dt":"2026-08-09 12:00:00.000 UTC"}))' > "$TMP/rows_echo"
mk_stub "$TMP/rows_echo" 0
run_sut
[[ "$RC" -eq 3 ]] && pass "a non-emission row quoting the marker name does not satisfy the anchor" \
  || fail "an echo of the marker name was read as an emission (rc=$RC)"

echo "== 4 — a mixed source does not abort the decode =="
# The two copies this replaced used `jq -r '.raw | fromjson | .message'` with no -R and no
# fromjson?, so ONE non-JSON row aborted the whole pipeline. The newest emission must still win.
{ printf 'this line is not JSON at all\n'
  mk_row "$GOOD" "2026-08-09 12:00:00.000 UTC"; } > "$TMP/rows_mixed"
mk_stub "$TMP/rows_mixed" 0
run_sut
[[ "$RC" -eq 0 ]] && pass "a non-JSON row alongside a real emission does not abort the decode" \
  || fail "a mixed source aborted the decode (rc=$RC)" "$(cat "$TMP/err")"
[[ "$(fld pcent)" == "100" ]] && pass "the emission's fields survive a mixed source" || fail "pcent='$(fld pcent)'"

echo "== 5 — the NEWEST row wins =="
{ mk_row 'SOLEUR_ZOT_DISK fs_size_gb=59 pcent=10 boot_id=old zot_restarts=1' "2026-08-09 11:00:00.000 UTC"
  mk_row 'SOLEUR_ZOT_DISK fs_size_gb=59 pcent=100 boot_id=new zot_restarts=99' "2026-08-09 12:00:00.000 UTC"; } > "$TMP/rows_two"
mk_stub "$TMP/rows_two" 0
run_sut
[[ "$(fld boot_id)" == "new" && "$(fld zot_restarts)" == "99" ]] \
  && pass "rows arrive oldest-first and the newest is selected" \
  || fail "selected boot_id='$(fld boot_id)' restarts='$(fld zot_restarts)'"

echo "== 6 — an undecodable payload is its own class, not 'absent' =="
python3 -c '
import json
print(json.dumps({"raw": "{not valid json", "dt": "2026-08-09 12:00:00.000 UTC"}))' > "$TMP/rows_bad"
# Force the envelope to match while leaving the payload undecodable.
sed -i 's/{not valid json/{\\"message\\":\\"SOLEUR_ZOT_DISK /' "$TMP/rows_bad" 2>/dev/null || true
mk_stub "$TMP/rows_bad" 0
run_sut
[[ "$RC" -eq 3 || "$RC" -eq 4 ]] \
  && pass "an undecodable row exits 3 or 4, never 0 with empty fields (rc=$RC)" \
  || fail "an undecodable row exited $RC"

echo "== 7 — every declared key is present even when the marker omitted it =="
mk_row 'SOLEUR_ZOT_DISK fs_size_gb=59' "2026-08-09 12:00:00.000 UTC" > "$TMP/rows_partial"
mk_stub "$TMP/rows_partial" 0
run_sut
missing=0
for k in fs_size_gb pcent boot_id zot_restarts sample_at sample_age_s; do
  printf '%s\n' "$OUT" | grep -qE "^${k}=" || missing=$((missing + 1))
done
[[ "$missing" -eq 0 ]] \
  && pass "a field the marker omitted is printed EMPTY, so a fixed-key consumer cannot skip it" \
  || fail "$missing declared key(s) were omitted entirely"

echo ""
echo "test-zot-disk-sample: $PASS passed, $FAIL failed ($((PASS + FAIL)) assertions)"

# ANTI-VACUITY FLOOR — a suite whose assertions were removed exits 0 on `FAIL -eq 0` alone,
# which is indistinguishable from a pass. A floor, never an equality.
MIN_ASSERTIONS=15
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  echo "FAIL: only $((PASS + FAIL)) assertions ran, below the floor of ${MIN_ASSERTIONS} — treat as UN-RUN."
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
