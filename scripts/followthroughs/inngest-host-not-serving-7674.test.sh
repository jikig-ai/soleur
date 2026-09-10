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

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/inngest-host-not-serving-7674.sh"
fails=0
checks=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
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

# row <message> [host] [host_name] — ONE production-shaped, double-encoded JSONEachRow line.
row() {
  local msg="$1" h="${2:-soleur-inngest}" hn="${3:-soleur-inngest-prd}"
  jq -cn --arg m "$msg" --arg h "$h" --arg hn "$hn" \
    '{dt:"2026-09-10 10:00:00", raw: ({message:$m, host:$h, host_name:$hn, shipper:"vector"} | tostring)}'
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
_h_f0="$fails"; _h_c0="$checks"
RC=99; OUT="nothing like the expected text"
# stderr is muted for this ONE call: the failure is deliberate, and an un-muted line reading
# "FAIL: SELFTEST" in the output of a green suite is indistinguishable from a real regression to
# anyone reading CI logs.
expect "SELFTEST (must fail)" 0 "this substring cannot appear" 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails="$_h_f0"; checks="$_h_c0"; pass "INSTRUMENT: expect() reports a genuine mismatch as a failure"
else
  fails="$_h_f0"; checks="$_h_c0"; fail "INSTRUMENT: expect() did NOT fail on a guaranteed mismatch — every case below is decorative"
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

# --- anti-vacuity floor ---------------------------------------------------------------------
# Equal to the count, so deleting any case reds the suite. Reported with printf + exit, never
# through the helpers it backstops (ADR-193): a floor that calls fail() is disarmed by the same
# edit that disarms fail().
# Equal to the count measured after the self-test rolls its own counter back.
FLOOR=14
if [[ "$checks" -lt "$FLOOR" ]]; then
  printf '  FAIL ANTI-VACUITY: only %s checks ran, floor is %s — cases were deleted or skipped.\n' "$checks" "$FLOOR" >&2
  exit 1
fi

printf '\ninngest-host-not-serving-7674: %s passed, %s failed\n' "$((checks - fails))" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
