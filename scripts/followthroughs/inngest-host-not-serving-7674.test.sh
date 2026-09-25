#!/usr/bin/env bash
# Exit-code harness for inngest-host-not-serving-7674.sh (#7674 / #8015).
#
# THIS SUITE DID NOT EXIST. The probe's exit code gates a P1 tracker and, since #8015, decides
# whether a host counts as SERVING -- and nothing graded it. Guard 2's mutation rows in the
# probe_schema=8 plan mutated a file with no harness behind it, which is an audit, not a test.
#
# FIXTURES ARE DOUBLE-ENCODED, AND THAT IS THE WHOLE POINT. betterstack-query.sh emits JSONEachRow
# whose `raw` column is a JSON-ENCODED STRING containing a JSON document, and the probe decodes it
# with `fromjson?` at BOTH levels. A fixture emitting `raw` as a bare object puts the seam ABOVE
# the decode: every case here would pass while production returned zero rows. That is #7674's own
# 0/40-vs-40/40 measurement, reproduced inside the suite meant to prevent it. Rows are built with
# jq and `raw` is genuinely `tostring`-ed.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): the envelope and field shape mirror a
# measured emission; host ids and timestamps are fabricated.
#
# THE STUB ASSERTS ITS ARGV. A stub that answers regardless of arguments cannot notice the probe
# querying the wrong thing -- dropping --grep, or shrinking the window, stays green forever.

set -uo pipefail
# Hermetic: the probe resolves the shared predicate relative to itself unless this is set. A value
# leaked from the caller's env would silently point every case at some other lib (or none).
unset INNGEST_PROBE_ROW_LIB

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/inngest-host-not-serving-7674.sh"
fails=0
checks=0
passes=0
# `passes` is tracked SEPARATELY and is what the floor reads. A floor keyed on `checks` is
# FAILURE-INCLUSIVE: both helpers bump it, so a `fail()` rewritten to skip its own counter keeps
# the floor satisfied while the verdict silently inverts. Measured on the first cut of this file:
# one token (`fail() { checks=$((checks + 1)); }`) turned "7 passed, 7 failed / rc 1" into
# "14 passed, 0 failed / rc 0" with a real regression live in the probe.
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
argv="$*"
[[ "$argv" == *"--since"* ]] || { echo "stub: query missing --since (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--grep SOLEUR_INNGEST_SERVER_PROBE"* ]] || { echo "stub: query missing the marker --grep (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--limit"* ]] || { echo "stub: query missing --limit (argv: $argv)" >&2; exit 64; }
cat "${STUB_ROWS:-/dev/null}"
STUB
chmod +x "$WORK/stub-query"

# row <message> [host] [host_name] [emitter] — ONE production-shaped, double-encoded JSONEachRow
# line. The emitter is journald's SYSLOG_IDENTIFIER (#8846): the probe logs under
# `inngest-server-probe`, and the inngest server's own event log ships under `doppler` on the SAME
# host, quoting the marker whenever an issue/PR/comment about the probe is webhooked in.
row() {
  local msg="$1" h="${2:-soleur-inngest}" hn="${3:-soleur-inngest-prd}" ident="${4:-inngest-server-probe}"
  jq -cn --arg m "$msg" --arg h "$h" --arg hn "$hn" --arg id "$ident" \
    '{dt:"2026-09-10 10:00:00", raw: ({message:$m, host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$id, shipper:"vector"} | tostring)}'
}

# eventlog_row — the LIVE shape (#8846): the inngest event log on the dedicated host, emitter
# `doppler`, whose message is a JSON event whose body QUOTES a serving probe line. Every token the
# probe parses is followed by a space, so a substring reader is certain to grade it as serving.
eventlog_row() {
  local body='Measured on the host: SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active registry_fns=9 cutover_flag=done -- closing.'
  row "$(jq -cn --arg b "$body" '{caller:"api", event:{data:{action:"closed", issue:{number:7674}, body:$b}}} | tostring')" \
    soleur-inngest soleur-inngest-prd doppler
}

# probe_row <server_active> <http_code> [extra fields...]
probe_row() {
  local active="$1" code="$2"; shift 2
  printf 'SOLEUR_INNGEST_SERVER_PROBE http_code=%s server_active=%s vector_active=inactive redis_active=active probe_schema=8 host_role=dedicated cutover_flag=aborted %s' \
    "$code" "$active" "$*"
}

run() {
  OUT="$(BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        INNGEST_SERVING_QUERY_BIN="$WORK/stub-query" STUB_ROWS="$1" STUB_RC="${STUB_RC:-0}" \
        bash "$PROBE" 2>&1)"
  RC=$?
}

expect() { # expect <case> <want-rc> <want-substring>
  local name="$1" want_rc="$2" want_sub="$3"
  if [[ "$RC" -ne "$want_rc" ]]; then
    fail "$name — rc=$RC want=$want_rc :: $(printf '%s' "$OUT" | head -1)"
  elif ! grep -qF "$want_sub" <<<"$OUT"; then
    fail "$name — rc ok but missing '$want_sub' :: $(printf '%s' "$OUT" | head -1)"
  else
    pass "$name"
  fi
}

echo "== inngest-host-not-serving-7674.sh exit-code harness =="

# --- H1 the harness itself can FAIL --------------------------------------------------------
# A suite whose wrapper cannot go red certifies nothing. Drive a case that MUST fail and confirm
# the counter moved, then roll it back -- the instrument self-test the wrapper otherwise lacks.
_h_f0="$fails"; _h_c0="$checks"; _h_p0="$passes"
RC=99; OUT="nothing like the expected text"
# stderr is muted for this ONE call: the failure is deliberate, and an un-muted line reading
# "FAIL: SELFTEST" in the output of a green suite is indistinguishable from a real regression to
# anyone reading CI logs.
expect "SELFTEST (must fail)" 0 "this substring cannot appear" 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails="$_h_f0"; checks="$_h_c0"; passes="$_h_p0"; pass "INSTRUMENT: expect() reports a genuine mismatch as a failure"
else
  # printf + exit DIRECTLY: routing this through fail() would make the self-test that certifies the
  # helpers depend on the helpers, which is precisely the state it exists to detect.
  printf '  FAIL INSTRUMENT: expect() did NOT fail on a guaranteed mismatch — every case below is decorative.\n' >&2
  exit 1
fi

# --- H2 the stub rejects a malformed query, so argv drift cannot pass silently --------------
: > "$WORK/empty.jsonl"
_argv_out="$(STUB_ROWS="$WORK/empty.jsonl" "$WORK/stub-query" --since 24h --limit 500 2>&1; echo "rc=$?")"
if grep -q 'rc=64' <<<"$_argv_out"; then
  pass "INSTRUMENT: the stub exits 64 when --grep is missing (argv is actually asserted)"
else
  fail "INSTRUMENT: the stub accepted a query with no --grep — every argv assertion here is vacuous"
fi

# --- C1 zero rows is channel_dark, never a PASS ---------------------------------------------
run "$WORK/empty.jsonl"
expect "C1 zero probe rows => TRANSIENT channel_dark (serving state UNKNOWN, not healthy)" 2 "reason=channel_dark"

# --- C2 the three-conjunct PASS (#8015) ------------------------------------------------------
row "$(probe_row active 200 registry_fns=12)" > "$WORK/pass.jsonl"
run "$WORK/pass.jsonl"
expect "C2 active + 200 + a NON-ZERO registry => PASS" 0 "PASS:"

# --- C3 THE DEFECT #8015 CLOSES: a diagnostic boot satisfied the old two-field rule ----------
# registry_fns=0 is a MEASUREMENT -- a server that answers and owns nothing. Before the third
# conjunct this row returned PASS and closed the tracker on a host serving nothing at all.
row "$(probe_row active 200 registry_fns=0)" > "$WORK/diag.jsonl"
run "$WORK/diag.jsonl"
expect "C3 active + 200 but registry_fns=0 (DIAGNOSTIC BOOT) => refuses, where the old rule PASSED" 2 "reason=not_serving"
expect "C3 ...and names the cause rather than leaving 'down' vs 'owns nothing' ambiguous" 2 "registry_fns=0 is a MEASUREMENT"

# --- C4 an unreadable registry is not a count ------------------------------------------------
row "$(probe_row active 200 registry_fns=__UNREADABLE__)" > "$WORK/unread.jsonl"
run "$WORK/unread.jsonl"
expect "C4 registry_fns=__UNREADABLE__ => refuses (the question was not answered)" 2 "reason=not_serving"

# --- C5 THE TOKEN BOUNDARY. A bare [1-9][0-9]* also matches registry_fns=1abc ---------------
row "$(probe_row active 200 registry_fns=1abc)" > "$WORK/garbage.jsonl"
run "$WORK/garbage.jsonl"
expect "C5 registry_fns=1abc => refuses (trailing garbage is not a count)" 2 "reason=not_serving"

# --- C6 a host on the PRE-#8015 image cannot answer the conjunct at all ---------------------
row "SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active probe_schema=7 host_role=dedicated cutover_flag=aborted" > "$WORK/old.jsonl"
run "$WORK/old.jsonl"
expect "C6 no registry_fns field (host predates schema 8) => refuses, never a legacy pass" 2 "reason=not_serving"
expect "C6 ...and says the conjunct could not be evaluated rather than blaming the host" 2 "predates probe_schema=8"

# --- C7 SAME-ROW conjunction: two halves from two moments must not assemble a PASS ----------
{ row "$(probe_row active 200 registry_fns=0)"
  row "$(probe_row inactive 000 registry_fns=12)"; } > "$WORK/split.jsonl"
run "$WORK/split.jsonl"
expect "C7 the conjuncts split across TWO rows never assemble into a PASS" 2 "reason=not_serving"

# --- C8 identity filter: another host's healthy row is not ours ------------------------------
row "$(probe_row active 200 registry_fns=12)" "soleur-web" "soleur-web-prd" > "$WORK/other.jsonl"
run "$WORK/other.jsonl"
expect "C8 a DIFFERENT host's serving row is filtered out => channel_dark" 2 "reason=channel_dark"

# --- C9 a malformed line must not abort the decode and lose the valid rows after it ---------
{ printf 'not json at all\n'; row "$(probe_row active 200 registry_fns=12)"; } > "$WORK/mixed.jsonl"
run "$WORK/mixed.jsonl"
expect "C9 one malformed line does not swallow the valid PASS row after it" 0 "PASS:"

# --- C10 a query transport failure is not 'not serving' -------------------------------------
STUB_RC=1 run "$WORK/pass.jsonl"
STUB_RC=0
if [[ "$RC" -ne 0 ]]; then
  pass "C10 a failing warehouse query does not report a PASS"
else
  fail "C10 a failing warehouse query returned PASS — a read error read as a healthy host"
fi

# --- C11 THE #8846 FAIL-OPEN: an event-log row quoting a serving line is not a probe reading ----
# The real probe says the host is dark; the inngest event log on the SAME host (emitter `doppler`)
# carries an issue body quoting a serving probe line. A substring reader PASSED this and closed
# #7674 (and cleared apply-workflow G18) on a host serving nothing.
{ row "$(probe_row inactive 000 registry_fns=0)"
  eventlog_row; } > "$WORK/eventlog-quote.jsonl"
run "$WORK/eventlog-quote.jsonl"
expect "C11 real inactive probe + a doppler event-log row QUOTING a serving line => not_serving, never PASS" 2 "reason=not_serving"
expect "C11 ...and the verdict reads the REAL probe row, not the quoted one" 2 "server_active=inactive http_code=000"

# --- C12 the event-log row alone is no probe row at all ---------------------------------------
eventlog_row > "$WORK/eventlog-only.jsonl"
run "$WORK/eventlog-only.jsonl"
expect "C12 ONLY a doppler event-log row quoting a serving line => channel_dark" 2 "reason=channel_dark"

# --- C13 FORGED shape: not observed live (journald splits multi-line stdout into one entry per
# line, so a quoted line CAN begin a message); the emitter clause alone must reject it -----------
row "$(probe_row active 200 registry_fns=12)" soleur-inngest soleur-inngest-prd doppler > "$WORK/forged.jsonl"
run "$WORK/forged.jsonl"
expect "C13 a doppler row that BEGINS with the marker (forged shape) => channel_dark, never PASS" 2 "reason=channel_dark"

# --- C14 an unloadable selector is its own TRANSIENT, never channel_dark and never PASS -------
INNGEST_PROBE_ROW_LIB=/nonexistent run "$WORK/pass.jsonl"
expect "C14 INNGEST_PROBE_ROW_LIB=/nonexistent on a serving row => selector_unavailable" 2 "reason=selector_unavailable"
expect "C14 ...and names the path it could not load" 2 "lib=/nonexistent"

# --- C15 a def that does not compile is a decode failure, never silence and never PASS --------
# jq exits 3 on a compile error. Piped straight into grep, that exit code vanished: zero rows out
# read as channel_dark, or (after a grep that no longer runs) as nothing at all.
printf '%s\n' 'INNGEST_PROBE_ROW_JQ="def inngest_probe_row: ((( ;"' > "$WORK/broken-def.sh"
INNGEST_PROBE_ROW_LIB="$WORK/broken-def.sh" run "$WORK/pass.jsonl"
expect "C15 a lib whose def does not compile => decode_failed with jq's exit code" 2 "reason=decode_failed jq_rc="

# --- C16 a lib that sources cleanly but defines nothing is still an unavailable selector ------
printf '%s\n' '# defines nothing' > "$WORK/empty-lib.sh"
INNGEST_PROBE_ROW_LIB="$WORK/empty-lib.sh" run "$WORK/pass.jsonl"
expect "C16 a lib that defines no INNGEST_PROBE_ROW_JQ => selector_unavailable, not a set -u abort" 2 "reason=selector_unavailable"

# --- anti-vacuity floor ---------------------------------------------------------------------
# Equal to the count, so deleting any case reds the suite. Reported with printf + exit, never
# through the helpers it backstops (ADR-193): a floor that calls fail() is disarmed by the same
# edit that disarms fail().
# Equal to the count measured after the self-test rolls its own counter back. Keyed on `passes`,
# NOT `checks` -- see the note on the helpers above. Reported with printf + exit directly, never
# through the helpers it backstops (a floor dispatched through `fail()` is disarmed by the same
# one-line edit that disarms every assertion it protects).
# 14 pre-#8846 + 8 (#8846): C11 x2, C12, C13, C14 x2, C15, C16.
FLOOR=22
if [[ "$passes" -lt "$FLOOR" ]]; then
  printf '  FAIL ANTI-VACUITY: only %s PASSES recorded, floor is %s — cases were deleted, skipped, or a helper stopped counting.\n' "$passes" "$FLOOR" >&2
  exit 1
fi
# CONSERVATION: the two counters must reconcile. A helper that bumps one and not the other -- the
# exact mutation this file's own floor could not previously see -- breaks this even when both the
# floor and the failure count look healthy.
if [[ "$((passes + fails))" -ne "$checks" ]]; then
  printf '  FAIL INSTRUMENT: passes(%s) + fails(%s) != checks(%s) — a verdict helper is not counting.\n' "$passes" "$fails" "$checks" >&2
  exit 1
fi

printf '\ninngest-host-not-serving-7674: %s passed, %s failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
