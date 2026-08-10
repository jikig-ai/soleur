#!/usr/bin/env bash
#
# Test suite for scripts/zot-inventory-assert-marker.sh — the round-trip readback gate for
# the #7278 inventory lever.
#
# WHY THIS SCRIPT EXISTS AT ALL, and therefore why it has a suite: the deliverable's pass
# condition must not live in workflow YAML, where no test can reach it. Two of the four
# properties below are ones a YAML-embedded `grep` gets WRONG by construction:
#
#   1. `betterstack-query.sh` returns rows whose `raw` column is DOUBLE-ENCODED JSON. A bare
#      grep for the marker text against those rows matches NOTHING — the quotes are
#      backslash-escaped — so a grep-based gate can never PASS, and its permanent "not yet
#      observed" reads exactly like a genuine absence. The decode arm below is the primary
#      assertion, and the mutation at the end proves it is load-bearing.
#   2. Zero rows from the query is not evidence of anything until the channel is known to be
#      carrying rows at all. `SOLEUR_ZOT_DISK` lands on the same source every 5 minutes, so a
#      15-minute window holds ~3 of them for free. Zero control rows is `channel_dark`, and
#      must NEVER be reported as `marker_absent`.
#
# Run: bash tests/scripts/test-zot-inventory-assert-marker.sh
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/scripts/zot-inventory-assert-marker.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '       %s\n' "$2" >&2
  return 0
}

_skip() {
  if [ "${CI:-}" = "true" ]; then
    printf '%s — and CI=true, so this is a FAILURE: the runner must provide this dependency.\n' "$1" >&2
    exit 1
  fi
  printf '%s\n' "$1" >&2
  exit 0
}
for dep in python3 jq; do
  command -v "$dep" >/dev/null 2>&1 || _skip "test-zot-inventory-assert-marker: SKIP — $dep is not on PATH"
done
[ -f "$GATE" ] || { echo "test-zot-inventory-assert-marker: SETUP FAIL — $GATE does not exist" >&2; exit 2; }

TMP="$(mktemp -d)"
[ -d "$TMP" ] || { echo "test-zot-inventory-assert-marker: SETUP FAIL — mktemp -d produced no directory" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ROWS="$TMP/rows.txt"
ARGV="$TMP/stub-argv.txt"
OUT="$TMP/out.txt"
ERR="$TMP/err.txt"
STUB_RC="$TMP/stub.rc"

# The transport stub. It records the argv it was called with — that is how the window
# discipline (`--no-archive --since 15m`) is asserted against the CALL rather than against a
# comment in the gate's source.
cat > "$TMP/stub.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ARGV"
rc="\$(cat "$STUB_RC" 2>/dev/null || echo 0)"
if [ "\$rc" != "0" ]; then
  echo "betterstack-query.sh: simulated transport failure" >&2
  exit "\$rc"
fi
cat "$ROWS"
STUB
chmod +x "$TMP/stub.sh"
echo 0 > "$STUB_RC"

RUN_ID=17772222
OTHER_RUN_ID=99990000

# Build the row file in the shape betterstack-query.sh actually returns: JSONEachRow lines
# whose `raw` column is itself a JSON DOCUMENT ENCODED AS A STRING. Hand-writing this by
# string concatenation is how a fixture ends up single-encoded and the suite ends up proving
# nothing, so it is produced by a serialiser.
rows_encoded() {  # each argument is a decoded .message value
  python3 - "$ROWS" "$@" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    for i, msg in enumerate(sys.argv[2:]):
        raw = json.dumps({"message": msg})
        f.write(json.dumps({"dt": "2026-08-06 13:0%d:00.000000" % (i % 10), "raw": raw}) + "\n")
PY
}
rows_plaintext() {  # the SAME messages, NOT wrapped — an undecoded fixture
  : > "$ROWS"
  local m
  for m in "$@"; do printf '%s\n' "$m" >> "$ROWS"; done
}

mk_marker() {  # $1 run_id, $2 enumeration_complete
  printf 'SOLEUR_ZOT_INVENTORY run_id=%s commit_sha=abc marker_schema=1 outcome=ok reason=none origin_verdict=answered repos=2 repos_enumerated=2 tags=29 manifests_fetched=45 catalog_errors=0 tag_list_errors=0 manifest_errors=0 referrer_errors=0 link_unfollowed=0 enumeration_complete=%s unique_blobs=266 manifest_referenced_bytes=15867729779 manifest_referenced_gb=14.78 fs_size_gb=59 pcent=100 fs_used_gb=59.00 delta_gb=44.22 disk_sample_age_s=61 boot_id=b1 zot_restarts_at_start=15640 zot_restarts_at_end=15640 sweep_started_at=2026-08-06T13:00:00Z sweep_duration_s=91' "$1" "$2"
}
CONTROL_ROW='SOLEUR_ZOT_DISK pcent=100 fs_size_gb=59 zot_restarts=15640 boot_id=b1'

RC=0
run_gate() {  # $1 = gate path; rest = flags
  local gate="$1"; shift
  : > "$ARGV"
  env BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" \
      ZOT_ASSERT_POLL_INTERVAL_S=0 \
      ZOT_ASSERT_POLL_BUDGET_MULTIPLE=1 \
      "${EXTRA_ENV[@]}" \
      bash "$gate" --run-id "$RUN_ID" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
EXTRA_ENV=()

verdict() { grep -E '^SOLEUR_ZOT_INVENTORY_ASSERT ' "$OUT" | tail -1; }
vfield() { grep -oE "(^| )$1=[^ ]*" <<<"$(verdict)" | tail -1 | cut -d= -f2-; }
expect_v() {  # $1 name, $2 want, $3 label
  local got; got="$(vfield "$1")"
  if [ "$got" = "$2" ]; then pass "$3 ($1=$2)"; else fail "$3: $1 want='$2' got='$got'" "verdict=$(verdict)"; fi
}

echo "== 4.2 — a properly double-encoded marker for THIS run_id, with a live control =="
rows_encoded "$CONTROL_ROW" "$(mk_marker "$RUN_ID" true)" "$CONTROL_ROW" "$CONTROL_ROW"
run_gate "$GATE"
if [ "$RC" -eq 0 ]; then pass "an observed, complete marker exits 0"; else fail "observed marker rc=$RC (want 0)" "$(cat "$ERR")"; fi
expect_v outcome observed "observed"
expect_v reason none "observed"
expect_v run_id "$RUN_ID" "observed"
expect_v marker_rows 1 "observed"
if [ "$(vfield control_rows)" -ge 1 ]; then pass "the free positive control was counted (control_rows=$(vfield control_rows))"
else fail "control_rows=$(vfield control_rows) — the pass was certified without a live channel"; fi

echo "== 4.3 / E2 — the window discipline is asserted against the CALL =="
if grep -qF -- '--no-archive' "$ARGV"; then pass "the query is invoked with --no-archive"
else fail "the query was not invoked with --no-archive" "$(cat "$ARGV")"; fi
if grep -qE -- '--since[[:space:]]+15m' "$ARGV"; then pass "the query is invoked with --since 15m"
else fail "the query was not invoked with --since 15m" "$(cat "$ARGV")"; fi
if grep -qF -- 'SOLEUR_ZOT_DISK' "$ARGV"; then pass "the free positive control is requested in the same query"
else fail "the positive control marker is not in the query" "$(cat "$ARGV")"; fi

echo "== 4.5 / E6 — the poll budget is stated as a MULTIPLE of the measured ingest latency =="
expect_v measured_ingest_latency_s 17 "poll budget"
expect_v poll_budget_multiple 1 "poll budget"
expect_v poll_budget_s 17 "poll budget"
if grep -qE '17' "$GATE" && grep -qiE 'measured' "$GATE"; then
  pass "the 17 s figure is carried in the gate as a measured constant"
else
  fail "the gate does not carry the measured ingest latency"
fi

echo "== 4.7 PRIMARY — a line present with a DIFFERENT run_id must NOT pass =="
rows_encoded "$CONTROL_ROW" "$(mk_marker "$OTHER_RUN_ID" true)" "$CONTROL_ROW"
run_gate "$GATE"
if [ "$RC" -ne 0 ]; then pass "a different run_id does not pass"; else fail "a marker for run_id=$OTHER_RUN_ID certified run_id=$RUN_ID"; fi
expect_v outcome marker_absent "different run_id"
expect_v reason marker_not_observed "different run_id"
expect_v marker_rows 0 "different run_id"
if [ "$(vfield control_rows)" -ge 1 ]; then pass "the absence verdict was made with a LIVE control"
else fail "the absence verdict was made with a dark channel"; fi

echo "== 4.7 — an UNDECODED fixture must FAIL the gate =="
# The same messages, unwrapped. A gate that substring-matches the transport output would
# PASS here; a gate that decodes first cannot, because there is nothing to decode. This is
# what distinguishes "reads the sink's real shape" from "greps whatever it was handed".
rows_plaintext "$CONTROL_ROW" "$(mk_marker "$RUN_ID" true)" "$CONTROL_ROW"
run_gate "$GATE"
if [ "$RC" -ne 0 ]; then pass "an undecoded fixture does not pass"; else fail "the gate passed on an undecoded fixture — it is substring-matching the transport output, not decoding it"; fi
if [ "$(vfield outcome)" = "observed" ]; then fail "the undecoded fixture was reported as observed"; else pass "the undecoded fixture is not reported as observed"; fi

echo "== 4.4 / E3 — zero control rows is channel_dark, NEVER marker_absent =="
rows_encoded "some unrelated log line" "another unrelated line"
run_gate "$GATE"
if [ "$RC" -eq 2 ]; then pass "a dark channel exits 2"; else fail "dark channel rc=$RC (want 2)" "$(verdict)"; fi
expect_v outcome channel_dark "dark channel"
expect_v control_rows 0 "dark channel"
if [ "$(vfield outcome)" = "marker_absent" ]; then
  fail "zero control rows was reported as marker_absent — an unobservable channel was cited as evidence of absence"
else
  pass "zero control rows is never reported as marker_absent"
fi

echo "== 4.4 — a transport that does not answer is unknown(3), not an absence =="
rows_encoded "$CONTROL_ROW"
echo 7 > "$STUB_RC"
run_gate "$GATE"
echo 0 > "$STUB_RC"
if [ "$RC" -eq 3 ]; then pass "a transport failure exits 3"; else fail "transport failure rc=$RC (want 3)" "$(verdict)"; fi
expect_v outcome unknown "transport failure"
expect_v reason transport_did_not_answer "transport failure"

echo "== 4.6 / E5 — H6 attaches to the INGEST POST status, not to a non-observation =="
rows_encoded "$CONTROL_ROW" "$(mk_marker "$RUN_ID" true)"
run_gate "$GATE" --ingest-http-code 401
if [ "$RC" -eq 3 ]; then pass "a rejected ingest POST exits 3 (unknown)"; else fail "ingest rejection rc=$RC (want 3)" "$(verdict)"; fi
expect_v outcome unknown "ingest rejected"
expect_v reason ingest_rejected_http_401 "ingest rejected"
# A marker that the sink refused cannot be readback-verified, so the gate must not spend a
# poll budget pretending otherwise.
if [ ! -s "$ARGV" ]; then pass "no query was issued for a marker the sink rejected"
else fail "the gate polled for a marker whose ingest POST was rejected" "$(cat "$ARGV")"; fi
run_gate "$GATE" --ingest-http-code 202
if [ "$RC" -eq 0 ]; then pass "a 202 ingest code does not block the readback"; else fail "a 202 ingest code blocked the readback (rc=$RC)" "$(verdict)"; fi

echo "== 4.2 — the right run_id with enumeration_complete=false must NOT pass =="
rows_encoded "$CONTROL_ROW" "$(mk_marker "$RUN_ID" false)" "$CONTROL_ROW"
run_gate "$GATE"
if [ "$RC" -ne 0 ]; then pass "an incomplete enumeration does not pass"; else fail "enumeration_complete=false was certified as a pass"; fi
expect_v reason enumeration_incomplete "incomplete enumeration"
# The two counters are deliberately distinct: `run_id_rows` is what was SEEN for this run,
# `marker_rows` is what would PASS. Collapsing them would make "the marker never arrived"
# and "the marker arrived and said the sweep was incomplete" the same output, and those have
# different next actions (chase the channel vs re-dispatch the sweep).
expect_v run_id_rows 1 "incomplete enumeration still reports the row it saw"
expect_v marker_rows 0 "an incomplete row is not counted as a passing observation"

echo "== 4.5 — below the measured floor, a non-observation is unknown, not a verdict =="
rows_encoded "$CONTROL_ROW" "$CONTROL_ROW"
EXTRA_ENV=(ZOT_ASSERT_POLL_BUDGET_S=5)
run_gate "$GATE"
EXTRA_ENV=()
if [ "$RC" -eq 3 ]; then pass "a sub-floor budget yields unknown, not an absence"; else fail "sub-floor budget rc=$RC (want 3)" "$(verdict)"; fi
expect_v outcome unknown "sub-floor budget"
expect_v reason below_measured_ingest_floor "sub-floor budget"

echo "== usage — a non-numeric run_id is refused (E10: the discriminator needs a numeric id) =="
rows_encoded "$CONTROL_ROW"
: > "$ARGV"
env BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$GATE" --run-id 'not-a-number' >"$OUT" 2>"$ERR"; RC=$?
if [ "$RC" -eq 64 ]; then pass "a non-numeric run_id exits 64 (usage)"; else fail "non-numeric run_id rc=$RC (want 64)" "$(cat "$ERR")"; fi
env BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$GATE" >"$OUT" 2>"$ERR"; RC=$?
if [ "$RC" -eq 64 ]; then pass "a missing --run-id exits 64 (usage)"; else fail "missing --run-id rc=$RC (want 64)"; fi

echo "== E10 — the match is PREFIX-anchored, so a quoted echo of the marker cannot satisfy it =="
rows_encoded "$CONTROL_ROW" \
  "webhook echo: the workflow will emit \`$(mk_marker "$RUN_ID" true)\` once dispatched"
run_gate "$GATE"
if [ "$RC" -ne 0 ]; then pass "a quoted echo of the marker text does not satisfy the gate"
else fail "prose quoting the marker was accepted as an observation" "$(verdict)"; fi

# ---------------------------------------------------------------------------------
# MUTATION — the decode step must be load-bearing. Same helper contract as
# apps/web-platform/infra/git-data-emit.test.sh: a mutation that does not land exits
# non-zero rather than reporting a null result as a pass.
# ---------------------------------------------------------------------------------
mutate_sub() {  # <dst-basename> <old-substring> <new-substring>
  python3 - "$GATE" "$TMP/$1" "$2" "$3" <<'PY' || return 1
import sys
src, dst, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src).read()
if old not in s:
    sys.stderr.write("substring not found: %r\n" % old); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  chmod +x "$TMP/$1"
  bash -n "$TMP/$1" 2>/dev/null || { echo "mutant $1 does not parse" >&2; return 1; }
}

echo "== MUTATION — replacing the decode with a bare pass-through must break the pass arm =="
if mutate_sub gate-nodecode "jq -R -r 'fromjson? | .raw // empty' | jq -R -r 'fromjson? | .message // empty'" "cat"; then
  rows_encoded "$CONTROL_ROW" "$(mk_marker "$RUN_ID" true)" "$CONTROL_ROW"
  run_gate "$TMP/gate-nodecode"
  if [ "$RC" -ne 0 ]; then
    pass "the undecoded mutant cannot pass — the decode step is load-bearing, not decoration"
  else
    fail "MUTATION(decode): a bare pass-through still passed, so the decode assertion is vacuous" "$(verdict)"
  fi
else
  fail "MUTATION(decode) did not land — the decode pipeline was not found in the gate"
fi

total=$((passes + fails))
if [ "$total" -lt 38 ]; then
  echo "FAIL: ran only ${total} assertions (<38) — the suite did not execute fully" >&2
  exit 1
fi

echo "test-zot-inventory-assert-marker: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
