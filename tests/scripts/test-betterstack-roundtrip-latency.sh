#!/usr/bin/env bash
# (#7855) Unit tests for scripts/followthroughs/betterstack-roundtrip-latency-7855.sh.
#
# The probe under test is the only instrument in this repo that can distinguish an
# ACKNOWLEDGEMENT from STORAGE. Its failure mode is not "wrong answer" but "confident answer" —
# a verdict of STORED derived from the POST status alone would reproduce, in the fix, exactly
# the defect #7855 exists to remove.
#
# cq-test-fixtures-synthesized-only: every response below is synthesized; no live capture.

set -uo pipefail
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
SUT="${ROOT}/scripts/followthroughs/betterstack-roundtrip-latency-7855.sh"

TMP="$(mktemp -d -t bsrt.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0; fails=0; cases=0
FAILURES=()
pass() { passes=$((passes + 1)); cases=$((cases + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  FAILURES+=("$1"); fails=$((fails + 1)); cases=$((cases + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

printf '\n=== betterstack-roundtrip-latency (#7855) ===\n\n'

# ACCOUNTING CONTROL. A suite whose only merge signal is `fails -eq 0` is defenceless against
# its own fail() being neutered — measured on the sibling probe suite, where swapping one token
# left it reporting all-green with real defects injected.
_cp=$passes; _cf=$fails
pass "accounting-control: pass() increments"
fail "accounting-control: fail() increments (EXPECTED, retracted below)"
if [[ "$passes" -eq $((_cp + 1)) && "$fails" -eq $((_cf + 1)) ]]; then
  # Retract from `cases` as well as `fails`: the control's deliberate failure is not a case the
  # suite ran on the SUT, and leaving it counted breaks `passes + fails == cases` (ADR-193 pt 3).
  fails=$((fails - 1)); cases=$((cases - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
  printf '  ok   accounting-control: counters are independent (control failure retracted)\n'
else
  printf '  [FATAL] accounting control did not behave — this suite cannot certify anything.\n' >&2
  exit 2
fi

[[ -x "$SUT" ]] || { printf '  [FATAL] SUT not executable at %s\n' "$SUT" >&2; exit 2; }

# ── Stubs ────────────────────────────────────────────────────────────────────────────────────
# The curl stub VALIDATES ARGV and exits 64 on a missing required flag, so the suite can detect
# the probe sending the WRONG request rather than merely getting an answer. A stub that answers
# identically regardless of argv puts the fixture seam above the code under test.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/curl" <<'CURL'
#!/usr/bin/env bash
argv="$*"
prev=""
[[ "$argv" == *"Authorization: Bearer"* ]] || { echo "stub-curl: no Authorization header" >&2; exit 64; }
[[ "$argv" == *"--proto =https"* ]] || { echo "stub-curl: --proto '=https' missing" >&2; exit 64; }
[[ "$argv" == *"%{http_code}"* ]] || { echo "stub-curl: -w %{http_code} missing" >&2; exit 64; }
# A redirect-following probe would forward the bearer credential off-vendor.
if [[ "$argv" == *" -L "* || "$argv" == *" --location "* ]]; then
  echo "stub-curl: probe follows redirects" >&2; exit 65
fi
# RULE 1: the marker must carry no host_name key. Asserted at the WIRE, from the consumer's
# side, so a payload builder that grows the field is caught even if the source grep is edited.
if [[ "$argv" == *'host_name'* ]]; then
  echo "stub-curl: payload carries a host_name key — it would satisfy a foreign-host control" >&2
  exit 66
fi
# Record what was actually POSTed, so the query stub can answer only for a marker that was
# really written. Without this the suite asserts a read, not a round trip.
for a in "$@"; do
  case "$prev" in --data-raw) printf '%s' "$a" >> "${STUB_WROTE_FILE:-/dev/null}" ;; esac
  prev="$a"
done
printf '%s' "${STUB_HTTP_CODE:-202}"
CURL
chmod +x "$BIN/curl"

# The query stub dispatches on SHAPE: the readback carries the marker in a LIKE clause, the
# control read is the flag form. Keying on shape rather than call ordinal means a reordering
# cannot make a broken probe look correct.
QSTUB="$TMP/bs-query.sh"
cat > "$QSTUB" <<'QS'
#!/usr/bin/env bash
if [[ "${1:-}" == --* ]]; then
  if [[ "${BS_TABLE:-}" != "${STUB_EXPECT_CONTROL_TABLE:-}" ]]; then
    echo "stub: control read queried BS_TABLE=${BS_TABLE:-<unset>}, expected ${STUB_EXPECT_CONTROL_TABLE:-<unset>}" >&2
    exit 9
  fi
  case "${STUB_CONTROL:-live}" in
    live) printf '{"dt":"2026-09-04 12:00:00","raw":"{}"}\n'; exit 0 ;;
    dark) exit 0 ;;
    fail) echo "control read failed" >&2; exit 7 ;;
  esac
fi
# The marker is extracted from the LIKE clause the probe built, so the stub answers the
# question actually asked. A hardcoded marker models a warehouse returning a DIFFERENT run's
# row -- which the probe is right to reject, making every stored arm fail for a fixture reason.
sql="${1:-}"
# TABLE-AWARE (A2). The readback must query the TARGET table and the control read the CONTROL
# table; a stub that answers regardless of $BS_TABLE cannot see the two being swapped, which is
# Rule 2 -- the invariant scripts/lib/betterstack-sources.sh exists to make derivable.
if [[ "${BS_TABLE:-}" != "${STUB_EXPECT_TABLE:-}" ]]; then
  echo "stub: readback queried BS_TABLE=${BS_TABLE:-<unset>}, expected ${STUB_EXPECT_TABLE:-<unset>}" >&2
  exit 9
fi
marker="$(printf '%s' "$sql" | sed -n "s/.*LIKE '%\\(SOLEUR_BS_ROUNDTRIP_[^%']*\\)%'.*/\\1/p")"
# WRITE-AWARE (A1). Answer only for a marker that was actually POSTed. A stub that echoes back
# whatever the query asked for makes the round trip untestable by construction.
# NO `-s` GUARD. An earlier revision skipped this check when the write ledger was EMPTY, which
# is exactly backwards: an empty ledger means NOTHING was posted, so the readback must find
# nothing. With the `-s` in place, deleting `--data-raw` from the POST left the suite GREEN --
# a fail-open in the very guard added to make the round trip assertable. Caught by mutation.
if [[ -n "$marker" ]]; then
  grep -qF "$marker" "${STUB_WROTE_FILE:-/dev/null}" 2>/dev/null \
    || { echo "stub: marker was never written — returning no rows" >&2; exit 0; }
fi
row() { python3 -c 'import json,sys
inner = json.dumps({"message": sys.argv[1], "source": "betterstack-roundtrip-latency-7855"})
print(json.dumps({"dt":"2026-09-04 12:00:05","ingest_time":"2026-09-04 12:00:22","raw":inner}))' "$1"; }
case "${STUB_READBACK:-empty}" in
  empty) exit 0 ;;
  fail)  echo "readback failed" >&2; exit 7 ;;
  one)   [[ -n "$marker" ]] || { echo "stub: no marker in SQL" >&2; exit 9; }; row "$marker"; exit 0 ;;
  two)   [[ -n "$marker" ]] || { echo "stub: no marker in SQL" >&2; exit 9; }; row "$marker"; row "$marker"; exit 0 ;;
  other) row "SOLEUR_BS_ROUNDTRIP_7855_SOMEONE_ELSES_RUN"; exit 0 ;;
  # HTTP 200 CARRYING A CLICKHOUSE ERROR. `curl --fail-with-body` reports rc 0 for this, so a
  # readback gate keyed on the rc alone consumes it as a result set. Modelled as the vendor
  # actually delivers it: a BARE line, outside the JSONEachRow stream, on a successful exit.
  exception) echo "Code: 241. DB::Exception: Memory limit (for query) exceeded: would use 9.31 GiB. (MEMORY_LIMIT_EXCEEDED)"; exit 0 ;;
  # A ROW THIS RUN'S MARKER MATCHED, WHOSE `raw` IS NOT A JSON DOCUMENT. The stored schema for
  # this source is INFERRED (`http` platform, verified against a `vector`-platform table), so
  # this is the shape a schema mismatch actually takes: the SQL `LIKE` prefilter matches, the
  # jq field anchor does not resolve.
  undecodable) [[ -n "$marker" ]] || { echo "stub: no marker in SQL" >&2; exit 9; }
             python3 -c 'import json,sys
print(json.dumps({"dt":"2026-09-04 12:00:05","ingest_time":"2026-09-04 12:00:22",
                  "raw":"message=" + sys.argv[1] + " source=betterstack-roundtrip-latency-7855"}))' "$marker"
             exit 0 ;;
esac
QS
chmod +x "$QSTUB"

run_rt() {  # env overrides come from the caller
  : > "$TMP/wrote.txt"
  PATH="$BIN:$PATH" \
  STUB_WROTE_FILE="$TMP/wrote.txt" \
  STUB_EXPECT_TABLE="t520508_soleur_git_data_prd_logs" \
  STUB_EXPECT_CONTROL_TABLE="t520508_soleur_inngest_vector_prd_3_logs" \
  BETTERSTACK_QUERY_SH="$QSTUB" \
  GIT_DATA_BETTERSTACK_LOGS_TOKEN="${TOKEN_OVERRIDE-synthetic-token-for-tests}" \
  BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
  BETTERSTACK_ROUNDTRIP_POLL_S="${POLL_OVERRIDE:-1}" \
  BETTERSTACK_ROUNDTRIP_DEADLINE_S="${DEADLINE_OVERRIDE:-18}" \
    bash "$SUT" 2>&1
}

assert_rt() {  # $1=name $2=expected-verdict $3=expected-rc
  local name="$1" want="$2" want_rc="$3" got rc=0
  got="$(run_rt)" || rc=$?
  # EXACT token, not a substring: `*"$want"*` accepted ROUNDTRIP_DARK_MAYBE for
  # ROUNDTRIP_DARK, so any suffix on a verdict token passed.
  if [[ "$got" == *"verdict=${want} "* && "$rc" == "$want_rc" ]]; then
    pass "$name → $want (rc=$rc)"
  else
    fail "$name → expected '$want' rc=$want_rc" "got: $got (rc=$rc)"
  fi
}

echo "--- GUARD 2: no acknowledgement produces a storage verdict ---"

# ROW 2 — the whole thesis. A 202 with an empty readback must never read as stored.
STUB_HTTP_CODE=202 STUB_READBACK=empty STUB_CONTROL=live DEADLINE_OVERRIDE=18 \
  assert_rt "202 + empty readback + LIVE control → the vendor acknowledged a write it did not store" \
            "ROUNDTRIP_NOT_STORED" 1

# ROW 2a (#7855, found at ship) — THE SAME DOOR P1-B CAME THROUGH.
# `_read_ever_answered` existed to stop a readback that never ran from becoming a vendor
# accusation, and it keyed on the transport rc alone. An HTTP 200 carrying a ClickHouse
# exception is rc 0, so it set the flag, the marker was of course absent, the LIVE control
# decided, and this emitted ROUNDTRIP_NOT_STORED — exit 1, published to a public tracker — off
# a query that never ran. MUTATION that must drive this red: revert the gate to
# `if [[ "$_read_rc" -eq 0 ]]; then _read_ever_answered=1`, i.e. drop the
# `bs_absence_response_is_answer` call. Measured: without the fix this arm returns
# ROUNDTRIP_NOT_STORED rc=1.
STUB_HTTP_CODE=202 STUB_READBACK=exception STUB_CONTROL=live DEADLINE_OVERRIDE=18 \
  assert_rt "202 + a readback answering HTTP-200-with-a-ClickHouse-error + LIVE control → unknown, never an accusation" \
            "ROUNDTRIP_UNKNOWN" 3

# ROW 2b (#7855, found at ship) — AN UNDECODED ROW IS NOT A MISSING ROW.
# The `raw LIKE '%marker%'` prefilter matched, so the row is ours; the jq anchor did not resolve
# it, because this source's stored schema is inferred rather than verified. Before the fix
# `_observed` stayed empty and control reached the LIVE arm, publishing NOT_STORED about a row
# we had just read back. MUTATION: delete the `_rows_for_marker` arm → ROUNDTRIP_NOT_STORED rc=1.
STUB_HTTP_CODE=202 STUB_READBACK=undecodable STUB_CONTROL=live DEADLINE_OVERRIDE=18 \
  assert_rt "202 + a marker-matching row whose raw does not decode + LIVE control → unknown (schema), never an accusation" \
            "ROUNDTRIP_UNKNOWN" 3

# The marker actually coming back is the only path to a stored verdict.
STUB_HTTP_CODE=202 STUB_READBACK=one STUB_CONTROL=live \
  assert_rt "a marker read back out of the warehouse → stored" "ROUNDTRIP_STORED" 0

# H2 — must-PASS NON-CANONICAL: two marker rows. The contract is at-least-one, not exactly-one,
# so a matcher written as an equality would reject a legitimate duplicate delivery.
STUB_HTTP_CODE=202 STUB_READBACK=two STUB_CONTROL=live \
  assert_rt "TWO marker rows still read as stored (at-least-one, not exactly-one)" "ROUNDTRIP_STORED" 0

# H1 — a stored verdict needs BOTH legs. A readback that returns a row while the POST failed
# must not report stored: the row cannot be this run's.
STUB_HTTP_CODE=500 STUB_READBACK=one STUB_CONTROL=live \
  assert_rt "a row present but the POST refused → not a stored verdict" "ROUNDTRIP_UNKNOWN" 3

# A row from a DIFFERENT run must not satisfy this one. The marker is unique per invocation
# precisely so a stale row cannot make the probe report STORED forever after the first success --
# the readback anchors on THIS run's marker, not on the marker family.
STUB_HTTP_CODE=202 STUB_READBACK=other STUB_CONTROL=live DEADLINE_OVERRIDE=18 \
  assert_rt "another run's marker does NOT satisfy this run's readback" "ROUNDTRIP_NOT_STORED" 1

# ROW 6 — NOT_STORED and DARK carry different exit codes because their remedies differ: one is a
# vendor data-loss finding, the other is "wait for #7811". The sweeper collapses every non-0/1
# code, so the stdout token is what separates DARK from UNKNOWN.
STUB_HTTP_CODE=202 STUB_READBACK=empty STUB_CONTROL=dark DEADLINE_OVERRIDE=18 \
  assert_rt "empty readback + DARK control → not our finding, retry" "ROUNDTRIP_DARK" 2
STUB_HTTP_CODE=202 STUB_READBACK=empty STUB_CONTROL=fail DEADLINE_OVERRIDE=18 \
  assert_rt "empty readback + failed control → nothing established" "ROUNDTRIP_UNKNOWN" 3

# THE ARM THAT WAS MISSING, and its absence is why the defect shipped. The stub has had a `fail`
# readback mode from the start; no case ever paired it with a LIVE control — which is exactly the
# combination that produced a false vendor accusation. A readback that NEVER answered says nothing
# about storage: the control source is a DIFFERENT table, so its health cannot license a verdict
# about ours. This arm fails against the pre-fix implementation.
STUB_HTTP_CODE=202 STUB_READBACK=fail STUB_CONTROL=live DEADLINE_OVERRIDE=18 \
  assert_rt "a readback that never answered is UNKNOWN, never a vendor accusation" "ROUNDTRIP_UNKNOWN" 3

# ...and the same input must NOT be reported as DARK either: a broken read of our table is not
# evidence about the warehouse, so the control's verdict must not be borrowed in either direction.
STUB_HTTP_CODE=202 STUB_READBACK=fail STUB_CONTROL=dark DEADLINE_OVERRIDE=18 \
  assert_rt "a readback that never answered is UNKNOWN even when the control is dark" "ROUNDTRIP_UNKNOWN" 3

# The four verdicts must be four distinct tokens on four distinct exit codes.
# ANCHORED ON THE emit() CALL, not the bare token. The SUT's header carries an EXIT CONTRACT
# table naming all four verdicts in prose, so a bare-token grep is satisfied by the comment alone
# and every `emit "ROUNDTRIP_DARK"` call site could be deleted with this assertion still green —
# the forbid-plus-document collision the sibling probe suite already anchors around.
_n_tok=$(grep -oE 'emit[[:space:]]+"ROUNDTRIP_(STORED|NOT_STORED|DARK|UNKNOWN)"' "$SUT" \
         | grep -oE 'ROUNDTRIP_[A-Z_]+' | sort -u | wc -l)
if [[ "$_n_tok" -eq 4 ]]; then
  pass "all four verdict tokens are distinct and present"
else
  fail "expected 4 distinct verdict tokens, found ${_n_tok}"
fi

# BELOW THE MEASURED FLOOR, A NON-OBSERVATION IS NOT A FINDING. A budget under ADR-172's 17 s
# could never have observed the row, so the honest answer is UNKNOWN — never NOT_STORED.
STUB_HTTP_CODE=202 STUB_READBACK=empty STUB_CONTROL=live DEADLINE_OVERRIDE=2 \
  assert_rt "a poll budget below the 17s ADR-172 floor → unknown, never a finding" "ROUNDTRIP_UNKNOWN" 3

echo "--- GUARD 2 ROW 4/5: the marker cannot satisfy any positive control ---"

# ROW 4 — asserted twice, deliberately: at the WIRE by the curl stub (exit 66, above) and here
# against the payload BUILDER. The field is the property, not the source id.
if grep -qE 'RT_PAYLOAD=.*host_name' "$SUT"; then
  fail "the marker payload carries a host_name key — it would become foreign-host liveness for the rung-2 capture"
else
  pass "the marker payload carries no host_name key"
fi

# ROW 5 — the shared source is refused BY NAME, because its liveness is read as an any-row
# control by the rung-2 capture. A marker there would manufacture the answer that capture reads.
_out="$(PATH="$BIN:$PATH" BETTERSTACK_QUERY_SH="$QSTUB" \
  GIT_DATA_BETTERSTACK_LOGS_TOKEN="synthetic-token-for-tests" \
  BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
  GIT_DATA_BETTERSTACK_INGEST_URL="https://s2457081.eu-fsn-3.betterstackdata.com/" \
  bash "$SUT" 2>&1)" || true
if [[ "$_out" == *"ROUNDTRIP_UNKNOWN"* && "$_out" == *"2457081"* ]]; then
  pass "writing to the shared control source 2457081 is refused by name"
else
  fail "the shared control source was not refused" "$_out"
fi

echo "--- GUARD 3: the ingest credential's destination is genuinely pinned ---"
assert_dest() {  # $1=name $2=url $3=refused|accepted
  local out
  out="$(PATH="$BIN:$PATH" BETTERSTACK_QUERY_SH="$QSTUB" \
    GIT_DATA_BETTERSTACK_LOGS_TOKEN="synthetic-token-for-tests" \
    BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
    BETTERSTACK_ROUNDTRIP_POLL_S=1 BETTERSTACK_ROUNDTRIP_DEADLINE_S=18 \
    STUB_WROTE_FILE="$TMP/wrote.txt" \
    STUB_EXPECT_TABLE="t520508_soleur_git_data_prd_logs" \
    STUB_EXPECT_CONTROL_TABLE="t520508_soleur_inngest_vector_prd_3_logs" \
    GIT_DATA_BETTERSTACK_INGEST_URL="$2" bash "$SUT" 2>&1)" || true
  if [[ "$3" == refused ]]; then
    if [[ "$out" == *"refusing to forward the credential"* ]]; then pass "$1"; else fail "$1" "$out"; fi
  else
    if [[ "$out" != *"refusing to forward the credential"* ]]; then pass "$1"; else fail "$1" "$out"; fi
  fi
}
# The same glob bypass that was live in betterstack-ingest-probe.sh on origin/main.
assert_dest "query-string bypass is refused" "https://evil.com/?x=.betterstackdata.com/" refused
assert_dest "path bypass is refused" "https://attacker.example.org/a/.betterstackdata.com/x" refused
assert_dest "userinfo bypass is refused" "https://s1.betterstackdata.com@evil.com/" refused
assert_dest "a lookalike registration is refused" "https://s1.notbetterstackdata.com/" refused
assert_dest "a plaintext http:// destination is refused" "http://s2734275.eu-central-1a.betterstackdata.com/" refused
# HARNESS ROW — must-PASS non-canonical: the real git-data endpoint must still be accepted, or
# the fix is "refuse everything", which every row above would also satisfy.
assert_dest "the real git-data endpoint is still accepted" "https://s2734275.eu-central-1a.betterstackdata.com/" accepted

# Rows 1 and 2 concern flags whose ABSENCE is the defect; a stub cannot observe a flag never passed.
if grep -qE "\-\-proto '=https'" "$SUT"; then pass "curl pins --proto '=https'"; else fail "curl no longer pins --proto '=https'"; fi
if grep -qE '(^|[[:space:]])(-L|--location)([[:space:]]|$)' "$SUT"; then
  fail "curl follows redirects — a 30x would forward the bearer credential off-vendor"
else
  pass "curl does not follow redirects"
fi

echo "--- the sweeper contract ---"
# An unprovisioned secret must be TRANSIENT, never FAIL. `: \${VAR:?}` aborts with status 1,
# which this contract reads as "the warehouse did not store our row" — a vendor accusation
# sourced from our own missing credential.
_out="$(TOKEN_OVERRIDE="" run_rt)" ; _rc=$?
if [[ "$_out" == *"ROUNDTRIP_UNKNOWN"* && "$_rc" -eq 3 ]]; then
  pass "an unset ingest token is TRANSIENT (exit 3), never FAIL"
else
  fail "an unset ingest token did not degrade to TRANSIENT" "rc=$_rc out=$_out"
fi
# DELEGATED TO THE REPO'S OWN LINTER, not re-implemented as a grep here. A bare source grep
# matches the probe's comment EXPLAINING why the form is banned -- the collision that always
# arises when a "must not contain X" assertion meets a comment documenting X. The linter scopes
# itself to executable probe lines, which is the property.
if bash "${ROOT}/scripts/lint-followthrough-varq-ban.sh" >/dev/null 2>&1; then
  pass "no follow-through uses the \${VAR:?} form (lint-followthrough-varq-ban)"
else
  fail "lint-followthrough-varq-ban rejects a probe -- that form aborts with status 1, read as FAIL"
fi

# ── Anti-vacuity floor ───────────────────────────────────────────────────────────────────────
# Reports with printf + exit, NEVER through fail(): a floor routed through the helper it
# backstops cannot witness that helper being disarmed (ADR-193, AP-023).
# FLOOR = the as-written count, derived by running the suite rather than estimated: 20 real
# assertions + the 2 the accounting control contributes (it retracts its deliberate failure from
# `fails`, not from `cases`).
if [[ "$cases" -lt 24 ]]; then
  printf '  FAIL ANTI-VACUITY: only %s cases ran, floor is 24.\n' "$cases" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s cases ran (floor 24)\n' "$cases"

if [[ "${#FAILURES[@]}" -ne "$fails" ]]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded — fail() was tampered with.\n' \
    "$fails" "${#FAILURES[@]}" >&2
  exit 1
fi
printf '\n=== %d passed, %d failed (%d cases) ===\n\n' "$passes" "$fails" "$cases"
exit $(( ${#FAILURES[@]} > 0 ))
