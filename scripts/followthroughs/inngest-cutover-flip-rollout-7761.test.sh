#!/usr/bin/env bash
# Tests for inngest-cutover-flip-rollout-7761.sh (#7761 Phase 8 probe).
#
# WHY THIS EXISTS. The probe is what authorizes closing a P1 security issue after a production
# destroy-and-recreate of the fleet's sole scheduler. An unexercised probe that always returns
# TRANSIENT is a permanent silent no-op, and one that returns PASS on the wrong evidence closes
# the tracker on a host nobody measured — both are recorded failure modes of this probe's own
# predecessor (see the header of inngest-host-not-serving-7674.sh).
#
# THE STUB APPLIES ITS --grep, AND THAT IS THE POINT. An earlier revision of this suite `cat`-ed a
# fixture and discarded every argument, so it modelled the query's SHAPE and not its SELECTION —
# and it certified 19/19 green over a probe whose grep term (`SOLEUR_INNGEST_CUTOVER`) matched none
# of the bare-JSON rows it counts, making the probe structurally incapable of passing. A fake that
# answers regardless of the request cannot observe the request being wrong. Every stub below
# filters its fixture by the term the probe actually passes.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-cutover-flip-rollout-7761.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# INSTRUMENT SELF-TEST (#7761 review, P0). The assertion floor at the bottom used to report THROUGH
# fail(), so one edit disarmed every assertion and the floor together while the suite exited 0.
# Prove both counters move, then reset. Output suppressed so the deliberate FAIL row is not misread.
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
TAG="inngest-cutover-flip"
# BOUNDARY AND EVERY FIXTURE TIMESTAMP ARE RELATIVE TO NOW, and that is load-bearing rather than
# tidy. The probe grades silence by AGE: past FLIP_ROLLOUT_STALE_AFTER_S (default 3600s) a quiet
# host stops being "not yet" and becomes a FAIL. An ABSOLUTE boundary therefore makes this suite's
# verdicts a function of when it runs — the literal `2026-09-03T12:00:00Z` that lived here was
# green for exactly one hour after it was written, then flipped five TRANSIENT cases to FAIL and
# would have redded every run from then on. It reached CI. Anchor to now and the arms stay
# deterministic on any day.
#
# OLD_BOUNDARY stays absolute ON PURPOSE: it is the deliberately-stale arm, and a fixed date in
# the past only gets staler, so it cannot rot in the direction that matters.
_ts() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }   # GNU date; CI and the dev host both have it
BOUNDARY="$(_ts '-5 minutes')"        # fresh: well inside STALE_AFTER_S, so silence is TRANSIENT
POST_A="$(_ts '-4 minutes')"          # first post-boundary marker
POST_B="$(_ts '-210 seconds')"        # second — two are what proves the 30s timer is cycling
POST_C="$(_ts '-3 minutes')"          # a third row (a flush transition / an armed flag)
PRE_A="$(_ts '-65 minutes')"          # pre-boundary: the REPLACED host's evidence
PRE_B="$(_ts '-35 minutes')"
OLD_BOUNDARY="2020-01-01T00:00:00Z"
GUARD="7761"

# FRESHNESS SELF-CHECK. If someone reinstates an absolute BOUNDARY, this says so by name instead
# of letting five unrelated assertions flip verdict for a reason none of them mentions.
_b_epoch="$(date -u -d "$BOUNDARY" +%s 2>/dev/null || echo 0)"
_now_epoch="$(date -u +%s)"
_b_age=$(( _now_epoch - _b_epoch ))
_stale_after="${FLIP_ROLLOUT_STALE_AFTER_S:-3600}"
if [[ "$_b_epoch" -le 0 || "$_b_age" -ge "$_stale_after" ]]; then
  printf 'SETUP FAIL: BOUNDARY is %ss old, at or past the probe STALE_AFTER_S of %ss.\n' \
    "$_b_age" "$_stale_after" >&2
  printf '            The TRANSIENT arms below grade silence by AGE and would all read FAIL.\n' >&2
  printf '            BOUNDARY must be computed relative to now, never written as a literal.\n' >&2
  exit 2
fi

# One warehouse row in the DOUBLE-ENCODED shape the real source returns: the outer object carries
# `raw` as a JSON *string*, which decodes to {host, host_name, SYSLOG_IDENTIFIER, message}, and
# `message` is itself the flip script's emit_state JSON. Getting this wrong is not hypothetical — a
# probe that matched the outer row read zero rows forever (#7674).
row() { # row <flag> <reason> <start_ts> [guard] [host] [host_name]
  local flag="$1" reason="$2" ts="$3" g="${4-$GUARD}" h="${5:-$HOST}" hn="${6:-$HOST_NAME}"
  local msg inner
  if [[ -n "$g" ]]; then
    msg="$(jq -nc --arg r "$reason" --arg f "$flag" --arg t "$ts" --arg g "$g" \
          '{exit_code:0, dbsize:"", reason:$r, flag:$f, start_ts:$t, guard:$g}')"
  else
    # A PRE-#7761 row: same shape, no guard stamp. This is what a host still running the old image
    # emits, and it is the fixture the delivery discriminator exists to reject.
    msg="$(jq -nc --arg r "$reason" --arg f "$flag" --arg t "$ts" \
          '{exit_code:0, dbsize:"", reason:$r, flag:$f, start_ts:$t}')"
  fi
  inner="$(jq -nc --arg h "$h" --arg hn "$hn" --arg t "$TAG" --arg m "$msg" \
          '{host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$t, message:$m}')"
  jq -nc --arg raw "$inner" '{raw:$raw}'
}

# A raw (non-JSON) marker line, as the seam gate's refusal emits it.
refusal_row() {
  local inner
  inner="$(jq -nc --arg h "$HOST" --arg hn "$HOST_NAME" --arg t "$TAG" \
          '{host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$t,
            message:"SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED count=1 detail=collision"}')"
  jq -nc --arg raw "$inner" '{raw:$raw}'
}

# A query stub that APPLIES its --grep, so the probe's SELECTION is under test, not just its shape.
make_stub() {
  local rows_file="$1" stub="$WORK/query-$RANDOM$RANDOM.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
term=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --grep) term="$2"; shift 2 ;;
    --since|--limit) shift 2 ;;
    *) shift ;;
  esac
done
# Refuse rather than answer: a stub that returns rows for a request carrying no --grep cannot
# observe the probe forgetting one.
[[ -n "$term" ]] || { echo "STUB: probe passed no --grep" >&2; exit 64; }
grep -F -- "$term" "__ROWS__" || true
STUBEOF
  sed -i "s|__ROWS__|$rows_file|" "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}

failing_stub() {
  local stub="$WORK/queryfail-$RANDOM.sh"
  printf '#!/usr/bin/env bash\nexit 7\n' > "$stub"; chmod +x "$stub"
  printf '%s' "$stub"
}

# A doppler stub, so the corroboration arm is drivable. Without a seam that arm is unreachable by
# design and its FAIL branch has zero coverage.
doppler_stub() {
  local val="$1" stub="$WORK/doppler-$RANDOM$RANDOM.sh"
  { printf '#!/usr/bin/env bash\n'; printf 'printf %%s %s\n' "$val"; } > "$stub"
  chmod +x "$stub"; printf '%s' "$stub"
}

# run_probe <stub> [EXTRA_ENV...] -> echoes the exit code; output lands in $WORK/probe-out.
# The output MUST travel through a file: callers invoke this as `rc="$(run_probe ...)"`, and
# command substitution runs the function in a SUBSHELL, so any variable it assigns is discarded and
# every message assertion would silently compare against an empty string while the exit-code
# assertions kept passing. That is not hypothetical — it is how this suite first behaved.
#
# FLIP_ROLLOUT_DOPPLER_BIN points at a non-existent path by default, so an ambient `doppler` on the
# runner's PATH cannot leak into the result. The suite previously relied on the real binary FAILING.
run_probe() {
  local stub="$1"; shift
  local rc=0
  env FLIP_ROLLOUT_QUERY_BIN="$stub" \
      FLIP_ROLLOUT_AFTER="$BOUNDARY" \
      FLIP_ROLLOUT_AFTER_FILE="$WORK/nonexistent.after" \
      FLIP_ROLLOUT_DOPPLER_BIN="$WORK/no-such-doppler" \
      BETTERSTACK_QUERY_HOST=stub \
      BETTERSTACK_QUERY_USERNAME=stub \
      BETTERSTACK_QUERY_PASSWORD=stub \
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
           FLIP_ROLLOUT_DOPPLER_BIN="$WORK/no-such-doppler" \
           BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
           bash "$TARGET" 2>&1)" || rc=$?
[[ "$rc" == "2" ]] && pass "exit 2 when no boundary is supplied" || fail "expected exit 2, got $rc"
[[ "$out" == *"boundary_unknown"* ]] && pass "names boundary_unknown as the reason" || fail "reason not named: $out"

# --- 2. an unparseable boundary must not widen to 'any time' -------------------------------
echo "TEST: an unparseable boundary is TRANSIENT, not silently widened"
rc=0
out="$(env FLIP_ROLLOUT_QUERY_BIN="$(make_stub "$f")" \
           FLIP_ROLLOUT_AFTER="last tuesday" \
           FLIP_ROLLOUT_DOPPLER_BIN="$WORK/no-such-doppler" \
           BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
           bash "$TARGET" 2>&1)" || rc=$?
[[ "$rc" == "2" ]] && pass "exit 2 on an unparseable boundary" || fail "expected exit 2, got $rc"
[[ "$out" == *"boundary_unparseable"* ]] && pass "names boundary_unparseable" || fail "reason not named"

# --- 3. the happy path ---------------------------------------------------------------------
echo "TEST: two post-boundary guard-stamped rolled-back markers => PASS"
f="$WORK/rows-good"
{ row rolled-back noop-rolled-back "$POST_A"
  row rolled-back noop-rolled-back "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "0" ]] && pass "exit 0 with two post-boundary markers" || fail "expected 0, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"PASS: #7761 delivered"* ]] && pass "reports the delivery in its own words" || fail "no PASS line"

# --- 3b. THE GREP MUST SELECT THE ROWS IT COUNTS (the inert-probe row) ----------------------
# The row this suite exists for. The probe greps a term; if that term does not appear in the rows
# it counts, it can never pass — which is exactly what shipped, invisible to a stub that ignored
# --grep. Assert the term the probe actually passes is the syslog tag.
echo "TEST: #7761 the probe greps the syslog TAG, not a string the JSON rows never carry"
GREP_SEEN="$WORK/grep-seen"; : > "$GREP_SEEN"
spy="$WORK/query-spy.sh"
{ printf '#!/usr/bin/env bash\nterm=""\n'
  printf 'while [[ $# -gt 0 ]]; do case "$1" in\n'
  printf '  --grep) term="$2"; printf "%%s\\n" "$2" >> %q; shift 2 ;;\n' "$GREP_SEEN"
  printf '  --since|--limit) shift 2 ;; *) shift ;; esac; done\n'
  printf 'grep -F -- "$term" %q || true\n' "$f"
} > "$spy"
chmod +x "$spy"
rc="$(run_probe "$spy")"
[[ "$rc" == "0" ]] && pass "the probe passes against a grep-applying stub" || fail "expected 0, got $rc: $(probe_out)"
if grep -qxF "$TAG" "$GREP_SEEN"; then
  pass "the probe's grep term is the syslog tag '$TAG'"
else
  fail "grep terms were [$(tr '\n' ' ' < "$GREP_SEEN")] — none is the tag '$TAG'"
fi

# --- 4. ONE marker is not enough: booted-once is not cycling --------------------------------
echo "TEST: a single post-boundary marker is TRANSIENT (booted once != timer cycling)"
f="$WORK/rows-one"
row rolled-back noop-rolled-back "$POST_A" > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 on a single marker" || fail "expected 2, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"insufficient_post_replace_markers"* ]] && pass "names the insufficient-marker reason" || fail "reason not named"

# --- 5. PRE-boundary markers must not satisfy the probe -------------------------------------
echo "TEST: pre-boundary markers do NOT satisfy the probe (the replaced host's evidence)"
f="$WORK/rows-old"
{ row rolled-back noop-rolled-back "$PRE_A"
  row rolled-back noop-rolled-back "$PRE_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 when every marker predates the boundary" || fail "expected 2, got $rc: $(probe_out)"

# --- 5b. THE DELIVERY DISCRIMINATOR --------------------------------------------------------
# A host that booted after the boundary but is still running the PRE-fix image emits byte-identical
# evidence apart from the guard stamp. Without this the probe certifies a rollout that delivered
# nothing — every other observable it checks is emitted by the old script too.
echo "TEST: #7761 post-boundary markers WITHOUT the guard stamp are a stale image, not a pass"
f="$WORK/rows-oldrev"
{ row rolled-back noop-rolled-back "$POST_A" ""
  row rolled-back noop-rolled-back "$POST_B" ""; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "1" ]] && pass "exit 1 when post-boundary rows carry no guard stamp" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"stale_image"* ]] && pass "names stale_image rather than silence" || fail "reason not named"

# --- 6. a flush-path transition is a hard FAIL ----------------------------------------------
echo "TEST: a post-boundary flush-path transition FAILs (the latch guarantee is broken)"
f="$WORK/rows-flush"
{ row rolled-back noop-rolled-back "$POST_A"
  row rolled-back noop-rolled-back "$POST_B"
  row flushed flip-flushed "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "1" ]] && pass "exit 1 on a post-boundary flush-path transition" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"latch guarantee is broken"* ]] && pass "names the latch guarantee" || fail "message not named"

# --- 7. `armed` must FAIL, not pass -----------------------------------------------------------
echo "TEST: a post-boundary flag=armed FAILs (a cutover is queued, not a quiet host)"
f="$WORK/rows-armed"
{ row rolled-back noop-rolled-back "$POST_A"
  row rolled-back noop-rolled-back "$POST_B"
  row armed noop-armed "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "1" ]] && pass "exit 1 on a post-boundary flag=armed" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"cutover is QUEUED"* ]] && pass "names the queued cutover explicitly" || fail "message not named"

# --- 7b. a broken clock must not sort to the top ---------------------------------------------
# START_TS falls back to the literal `unknown` when date fails, and "unknown" > "2026-…" as a
# string — so a broken-clock row, INCLUDING one from the replaced host, would otherwise count as
# post-boundary evidence toward the PASS.
echo "TEST: #7761 a non-date start_ts is excluded, not sorted above the boundary"
f="$WORK/rows-unknown"
{ row rolled-back noop-rolled-back "unknown"
  row rolled-back noop-rolled-back "unknown"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 — 'unknown' stamps are excluded, not counted" || fail "expected 2, got $rc: $(probe_out)"

# --- 8. host isolation, on BOTH identity fields ---------------------------------------------
echo "TEST: rows from another host do not satisfy the probe (both identity fields required)"
f="$WORK/rows-otherhost"
{ row rolled-back noop-rolled-back "$POST_A" "$GUARD" "web-1" "web-1-prd"
  row rolled-back noop-rolled-back "$POST_B" "$GUARD" "web-1" "web-1-prd"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 when the only rows belong to another host" || fail "expected 2, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"channel_dark"* ]] && pass "reports channel_dark rather than inventing a pass" || fail "reason not named"

echo "TEST: a row matching host_name but NOT host is rejected (#6616 — host_name can lie)"
f="$WORK/rows-spoof"
{ row rolled-back noop-rolled-back "$POST_A" "$GUARD" "web-1" "$HOST_NAME"
  row rolled-back noop-rolled-back "$POST_B" "$GUARD" "web-1" "$HOST_NAME"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "2" ]] && pass "exit 2 when host_name matches but host does not" || fail "expected 2, got $rc: $(probe_out)"

# --- 9. a query failure is TRANSIENT, never a pass ------------------------------------------
echo "TEST: a failing query is TRANSIENT (a read-path outage is not a statement about the host)"
rc="$(run_probe "$(failing_stub)")"
[[ "$rc" == "2" ]] && pass "exit 2 when the query binary fails" || fail "expected 2, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"query_failed"* ]] && pass "names query_failed" || fail "reason not named"

# --- 10. a malformed line must not discard the valid rows after it --------------------------
echo "TEST: one malformed row does not discard the valid rows after it"
f="$WORK/rows-malformed"
{ printf '{"raw":"{trunca\n'
  row rolled-back noop-rolled-back "$POST_A"
  row rolled-back noop-rolled-back "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "0" ]] && pass "exit 0 — the malformed line was skipped, not fatal" || fail "expected 0, got $rc: $(probe_out)"

# --- 11. SILENCE PAST THE DEADLINE IS A FAILURE, NOT 'NOT YET' ------------------------------
# Without this, a permanently bricked scheduler and a rollout nobody has run return the same exit
# code forever, and the sweeper treats both as "check again later".
echo "TEST: #7761 a host silent well past the boundary FAILs rather than TRANSIENTing forever"
f="$WORK/rows-empty2"; : > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$OLD_BOUNDARY")"
[[ "$rc" == "1" ]] && pass "exit 1 when the channel is dark long past the boundary" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"channel_dark_past_deadline"* ]] && pass "names the deadline, not plain silence" || fail "reason not named"

echo "TEST: #7761 too-few markers past the deadline FAILs too"
f="$WORK/rows-one2"
row rolled-back noop-rolled-back "$POST_A" > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$OLD_BOUNDARY")"
[[ "$rc" == "1" ]] && pass "exit 1 on insufficient markers past the deadline" || fail "expected 1, got $rc: $(probe_out)"

# --- 12. a seam refusal on the live host is the #7761 condition occurring --------------------
echo "TEST: #7761 a seam refusal on the live host FAILs (a Doppler name collided with a seam)"
f="$WORK/rows-refusal"
{ row rolled-back noop-rolled-back "$POST_A"
  row rolled-back noop-rolled-back "$POST_B"
  refusal_row; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
[[ "$rc" == "1" ]] && pass "exit 1 when a seam refusal appears on the live host" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"seam_refused"* ]] && pass "names seam_refused" || fail "reason not named"

# --- 13. the Doppler corroboration arm, now reachable ---------------------------------------
# Seamed via FLIP_ROLLOUT_DOPPLER_BIN. Previously this arm was unreachable by construction: the
# suite's correctness depended on an ambient `doppler` happening to FAIL, so its FAIL branch — the
# only exit 1 independent of marker rows — had zero intentional coverage.
echo "TEST: #7761 a Doppler flag that disagrees FAILs fast"
f="$WORK/rows-good2"
{ row rolled-back noop-rolled-back "$POST_A"
  row rolled-back noop-rolled-back "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DOPPLER_BIN="$(doppler_stub armed)")"
[[ "$rc" == "1" ]] && pass "exit 1 when Doppler reads a different flag" || fail "expected 1, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"armed"* ]] && pass "names the disagreeing value" || fail "value not named"

echo "TEST: #7761 a Doppler flag that agrees is reported as corroboration"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DOPPLER_BIN="$(doppler_stub rolled-back)")"
[[ "$rc" == "0" ]] && pass "exit 0 when Doppler agrees" || fail "expected 0, got $rc: $(probe_out)"
[[ "$(probe_out)" == *"doppler corroborates"* ]] && pass "says the read happened" || fail "corroboration not named"

# --- floor ------------------------------------------------------------------------------------
# Every assertion above gates only on FAIL, so deleting a whole block would drop PASS and still
# exit 0. Derived from a green run, never guessed.
MIN_ASSERTIONS=33
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
