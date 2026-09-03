#!/usr/bin/env bash
# Tests for inngest-cutover-flip-rollout-7761.sh (#7761 Phase 8 probe).
#
# WHY THIS EXISTS. The probe is what authorizes closing a P1 security issue after a production
# destroy-and-recreate of the fleet's sole scheduler. An unexercised probe that always returns
# TRANSIENT is a permanent silent no-op, and one that returns PASS on the wrong evidence closes
# the tracker on a host nobody measured — both are recorded failure modes of this probe's own
# predecessor (see the header of inngest-host-not-serving-7674.sh).
#
# The probe is driven through a STUBBED query binary, so every arm is reachable offline. The stub
# is seamed via FLIP_ROLLOUT_QUERY_BIN, which the probe already reads — no PATH shadowing.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-cutover-flip-rollout-7761.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# INSTRUMENT SELF-TEST (#7761 review, P0). Measured on this suite: with the SUT genuinely broken
# (`sys.exit(main())` -> `main(); sys.exit(0)`) it printed 10 real FAIL: lines and, with fail()
# neutered, reported "20/20 passed, 0 failed" and exit 0 — self-consistently, because the
# denominator is PASS+FAIL. CI reads only the exit code. Neutering pass() IS caught (the floor sums
# PASS); neutering fail() was not, because the floor reported THROUGH fail(). Prove both counters
# move, then reset. Output suppressed so the deliberate FAIL row is not misread as a real one.
pass "instrument self-test" >/dev/null
fail "instrument self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: assertion counters are broken (PASS=%s FAIL=%s, expected 1/1).\n' "$PASS" "$FAIL" >&2
  exit 1
fi
PASS=0
FAIL=0

WORK="$(mktemp -d -t flip7761probe.XXXXXXXX)" || { echo "SETUP FAIL: mktemp"; exit 2; }
trap 'rm -rf "$WORK"' EXIT

HOST="soleur-inngest"
HOST_NAME="soleur-inngest-prd"
BOUNDARY="2026-09-03T12:00:00Z"

# Build one warehouse row in the DOUBLE-ENCODED shape the real source returns: the outer object
# carries `raw` as a JSON *string*, which decodes to {host, host_name, message}, and `message` is
# itself the flip script's emit_state JSON. Getting this wrong is not hypothetical — a probe that
# matched the outer row read zero rows forever (#7674).
row() { # row <flag> <reason> <start_ts> [host] [host_name]
  local flag="$1" reason="$2" ts="$3" h="${4:-$HOST}" hn="${5:-$HOST_NAME}"
  local msg inner
  msg="$(jq -nc --arg r "$reason" --arg f "$flag" --arg t "$ts" \
        '{exit_code:0, dbsize:"", reason:$r, flag:$f, start_ts:$t}')"
  inner="$(jq -nc --arg h "$h" --arg hn "$hn" --arg m "$msg" \
          '{host:$h, host_name:$hn, message:$m}')"
  jq -nc --arg raw "$inner" '{raw:$raw}'
}

# make_stub <file-with-rows> -> a query binary that prints them and exits 0
make_stub() {
  local rows_file="$1" stub="$WORK/query-$RANDOM.sh"
  cat > "$stub" <<EOF
#!/usr/bin/env bash
cat "$rows_file"
EOF
  chmod +x "$stub"
  printf '%s' "$stub"
}

failing_stub() {
  local stub="$WORK/queryfail-$RANDOM.sh"
  printf '#!/usr/bin/env bash\nexit 7\n' > "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}

# run_probe <stub> [EXTRA_ENV...] -> echoes the exit code; the probe's combined output lands in
# $WORK/probe-out, and callers read it with probe_out.
#
# The output MUST travel through a file rather than a variable. Callers invoke this as
# `rc="$(run_probe ...)"`, and command substitution runs the function in a SUBSHELL — so any
# variable this function assigns is discarded the moment it returns, and every message assertion
# would silently compare against an empty string while the exit-code assertions kept passing.
# That is not hypothetical: it is how this suite first behaved.
run_probe() {
  local stub="$1"; shift
  local rc=0
  # PATH is left alone; `doppler` may or may not exist in the caller's environment and the probe
  # treats it as corroboration either way, so both cases are legitimate here. The credential vars
  # are supplied so the run reaches the marker logic rather than stopping at the credential arm.
  env FLIP_ROLLOUT_QUERY_BIN="$stub" \
      FLIP_ROLLOUT_AFTER="$BOUNDARY" \
      FLIP_ROLLOUT_AFTER_FILE="$WORK/nonexistent.after" \
      BETTERSTACK_QUERY_HOST=stub \
      BETTERSTACK_QUERY_USERNAME=stub \
      BETTERSTACK_QUERY_PASSWORD=stub \
      FLIP_ROLLOUT_DOPPLER_PROJECT=__no_such_project__ \
      "$@" bash "$TARGET" > "$WORK/probe-out" 2>&1 || rc=$?
  printf '%s' "$rc"
}
probe_out() { cat "$WORK/probe-out" 2>/dev/null || true; }

echo "=== inngest-cutover-flip-rollout-7761.sh probe test suite ==="

# --- 1. boundary absent => TRANSIENT, never PASS -------------------------------------------
echo "TEST: an unsupplied boundary is TRANSIENT, not a pass"
f="$WORK/rows-empty"; : > "$f"
rc=0
out="$(env FLIP_ROLLOUT_QUERY_BIN="$(make_stub "$f")" \
           FLIP_ROLLOUT_AFTER_FILE="$WORK/nonexistent.after" \
           BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
           bash "$TARGET" 2>&1)" || rc=$?
[[ "$rc" == "2" ]] && pass "exit 2 when no boundary is supplied" || fail "expected exit 2, got $rc"
[[ "$out" == *"boundary_unknown"* ]] && pass "names boundary_unknown as the reason" || fail "reason not named: $out"

# --- 2. an unparseable boundary must not widen to 'any time' -------------------------------
echo "TEST: an unparseable boundary is TRANSIENT, not silently widened"
rc=0
out="$(env FLIP_ROLLOUT_QUERY_BIN="$(make_stub "$f")" \
           FLIP_ROLLOUT_AFTER="last tuesday" \
           BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
           bash "$TARGET" 2>&1)" || rc=$?
[[ "$rc" == "2" ]] && pass "exit 2 on an unparseable boundary" || fail "expected exit 2, got $rc"
[[ "$out" == *"boundary_unparseable"* ]] && pass "names boundary_unparseable" || fail "reason not named"

# --- 3. the happy path ---------------------------------------------------------------------
echo "TEST: two post-boundary rolled-back markers => PASS"
f="$WORK/rows-good"
{ row rolled-back noop-rolled-back "2026-09-03T12:05:00Z"
  row rolled-back noop-rolled-back "2026-09-03T12:05:30Z"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "0" ]] && pass "exit 0 with two post-boundary markers" || fail "expected 0, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"PASS: #7761 delivered"* ]] && pass "reports the delivery in its own words" || fail "no PASS line"

# --- 4. ONE marker is not enough: booted-once is not cycling --------------------------------
echo "TEST: a single post-boundary marker is TRANSIENT (booted once != timer cycling)"
f="$WORK/rows-one"
row rolled-back noop-rolled-back "2026-09-03T12:05:00Z" > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 on a single marker" || fail "expected 2, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"insufficient_post_replace_markers"* ]] && pass "names the insufficient-marker reason" || fail "reason not named"

# --- 5. PRE-boundary markers must not satisfy the probe -------------------------------------
# The row this exists for: markers produced by the host the rollout REPLACED would otherwise
# certify the rollout. Two valid markers, both before the boundary.
echo "TEST: pre-boundary markers do NOT satisfy the probe (the replaced host's evidence)"
f="$WORK/rows-old"
{ row rolled-back noop-rolled-back "2026-09-03T11:00:00Z"
  row rolled-back noop-rolled-back "2026-09-03T11:30:00Z"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 when every marker predates the boundary" || fail "expected 2, got $rc: $(probe_out)"

# --- 6. a flush-path transition is a hard FAIL ----------------------------------------------
echo "TEST: a post-boundary flush-path transition FAILs (the latch guarantee is broken)"
f="$WORK/rows-flush"
{ row rolled-back noop-rolled-back "2026-09-03T12:05:00Z"
  row rolled-back noop-rolled-back "2026-09-03T12:05:30Z"
  row flushed flip-flushed "2026-09-03T12:06:00Z"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "1" ]] && pass "exit 1 on a post-boundary flush-path transition" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"latch guarantee is broken"* ]] && pass "names the latch guarantee" || fail "message not named"

# --- 7. `armed` must FAIL, not pass -----------------------------------------------------------
# The row the narrower {flipping,flushed,done} enumeration would have let through. `armed` is the
# state whose NEXT poll stops the server and runs FLUSHALL, so passing here would report all-clear
# on the last quiet moment before the destructive arm.
echo "TEST: a post-boundary flag=armed FAILs (a cutover is queued, not a quiet host)"
f="$WORK/rows-armed"
{ row rolled-back noop-rolled-back "2026-09-03T12:05:00Z"
  row rolled-back noop-rolled-back "2026-09-03T12:05:30Z"
  row armed noop-armed "2026-09-03T12:06:00Z"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "1" ]] && pass "exit 1 on a post-boundary flag=armed" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"cutover is QUEUED"* ]] && pass "names the queued cutover explicitly" || fail "message not named"

# --- 8. host isolation, on BOTH identity fields ---------------------------------------------
# web-1 legitimately emits on this marker family. A probe filtering on only one field would close
# #7761 using another host's rows.
echo "TEST: rows from another host do not satisfy the probe (both identity fields required)"
f="$WORK/rows-otherhost"
{ row rolled-back noop-rolled-back "2026-09-03T12:05:00Z" "web-1" "web-1-prd"
  row rolled-back noop-rolled-back "2026-09-03T12:05:30Z" "web-1" "web-1-prd"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 when the only rows belong to another host" || fail "expected 2, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"channel_dark"* ]] && pass "reports channel_dark rather than inventing a pass" || fail "reason not named"

echo "TEST: a row matching host_name but NOT host is rejected (#6616 — host_name can lie)"
f="$WORK/rows-spoof"
{ row rolled-back noop-rolled-back "2026-09-03T12:05:00Z" "web-1" "$HOST_NAME"
  row rolled-back noop-rolled-back "2026-09-03T12:05:30Z" "web-1" "$HOST_NAME"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 when host_name matches but host does not" || fail "expected 2, got $rc: $(probe_out)"

# --- 9. a query failure is TRANSIENT, never a pass ------------------------------------------
echo "TEST: a failing query is TRANSIENT (a read-path outage is not a statement about the host)"
rc="$(run_probe "$(failing_stub)")"
[[ "$rc" == "2" ]] && pass "exit 2 when the query binary fails" || fail "expected 2, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"query_failed"* ]] && pass "names query_failed" || fail "reason not named"

# --- 10. a malformed line must not destroy the rows after it --------------------------------
# Without `-R` + `fromjson?`, one truncated warehouse line aborts the whole jq invocation and the
# probe reports channel_dark on a window that in fact contained a clean pass.
echo "TEST: one malformed row does not discard the valid rows after it"
f="$WORK/rows-malformed"
{ printf '{"raw":"{trunca\n'
  row rolled-back noop-rolled-back "2026-09-03T12:05:00Z"
  row rolled-back noop-rolled-back "2026-09-03T12:05:30Z"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "0" ]] && pass "exit 0 — the malformed line was skipped, not fatal" || fail "expected 0, got $rc: $(probe_out)"

# --- floor ------------------------------------------------------------------------------------
# Every assertion above gates only on FAIL, so deleting a whole block would drop PASS and still
# exit 0. Derived from a green run, never guessed.
MIN_ASSERTIONS=19
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  # printf + exit, NOT fail() (ADR-193): routing the floor through the counter it exists to
  # protect means one edit disarms both. See the instrument self-test at the top.
  printf 'FAIL: assertion-count floor: only %s assertions ran, expected >= %s — a block was skipped.\n' \
    "$PASS" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
