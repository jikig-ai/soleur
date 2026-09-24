#!/usr/bin/env bash
# Tests for inngest-cutover-flip-rollout-7761.sh (#7761 Phase 8 probe).
#
# WHY THIS EXISTS. The probe is what authorizes closing a P1 security issue after a production
# destroy-and-recreate of the fleet's sole scheduler. An unexercised probe that always returns
# TRANSIENT is a permanent silent no-op, and one that returns PASS on the wrong evidence closes
# the tracker on a host nobody measured — both are recorded failure modes of this probe's own
# predecessor (see the header of inngest-host-not-serving-7674.sh).
#
# THE FIXTURES MODEL THE WAREHOUSE AS IT IS, NOT AS IT WAS ASSUMED TO BE (2026-09-24). Two facts,
# both measured, and both previously wrong here:
#   * The flip FSM's `message` arrives in the warehouse as a parsed JSON OBJECT inside `raw` (2,743
#     of 2,743 emit_state rows in a 30h sample), not as a JSON string. The old row() built a string,
#     so the suite certified a decoder that dropped every live row. row() now builds the object
#     shape; row_str() keeps the legacy string shape for the decoder's other arm.
#   * Every row carries journald's `_MACHINE_ID`, which is what binds `done` ownership to a
#     machine rather than a hostname that survives a replace.
#
# THE STUB MODELS `raw LIKE '%t%'`, AND THAT IS THE POINT. An earlier revision `cat`-ed a fixture
# and discarded every argument, so it modelled the query's SHAPE and not its SELECTION — and it
# certified 19/19 green over a probe whose grep term matched none of the rows it counts. The stub
# below OR-combines every --grep over each line's decoded raw column text, returns the NEWEST
# --limit lines in chronological order (as betterstack-query.sh does), and refuses a --since shape
# the real reader would answer with a 400. Four self-checks prove each of those can go red.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# FLIP_ROLLOUT_TEST_TARGET: the mutation battery runs this suite against COPIES of the probe, never
# the tracked file.
TARGET="${FLIP_ROLLOUT_TEST_TARGET:-$SCRIPT_DIR/inngest-cutover-flip-rollout-7761.sh}"

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
GUARD="7761"
MID_A="aaaaaaaa11111111aaaaaaaa11111111"
MID_B="bbbbbbbb22222222bbbbbbbb22222222"

# ONE ANCHOR EPOCH. Every timestamp derives from NOW, captured once, so the fresh/deadline arms do
# not depend on how long the suite takes to run. The probe grades silence by AGE: past
# FLIP_ROLLOUT_STALE_AFTER_S a quiet host stops being "not yet" and becomes a FAIL. An absolute
# boundary made this suite's verdicts a function of when it ran — the literal that once lived here
# was green for exactly one hour after it was written, then reached CI red.
#
# OLD_BOUNDARY stays absolute ON PURPOSE: it is the deliberately-stale arm (also older than the
# probe's 7-day non-verdict aging), and a fixed date in the past only gets staler.
NOW="$(date -u +%s)"
_at() { date -u -d "@$(( NOW + $1 ))" +%Y-%m-%dT%H:%M:%SZ; }   # GNU date; CI and the dev host both have it
BOUNDARY="$(_at -300)"     # fresh: well inside STALE_AFTER_S, so silence is TRANSIENT
R_TS="$(_at -270)"         # the op=resume row (flushed-resume-no-reflush)
POST_A="$(_at -240)"       # first post-resume noop-done
POST_B="$(_at -210)"       # second — two are what proves the 30s timer is cycling
POST_C="$(_at -180)"       # a third row (a transition / an armed flag)
PRE_A="$(_at -4800)"       # pre-boundary, and OUTSIDE [AFTER-1h, AFTER]: the replaced host's evidence
PRE_B="$(_at -2100)"
OLD_BOUNDARY="2020-01-01T00:00:00Z"
# The 600-row fixtures (a LIVE page is 500 rows, so the resume row falls off it).
BIG_AFTER="$(_at -2700)"
BIG_R_OFF=-2640
BIG_NOOP_OFF=-2600         # noop i at NOW-2600+4i, i < 600 -> last at NOW-204

# FRESHNESS SELF-CHECK. If someone reinstates an absolute BOUNDARY, this says so by name instead of
# letting unrelated assertions flip verdict for a reason none of them mentions.
_b_age=$(( NOW - $(date -u -d "$BOUNDARY" +%s) ))
if (( _b_age <= 0 || _b_age >= 3600 )); then
  printf 'SETUP FAIL: BOUNDARY is %ss old; it must be inside the 3600s STALE_AFTER_S the suite pins.\n' "$_b_age" >&2
  exit 2
fi

# row <flag> <reason> <start_ts> [guard] [host] [host_name] [mid] [tag]
# The LIVE warehouse shape: `raw` is a JSON string whose object carries `message` as an OBJECT.
row() {
  local g="${4-$GUARD}"
  jq -nc --arg f "$1" --arg r "$2" --arg t "$3" --arg g "$g" --arg h "${5:-$HOST}" \
         --arg hn "${6:-$HOST_NAME}" --arg mid "${7:-$MID_A}" --arg tag "${8:-$TAG}" '
    ({exit_code:0, dbsize:"", reason:$r, flag:$f, start_ts:$t} + (if $g == "" then {} else {guard:$g} end)) as $m
    | {raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$tag, _MACHINE_ID:$mid, message:$m} | tojson)}'
}
# row_str: the LEGACY shape — `message` is a JSON STRING. Still carries _MACHINE_ID (the decoder
# must attach it to string-decoded rows too).
row_str() {
  local g="${4-$GUARD}"
  jq -nc --arg f "$1" --arg r "$2" --arg t "$3" --arg g "$g" --arg h "${5:-$HOST}" \
         --arg hn "${6:-$HOST_NAME}" --arg mid "${7:-$MID_A}" --arg tag "${8:-$TAG}" '
    ({exit_code:0, dbsize:"", reason:$r, flag:$f, start_ts:$t} + (if $g == "" then {} else {guard:$g} end)) as $m
    | {raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$tag, _MACHINE_ID:$mid, message:($m | tojson)} | tojson)}'
}
# msg_row <text> [host] [host_name] [tag] — a raw (non-JSON) message line under the tag.
msg_row() {
  jq -nc --arg m "$1" --arg h "${2:-$HOST}" --arg hn "${3:-$HOST_NAME}" --arg tag "${4:-$TAG}" --arg mid "$MID_A" \
    '{raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$tag, _MACHINE_ID:$mid, message:$m} | tojson)}'
}
refusal_row() { msg_row "SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED count=1 detail=collision"; }
# bulk <n> <first_offset_s> <step_s> <flag> <reason> [mid] [host] [host_name] — ONE jq pass,
# strictly increasing, distinct start_ts.
bulk() {
  jq -nc --argjson n "$1" --argjson s "$(( NOW + $2 ))" --argjson st "$3" --arg f "$4" --arg r "$5" \
         --arg mid "${6:-$MID_A}" --arg h "${7:-$HOST}" --arg hn "${8:-$HOST_NAME}" --arg g "$GUARD" --arg tag "$TAG" '
    range(0; $n) as $i
    | {raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$tag, _MACHINE_ID:$mid,
              message:{exit_code:0, dbsize:"", reason:$r, flag:$f, start_ts:(($s + $st * $i) | todate), guard:$g}} | tojson)}'
}
# The canonical healthy host: the op=resume row, then two stamped noop-done heartbeats.
base_ok() {
  row "done" flushed-resume-no-reflush "$R_TS"
  row "done" noop-done "$POST_A"
  row "done" noop-done "$POST_B"
}

# A query stub modelling betterstack-query.sh: OR over every --grep against the decoded raw text
# (a line that does not decode is matched on its literal text), newest --limit lines kept in
# chronological order, --since/--until shape-gated (anything the real reader cannot parse -> 22).
make_stub() {
  local rows_file="$1" stub
  stub="$(mktemp "$WORK/query-XXXXXXXX.sh")"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
terms=(); since=""; until=""; limit=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --grep) terms+=("$2"); shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --until) until="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    *) shift ;;
  esac
done
# Refuse rather than answer: a stub that returns rows for a request carrying no --grep cannot
# observe the probe forgetting one.
[[ "${#terms[@]}" -gt 0 ]] || { echo "STUB: probe passed no --grep" >&2; exit 64; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "STUB: --limit '$limit' is not a number" >&2; exit 64; }
_shape_ok() {
  [[ "$1" =~ ^[0-9]+[hmd]$ || "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ \
     || "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}
_shape_ok "$since" || { echo "STUB: --since '$since' would be a ClickHouse 400" >&2; exit 22; }
[[ -z "$until" ]] || _shape_ok "$until" || { echo "STUB: --until '$until' would be a ClickHouse 400" >&2; exit 22; }
if [[ -n "${STUB_GREP_LOG:-}" ]]; then printf '%s\n' "${terms[@]}" >> "$STUB_GREP_LOG"; fi
if [[ -n "${STUB_FAIL_ON_TERM:-}" ]]; then
  for t in "${terms[@]}"; do [[ "$t" == "$STUB_FAIL_ON_TERM" ]] && exit 7; done
fi
jq -R -r '. as $l
  | ((try (fromjson | .raw) catch null) | if type == "string" then . else null end) as $r
  | ($r // $l) as $t
  | select(any($ARGS.positional[]; . as $g | $t | contains($g)))
  | $l' --args "${terms[@]}" < "__ROWS__" | tail -n "$limit"
STUBEOF
  sed -i "s|__ROWS__|$rows_file|" "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}

failing_stub() {
  local stub
  stub="$(mktemp "$WORK/queryfail-XXXXXXXX.sh")"
  printf '#!/usr/bin/env bash\nexit 7\n' > "$stub"; chmod +x "$stub"
  printf '%s' "$stub"
}

# A doppler stub, so the corroboration arm is drivable.
doppler_stub() {
  local val="$1" stub
  stub="$(mktemp "$WORK/doppler-XXXXXXXX.sh")"
  { printf '#!/usr/bin/env bash\n'; printf 'printf %%s %s\n' "$val"; } > "$stub"
  chmod +x "$stub"; printf '%s' "$stub"
}

# run_probe <stub> [EXTRA_ENV...] -> echoes the exit code; output lands in $WORK/probe-out.
# The output MUST travel through a file: callers invoke this as `rc="$(run_probe ...)"`, and
# command substitution runs the function in a SUBSHELL, so any variable it assigns is discarded.
# FLIP_ROLLOUT_STALE_AFTER_S is pinned so the fresh/deadline arms do not depend on the default.
run_probe() {
  local stub="$1"; shift
  local rc=0
  env FLIP_ROLLOUT_QUERY_BIN="$stub" \
      FLIP_ROLLOUT_AFTER="$BOUNDARY" \
      FLIP_ROLLOUT_AFTER_FILE="$WORK/nonexistent.after" \
      FLIP_ROLLOUT_DOPPLER_BIN="$WORK/no-such-doppler" \
      FLIP_ROLLOUT_STALE_AFTER_S=3600 \
      BETTERSTACK_QUERY_HOST=stub \
      BETTERSTACK_QUERY_USERNAME=stub \
      BETTERSTACK_QUERY_PASSWORD=stub \
      "$@" bash "$TARGET" > "$WORK/probe-out" 2>&1 || rc=$?
  printf '%s' "$rc"
}
probe_out() { cat "$WORK/probe-out" 2>/dev/null || true; }
# ANCHORED token checks: `reason=<tok>` followed by a non-token character, so `done_not_resumed`
# is never satisfied by `done_not_resumed_past_deadline`.
has_reason() { grep -qE -- "reason=$1([^a-z_]|\$)" "$WORK/probe-out"; }
is_pass() { grep -qE '^PASS: #7761 delivered' "$WORK/probe-out"; }

# expect <id> <rc> <token|PASS> [competing-token...] — exit code, the anchored positive token, and
# the absence of each competing token (and of PASS when a non-PASS is expected).
expect() {
  local id="$1" want="$2" tok="$3"; shift 3
  if [[ "$rc" == "$want" ]]; then pass "$id exit $want"; else fail "$id expected exit $want, got $rc: $(probe_out | tail -4 | tr '\n' ' ')"; fi
  if [[ "$tok" == "PASS" ]]; then
    is_pass && pass "$id prints the PASS line" || fail "$id no PASS line: $(probe_out | tail -3 | tr '\n' ' ')"
  else
    has_reason "$tok" && pass "$id names reason=$tok" || fail "$id reason=$tok not named: $(probe_out | head -3 | tr '\n' ' ')"
    is_pass && fail "$id printed a PASS line on a non-PASS verdict" || pass "$id prints no PASS line"
  fi
  local c
  for c in "$@"; do
    has_reason "$c" && fail "$id also names competing reason=$c" || pass "$id does not name reason=$c"
  done
}

echo "=== inngest-cutover-flip-rollout-7761.sh probe test suite ==="

# =============================================================================================
# STUB SELF-CHECKS — each property the fixtures below depend on, driven directly, able to go red.
# =============================================================================================
echo "TEST: [stub] OR-combines repeated --grep terms"
f="$WORK/rows-selfcheck"
{ row "done" reason-x "$POST_A"; row "done" reason-y "$POST_B"; row "done" reason-z "$POST_C"; } > "$f"
s="$(make_stub "$f")"
n="$(bash "$s" --since 1h --limit 10 --grep '"reason":"reason-x' --grep '"reason":"reason-y' | grep -c . || true)"
[[ "$n" == "2" ]] && pass "stub OR: two terms return rows matching either" || fail "stub OR: expected 2 rows, got $n"

echo "TEST: [stub] --limit keeps the NEWEST N, in chronological order"
f="$WORK/rows-selfcheck5"
{ row "done" r1 "$(_at -60)"; row "done" r2 "$(_at -50)"; row "done" r3 "$(_at -40)"; row "done" r4 "$(_at -30)"; row "done" r5 "$(_at -20)"; } > "$f"
got="$(bash "$(make_stub "$f")" --since 1h --limit 2 --grep "$TAG" | jq -r '.raw | fromjson | .message.reason' | tr '\n' ' ')"
[[ "$got" == "r4 r5 " ]] && pass "stub newest-N: --limit 2 over 5 rows returns r4 then r5" || fail "stub newest-N: got '$got'"

echo "TEST: [stub] --since shape gate (ISO-Z accepted, garbage is the reader's rc 22)"
bash "$s" --since "$BOUNDARY" --limit 1 --grep x >/dev/null 2>&1; src=$?
[[ "$src" == "0" ]] && pass "stub accepts an ISO-Z --since" || fail "stub rejected ISO-Z --since (rc $src)"
bash "$s" --since "last tuesday" --limit 1 --grep x >/dev/null 2>&1; src=$?
[[ "$src" == "22" ]] && pass "stub refuses an unparseable --since with rc 22" || fail "stub accepted garbage --since (rc $src)"

echo "TEST: [stub] a quoted term matches an OBJECT message and not a STRING message"
f="$WORK/rows-selfcheck-q"
{ row "done" quoted-probe "$POST_A"; row_str "done" quoted-probe "$POST_B"; } > "$f"
got="$(bash "$(make_stub "$f")" --since 1h --limit 10 --grep '"reason":"quoted-probe"' | grep -c . || true)"
[[ "$got" == "1" ]] && pass "stub quoted term: object row matches, escaped string row does not" || fail "stub quoted term: expected 1 row, got $got"

echo "TEST: [stub] the 600-row fixture has distinct, in-window, increasing start_ts"
bulk 600 "$BIG_NOOP_OFF" 4 "done" noop-done > "$WORK/bulk-check"
read -r bn bu bmin bmax < <(jq -rs --arg a "$BIG_AFTER" '[.[] | .raw | fromjson | .message.start_ts] as $t
  | "\($t | length) \($t | unique | length) \($t | min) \($t | max)"' "$WORK/bulk-check")
if [[ "$bn" == "600" && "$bu" == "600" && "$bmin" > "$BIG_AFTER" && ! "$bmax" > "$(_at 0)" ]]; then
  pass "bulk fixture: 600 distinct start_ts inside (BIG_AFTER, NOW]"
else
  fail "bulk fixture malformed: n=$bn unique=$bu min=$bmin max=$bmax after=$BIG_AFTER"
fi

# =============================================================================================
# THE BOUNDARY
# =============================================================================================
echo "TEST: an unsupplied boundary is TRANSIENT, not a pass"
f="$WORK/rows-empty"; : > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER=)"
expect "boundary-absent" 2 probe_channel_dark

echo "TEST: an unparseable boundary is TRANSIENT, not silently widened"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="last tuesday")"
expect "boundary-unparseable" 2 boundary_unparseable

echo "TEST: [F32] a SYMLINKED sidecar is refused and its target is never echoed"
printf 'LEAKME\n' > "$WORK/leak-target"
ln -s "$WORK/leak-target" "$WORK/link.after"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_AFTER_FILE="$WORK/link.after")"
expect "F32" 2 sidecar_is_symlink
grep -qF LEAKME "$WORK/probe-out" && fail "F32 the symlink target's content was printed" || pass "F32 the symlink target's content is not printed"

echo "TEST: [F33] an unparseable sidecar prints its LENGTH, never its value"
printf 'LEAKME-not-a-date\n' > "$WORK/bad.after"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_AFTER_FILE="$WORK/bad.after")"
expect "F33" 2 boundary_unparseable
grep -qF LEAKME "$WORK/probe-out" && fail "F33 the sidecar value was printed" || pass "F33 the sidecar value is not printed"
grep -qE 'length=17([^0-9]|$)' "$WORK/probe-out" && pass "F33 prints the value's length" || fail "F33 length not printed: $(probe_out | head -2)"

echo "TEST: [F33b] an oversize sidecar is refused"
printf '%0100d\n' 0 > "$WORK/big.after"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_AFTER_FILE="$WORK/big.after")"
expect "F33b" 2 sidecar_oversize

# =============================================================================================
# THE HAPPY PATH AND THE ANSWER KEY
# =============================================================================================
echo "TEST: [F1] op=resume on this machine, then two stamped noop-done => PASS"
f="$WORK/rows-good"; base_ok > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F1" 0 PASS
grep -qF "owned since ${R_TS}" "$WORK/probe-out" && pass "F1 names the owning resume time" || fail "F1 'owned since ${R_TS}' missing: $(probe_out)"
grep -qE '^PASS: .*seams=overridden:[A-Z_,]*FLIP_ROLLOUT_AFTER' "$WORK/probe-out" \
  && pass "F1 the PASS line discloses the overridden seams" || fail "F1 seams disclosure missing: $(probe_out)"

echo "TEST: the probe greps the syslog TAG for LIVE, and the drift query greps the resume reason"
GREP_SEEN="$WORK/grep-seen"; : > "$GREP_SEEN"
rc="$(run_probe "$(make_stub "$f")" STUB_GREP_LOG="$GREP_SEEN")"
[[ "$rc" == "0" ]] && pass "the probe passes against a grep-logging stub" || fail "expected 0, got $rc: $(probe_out)"
grep -qxF "$TAG" "$GREP_SEEN" && pass "one grep term is the syslog tag '$TAG'" || fail "grep terms [$(tr '\n' ' ' < "$GREP_SEEN")] lack the tag"
grep -qxF '"reason":"flushed-resume-no-reflush' "$GREP_SEEN" && pass "the drift query greps the op=resume reason" \
  || fail "the op=resume reason is not grepped: [$(tr '\n' ' ' < "$GREP_SEEN")]"
grep -qxF '"reason":"noop-done' "$GREP_SEEN" && fail "noop-done is grepped by the drift query (it must stay sparse)" \
  || pass "the steady noop-done heartbeat is NOT a drift term"

echo "TEST: [F1L] live shape — the resume row is off the 500-row LIVE page, only the drift query finds it"
f="$WORK/rows-big"
{ row "done" flushed-resume-no-reflush "$(_at "$BIG_R_OFF")"; bulk 600 "$BIG_NOOP_OFF" 4 "done" noop-done; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$BIG_AFTER")"
expect "F1L" 0 PASS

echo "TEST: [F2] noop-done with no op=resume on this machine is not a PASS (inherited done)"
f="$WORK/rows-noresume"
{ row "done" noop-done "$POST_A"; row "done" noop-done "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F2" 2 done_not_resumed stale_image drift_after_replace
grep -qF "$BOUNDARY" "$WORK/probe-out" && pass "F2 prints the boundary it used" || fail "F2 boundary not printed"
grep -qF 'sidecar' "$WORK/probe-out" && grep -qF 'op=resume' "$WORK/probe-out" \
  && pass "F2 names op=resume and the sidecar move" || fail "F2 remediation not named: $(probe_out)"

echo "TEST: [F2b] an un-resumed done past the deadline FAILs"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$OLD_BOUNDARY")"
expect "F2b" 1 done_not_resumed_past_deadline

echo "TEST: [F3] REORDER — a PRE-boundary resume does not own post-boundary done"
f="$WORK/rows-preresume"
{ row "done" flushed-resume-no-reflush "$PRE_A"; row "done" noop-done "$POST_A"; row "done" noop-done "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F3" 2 done_not_resumed boundary_inside_owning_machine_lifetime

echo "TEST: [F4] REORDER — heartbeats BEFORE the resume do not count as liveness after it"
f="$WORK/rows-noopsfirst"
{ row "done" noop-done "$POST_A"; row "done" noop-done "$POST_B"; row "done" flushed-resume-no-reflush "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F4" 2 insufficient_post_replace_markers done_not_resumed

echo "TEST: a single post-resume marker is TRANSIENT (booted once != timer cycling)"
f="$WORK/rows-one"
{ row "done" flushed-resume-no-reflush "$R_TS"; row "done" noop-done "$POST_A"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "one-marker" 2 insufficient_post_replace_markers

echo "TEST: too-few markers past the deadline FAILs"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$OLD_BOUNDARY")"
expect "one-marker-deadline" 1 insufficient_post_replace_markers_past_deadline

echo "TEST: pre-boundary markers do NOT satisfy the probe (the replaced host's evidence)"
f="$WORK/rows-old"
{ row "done" noop-done "$PRE_A"; row "done" noop-done "$PRE_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "pre-boundary" 2 insufficient_post_replace_markers

echo "TEST: a non-date start_ts is excluded from liveness, not sorted above the boundary"
f="$WORK/rows-unknown"
{ row "done" noop-done "unknown"; row "done" noop-done "unknown"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "unknown-ts" 2 insufficient_post_replace_markers

echo "TEST: [F5] post-boundary rows WITHOUT the guard stamp are a stale image, not a pass"
f="$WORK/rows-oldrev"
{ row "done" flushed-resume-no-reflush "$R_TS" ""; row "done" noop-done "$POST_A" ""; row "done" noop-done "$POST_B" ""; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F5" 1 stale_image done_not_resumed drift_after_replace

echo "TEST: [F16] an UNSTAMPED resume with stamped heartbeats does not own done"
f="$WORK/rows-unstamped-r"
{ row "done" flushed-resume-no-reflush "$R_TS" ""; row "done" noop-done "$POST_A"; row "done" noop-done "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F16" 2 done_not_resumed stale_image drift_after_replace

echo "TEST: [F25] machine binding — a resume on another MACHINE does not own this one's done"
f="$WORK/rows-othermachine"
{ row "done" flushed-resume-no-reflush "$R_TS"
  row "done" noop-done "$POST_A" "$GUARD" "$HOST" "$HOST_NAME" "$MID_B"
  row "done" noop-done "$POST_B" "$GUARD" "$HOST" "$HOST_NAME" "$MID_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F25" 2 done_not_resumed

echo "TEST: [F26] a second resume on the same machine is harmless"
f="$WORK/rows-tworesumes"
{ row "done" flushed-resume-no-reflush "$R_TS"; row "done" noop-done "$POST_A"
  row "done" flushed-resume-no-reflush "$(_at -225)"; row "done" noop-done "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F26" 0 PASS

echo "TEST: [F30] a resume whose start_ts is not a date cannot own done"
f="$WORK/rows-unknown-r"
{ row "done" flushed-resume-no-reflush "unknown"; row "done" noop-done "$POST_A"; row "done" noop-done "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F30" 2 done_not_resumed drift_after_replace

echo "TEST: [F29] a boundary INSIDE the owning machine's lifetime is refused (the sidecar was moved)"
f="$WORK/rows-moved"
{ row "done" noop-done "$(_at -330)"; base_ok; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F29" 2 boundary_inside_owning_machine_lifetime

# =============================================================================================
# DRIFT — any non-exempt FSM row since the boundary
# =============================================================================================
echo "TEST: [F24] a resting 'aborted' after the cutover is drift, not a PASS (was D7)"
f="$WORK/rows-aborted"
{ row aborted noop-aborted "$POST_A"; row aborted noop-aborted "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F24" 1 drift_after_replace flush_path_transition_after_replace

echo "TEST: a resting 'rolled-back' after the cutover is drift"
f="$WORK/rows-rolledback"
{ base_ok; row rolled-back noop-rolled-back "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "rolled-back-rest" 1 drift_after_replace

echo "TEST: [F7] mixed flipping rows — a flag=flipping row is a flush-path FAIL via its FLAG"
# noop-flipping is outside every reason grep and FLUSH_PATH_REASONS, so only the flag grep and the
# flag class can catch it. (Unreachable from today's emitter, which writes only post-run flags —
# the arm is defence in depth.)
f="$WORK/rows-flipping"
{ base_ok; row flipping noop-flipping "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F7" 1 flush_path_transition_after_replace drift_after_replace

echo "TEST: a flag=flushed row is a flush-path FAIL (latch guarantee)"
f="$WORK/rows-flush"
{ base_ok; row flushed flip-flushed "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "flushed-flag" 1 flush_path_transition_after_replace
grep -qF 'latch guarantee is broken' "$WORK/probe-out" && pass "flushed-flag names the latch guarantee" || fail "latch guarantee not named"

echo "TEST: [F8] a post-boundary flip-complete is a flush-path FAIL naming it"
f="$WORK/rows-flipcomplete"
{ base_ok; row "done" flip-complete "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F8" 1 flush_path_transition_after_replace
grep -qE 'reason=flip-complete' "$WORK/probe-out" && pass "F8 prints the flip-complete row" || fail "F8 row not printed: $(probe_out)"

echo "TEST: [F9] a finding AFTER a compliant row is still found (finding newest in page order)"
f="$WORK/rows-f9a"
{ base_ok; row aborted refuse-rearm-after-done "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F9a" 1 drift_after_replace
echo "TEST: [F9] ... and with the finding OLDEST in page order"
f="$WORK/rows-f9b"
{ row aborted refuse-rearm-after-done "$(_at -290)"; base_ok; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F9b" 1 drift_after_replace

echo "TEST: [F10] horizon — an early flip-complete 600 heartbeats back is still found"
f="$WORK/rows-f10"
{ row "done" flip-complete "$(_at -2680)"; row "done" flushed-resume-no-reflush "$(_at "$BIG_R_OFF")"
  bulk 600 "$BIG_NOOP_OFF" 4 "done" noop-done; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$BIG_AFTER")"
expect "F10" 1 flush_path_transition_after_replace

echo "TEST: [F11] direct-write drift — early noop-aborted rows 600 heartbeats back are found"
f="$WORK/rows-f11"
{ row "done" flushed-resume-no-reflush "$(_at "$BIG_R_OFF")"; bulk 3 -2630 5 aborted noop-aborted
  bulk 600 "$BIG_NOOP_OFF" 4 "done" noop-done; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$BIG_AFTER")"
expect "F11" 1 drift_after_replace

echo "TEST: [F21] a flush-path row outranks stale_image"
f="$WORK/rows-f21"
{ row "done" flushed-resume-no-reflush "$R_TS" ""; row "done" noop-done "$POST_A" ""; row "done" noop-done "$POST_B" ""
  row "done" flip-complete "$POST_C" ""; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F21" 1 flush_path_transition_after_replace stale_image

echo "TEST: [F31] a non-enum flag embedded in a finding is never printed"
f="$WORK/rows-f31"
{ base_ok; row s3cr3t-value noop-unset "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F31" 1 drift_after_replace
grep -qF 's3cr3t-value' "$WORK/probe-out" && fail "F31 the raw flag value was printed" || pass "F31 the raw flag value is not printed"

echo "TEST: [F35] a drift row with a non-date start_ts is a finding, not dropped"
f="$WORK/rows-f35"
{ base_ok; row aborted noop-aborted "unknown"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F35" 1 drift_after_replace

echo "TEST: [F37] 25 findings print 20 rows, a (+5 more) line, and the FAIL line LAST"
f="$WORK/rows-f37"
{ base_ok; bulk 25 -140 1 aborted refuse-rearm-after-done; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F37" 1 drift_after_replace
_n="$(grep -cE '^ +flag=' "$WORK/probe-out" || true)"
[[ "$_n" == "20" ]] && pass "F37 prints exactly 20 finding rows" || fail "F37 printed $_n finding rows"
grep -qF '(+5 more)' "$WORK/probe-out" && pass "F37 names the 5 unprinted rows" || fail "F37 no (+5 more) line"
[[ "$(tail -n 1 "$WORK/probe-out")" == "FAIL: reason="* ]] && pass "F37 the FAIL line is the last line" \
  || fail "F37 last line is '$(tail -n 1 "$WORK/probe-out")'"

echo "TEST: [F28] a same-host LUKS-cutover FSM row is not flip drift (tag isolation)"
f="$WORK/rows-f28"
{ base_ok; row aborted noop-aborted "$POST_C" "$GUARD" "$HOST" "$HOST_NAME" "$MID_A" inngest-luks-cutover; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F28" 0 PASS

echo "TEST: [F14] must-PASS, non-canonical: pre-boundary flip-complete, Doppler stderr rows, a web-1 resume"
f="$WORK/rows-f14"
{ row "done" flip-complete "$PRE_A"
  msg_row "Doppler Error: unable to fetch secrets (retrying)"
  row "done" flushed-resume-no-reflush "$R_TS" "$GUARD" web-1 web-1-prd "$MID_B"
  base_ok
  msg_row "Doppler Error: request timed out"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F14" 0 PASS

# =============================================================================================
# TRUNCATION AND THE READ PATH
# =============================================================================================
echo "TEST: [F18] a FULL drift page with no finding is TRANSIENT, never an absence conclusion"
f="$WORK/rows-f18"
{ row "done" flushed-resume-no-reflush "$R_TS"; row "done" flushed-resume-no-reflush "$(_at -255)"
  row "done" noop-done "$POST_A"; row "done" noop-done "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DRIFT_LIMIT=1)"
expect "F18" 2 drift_query_truncated done_not_resumed stale_image

echo "TEST: [F34] the same non-verdict against a supplied boundary older than 7 days is CANNOT ESTABLISH (exit 3)"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DRIFT_LIMIT=1 FLIP_ROLLOUT_AFTER="$OLD_BOUNDARY")"
expect "F34" 3 drift_query_truncated

echo "TEST: [F23] page-full is counted on the RAW page, before the host filter"
f="$WORK/rows-f23"
{ row aborted refuse-rearm-after-done "$(_at -295)"; base_ok
  row aborted refuse-rearm-after-done "$(_at -200)" "$GUARD" web-1 web-1-prd "$MID_B"
  row aborted refuse-rearm-after-done "$(_at -190)" "$GUARD" web-1 web-1-prd "$MID_B"
  row aborted refuse-rearm-after-done "$(_at -185)" "$GUARD" web-1 web-1-prd "$MID_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DRIFT_LIMIT=3)"
expect "F23" 2 drift_query_truncated done_not_resumed

echo "TEST: a malformed DRIFT_LIMIT (leading zero) is refused, not silently used"
f="$WORK/rows-good"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DRIFT_LIMIT=08)"
expect "drift-limit-shape" 2 drift_limit_invalid

echo "TEST: [F36] a LIVE page full of FOREIGN rows is channel_dark (sentinel stripped first)"
f="$WORK/rows-f36"
bulk 500 -1000 1 "done" noop-done "$MID_B" web-1 web-1-prd > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F36" 2 channel_dark insufficient_post_replace_markers

echo "TEST: [F27] a failed refusal query is TRANSIENT, never a PASS"
f="$WORK/rows-good"
rc="$(run_probe "$(make_stub "$f")" STUB_FAIL_ON_TERM=SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED)"
expect "F27" 2 refusals_query_failed

echo "TEST: a failing query is TRANSIENT (a read-path outage is not a statement about the host)"
rc="$(run_probe "$(failing_stub)")"
expect "query-failed" 2 query_failed

echo "TEST: one malformed row does not discard the valid rows after it"
f="$WORK/rows-malformed"
# The malformed line carries the tag in its LITERAL text, so the LIKE-faithful stub still returns it.
{ printf '{"raw":"{\\"SYSLOG_IDENTIFIER\\":\\"inngest-cutover-flip\\",trunca\n'; base_ok; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "malformed-line" 0 PASS

echo "TEST: [F12b] string-shaped JSON heartbeats decode and carry _mid"
f="$WORK/rows-f12b"
{ row "done" flushed-resume-no-reflush "$R_TS"; row_str "done" noop-done "$POST_A"; row_str "done" noop-done "$POST_B"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "F12b" 0 PASS

# =============================================================================================
# HOST ISOLATION, SILENCE, SEAM REFUSALS
# =============================================================================================
echo "TEST: rows from another host do not satisfy the probe (both identity fields required)"
f="$WORK/rows-otherhost"
{ row "done" flushed-resume-no-reflush "$R_TS" "$GUARD" web-1 web-1-prd
  row "done" noop-done "$POST_A" "$GUARD" web-1 web-1-prd; row "done" noop-done "$POST_B" "$GUARD" web-1 web-1-prd; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "other-host" 2 channel_dark

echo "TEST: a row matching host_name but NOT host is rejected (#6616 — host_name can lie)"
f="$WORK/rows-spoof"
{ row "done" flushed-resume-no-reflush "$R_TS" "$GUARD" web-1 "$HOST_NAME"
  row "done" noop-done "$POST_A" "$GUARD" web-1 "$HOST_NAME"; row "done" noop-done "$POST_B" "$GUARD" web-1 "$HOST_NAME"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "spoofed-host" 2 channel_dark

echo "TEST: a host silent well past the boundary FAILs rather than TRANSIENTing forever"
f="$WORK/rows-empty2"; : > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$OLD_BOUNDARY")"
expect "silent-deadline" 1 channel_dark_past_deadline

echo "TEST: a seam refusal on the live host FAILs (a Doppler name collided with a seam)"
f="$WORK/rows-refusal"
{ base_ok; refusal_row; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "seam-refusal" 1 seam_refused

echo "TEST: a post-boundary flag=armed FAILs (a cutover is queued, not a quiet host)"
# Unreachable from today's emitter (it never writes `armed` into a row's flag); kept as defence
# in depth, uncapped.
f="$WORK/rows-armed"
{ base_ok; row armed noop-armed "$POST_C"; } > "$f"
rc="$(run_probe "$(make_stub "$f")")"
expect "armed" 1 cutover_armed
grep -qF 'cutover is QUEUED' "$WORK/probe-out" && pass "armed names the queued cutover" || fail "queued cutover not named"

# =============================================================================================
# THE DOPPLER ARM
# =============================================================================================
echo "TEST: [F13] a Doppler flag of 'done' is reported as corroboration"
f="$WORK/rows-good"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DOPPLER_BIN="$(doppler_stub "done")")"
expect "F13" 0 PASS
grep -qF 'doppler corroborates: done' "$WORK/probe-out" && pass "F13 says the read happened" || fail "F13 corroboration not named"

echo "TEST: [F13a] a Doppler flag other than 'done' blocks a PASS"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DOPPLER_BIN="$(doppler_stub aborted)")"
expect "F13a" 1 doppler_flag_not_done

echo "TEST: a Doppler flag of 'armed' FAILs fast and names it"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_DOPPLER_BIN="$(doppler_stub armed)")"
expect "doppler-armed" 1 doppler_flag_not_done
grep -qF "'armed'" "$WORK/probe-out" && pass "doppler-armed names the disagreeing value" || fail "value not named"

# =============================================================================================
# #7695 — the DERIVED boundary arm (the fallback if the committed sidecar is ever removed)
# =============================================================================================
PIN_DIGEST="sha256:$(printf 'a%.0s' {1..64})"
PIN_FIXTURE="$WORK/pin-fixture.yml"
printf '    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.9@%s\n' "$PIN_DIGEST" > "$PIN_FIXTURE"

# The HOURLY host probe row: the timestamp lives ONLY on the outer object as a ClickHouse-shaped
# `dt` (space-separated, no T, no Z), and the message is a flat key=value string.
probe_row() { # probe_row <dt> <image_ref> [host] [host_name]
  local dt="$1" ref="$2" h="${3:-$HOST}" hn="${4:-$HOST_NAME}" inner
  inner="$(jq -nc --arg h "$h" --arg hn "$hn" --arg r "$ref" \
          '{host:$h, host_name:$hn, SYSLOG_IDENTIFIER:"inngest-server-probe",
            message:("SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active image_ref=" + $r + " cutover_flag=done")}')"
  jq -nc --arg dt "$dt" --arg raw "$inner" '{dt:$dt, raw:$raw}'
}
_ck() { date -u -d "@$(( NOW + $1 ))" '+%Y-%m-%d %H:%M:%S'; }   # the ClickHouse `dt` shape

echo "TEST: #7695 the boundary derives from a ZOT-prefixed image_ref (digest-only matching)"
f="$WORK/rows-derive-ok"
{ probe_row "$(_ck -4200)" "10.0.1.30:5000/jikig-ai/soleur-inngest-bootstrap:v9.9.9@${PIN_DIGEST}"
  row "done" flushed-resume-no-reflush "$(_at -2700)"
  row "done" noop-done "$(_at -2400)"
  row "done" noop-done "$(_at -1800)"; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_PIN_FILE="$PIN_FIXTURE")"
expect "derive-ok" 0 PASS
grep -qF 'boundary DERIVED from telemetry' "$WORK/probe-out" && pass "announces the derived provenance" || fail "provenance not announced: $(probe_out)"
has_reason boundary_unparseable && fail "the ClickHouse dt tripped the validator" || pass "the ClickHouse dt normalised through the validator"

echo "TEST: #7695 a foreign host's probe row does not supply the boundary (both identity fields)"
f="$WORK/rows-derive-foreign"
{ probe_row "$(_ck -4200)" "ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.9@${PIN_DIGEST}" "web-1" "soleur-web-prd"
  row "done" noop-done "$(_at -2400)"; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_PIN_FILE="$PIN_FIXTURE")"
expect "derive-foreign" 2 probe_channel_dark

# THE PROVENANCE CONTROL PAIR: identical fixture, only the boundary's PROVENANCE differs. The
# scenario is a host alive and polling but emitting NO guard stamp.
_mk_stale() {
  { probe_row "$(_ck -4200)" "ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.9@${PIN_DIGEST}"
    row "done" flushed-resume-no-reflush "$(_at -2700)" ""
    row "done" noop-done "$(_at -2400)" ""
    row "done" noop-done "$(_at -1800)" ""; } > "$1"
}
echo "TEST: #7695 a DERIVED boundary is capped at TRANSIENT where it would have said stale_image"
f="$WORK/rows-cap"; _mk_stale "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_PIN_FILE="$PIN_FIXTURE")"
expect "derive-cap" 2 derived_boundary_stale_supply_authoritative_boundary
grep -qF 'would have reported stale_image' "$WORK/probe-out" && pass "still says which verdict was suppressed" || fail "suppressed verdict not reported: $(probe_out)"

echo "TEST: #7695 CONTROL — the SAME fixture with a SUPPLIED boundary still FAILs stale_image"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$(_at -4200)" FLIP_ROLLOUT_PIN_FILE="$PIN_FIXTURE")"
expect "derive-control" 1 stale_image

echo "TEST: #7695 FLIP_ROLLOUT_AFTER takes precedence over the derived boundary"
f="$WORK/rows-derive-ok"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER="$BOUNDARY" FLIP_ROLLOUT_PIN_FILE="$PIN_FIXTURE")"
grep -qF 'boundary DERIVED from telemetry' "$WORK/probe-out" && fail "derived despite a supplied boundary: $(probe_out)" \
  || pass "no derivation ran when a boundary was supplied"

echo "TEST: #7695 an 'armed' row FAILs even under a DERIVED boundary (uncapped)"
f="$WORK/rows-armed-derived"
{ probe_row "$(_ck -4200)" "ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.9@${PIN_DIGEST}"
  row "done" noop-done "$(_at -2400)"
  row armed armed "$(_at -1200)"; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_PIN_FILE="$PIN_FIXTURE")"
expect "derive-armed" 1 cutover_armed
grep -qF 'FLUSHALL' "$WORK/probe-out" && pass "names the FLUSHALL consequence" || fail "consequence not named"

echo "TEST: #7695 T1 — rows exist for this host but carry a DIFFERENT digest"
f="$WORK/rows-wrong-digest"
{ probe_row "$(_ck -4200)" "10.0.1.30:5000/jikig-ai/soleur-inngest-bootstrap:v1.1.25@sha256:$(printf 'b%.0s' {1..64})"
  row "done" noop-done "$(_at -2400)"; } > "$f"
rc="$(run_probe "$(make_stub "$f")" FLIP_ROLLOUT_AFTER= FLIP_ROLLOUT_PIN_FILE="$PIN_FIXTURE")"
expect "derive-T1" 2 boundary_underivable probe_channel_dark
grep -qF 'observed=sha256:bbbb' "$WORK/probe-out" && pass "reports the OBSERVED digest alongside the pinned one" || fail "observed digest not reported"

# =============================================================================================
# STATIC PINS
# =============================================================================================
echo "TEST: #7695 no jq filter uses the jq-1.8-only \`? as \$var\` form"
_jq_as_hits="$(grep -nE '\? as \$' "$TARGET" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
[[ -z "$_jq_as_hits" ]] && pass "no bare '? as \$' in the probe (jq 1.7 would fail to COMPILE it)" \
  || fail "jq-1.8-only '? as \$' form found — parenthesise it: $_jq_as_hits"

echo "TEST: the answer key is inline — no env override reaches the guard, the flag, or the threshold"
_ak="$(grep -nE '^[^#]*FLIP_ROLLOUT_(EXPECTED_GUARD|EXPECTED_FLAG|MIN_MARKERS|TERMINAL)' "$TARGET" || true)"
[[ -z "$_ak" ]] && pass "no FLIP_ROLLOUT_* override for an answer-key member" || fail "env-supplied answer key: $_ak"
_dead="$(grep -cE '^[^#]*(TERMINAL_SAFE_FLAGS|EXPECTED_FLAG=|DRIFT_WINDOW=)' "$TARGET" || true)"
[[ "$_dead" == "0" ]] && pass "the pre-cutover key (TERMINAL_SAFE_FLAGS / EXPECTED_FLAG / DRIFT_WINDOW) is gone" \
  || fail "pre-cutover answer key still present ($_dead lines)"

# VERDICT-TABLE PARITY. Every reason token the probe can print must appear in the header's verdict
# table. Tokens come from CODE lines only (the first word of verdict_fail/non_verdict's reason, and
# `reason=<tok>` on echo lines); the table is read only from the leading comment block, so the
# table cannot satisfy itself and a code comment cannot satisfy the table.
verdict_parity_missing() { # <probe-file> -> prints missing tokens
  local file="$1" header codes tok
  header="$(awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$file")"
  codes="$( { grep -vE '^[[:space:]]*#' "$file" | grep -oE '(verdict_fail|non_verdict) "[a-z_]+' | awk '{ print substr($2, 2) }'
              grep -vE '^[[:space:]]*#' "$file" | grep -E 'echo "(TRANSIENT|FAIL)' | grep -oE 'reason=[a-z_]+' | cut -d= -f2; } | sort -u)"
  [[ -n "$codes" ]] || { echo "__NO_CODE_TOKENS__"; return; }
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    grep -qE "(^|[^a-z_])${tok}([^a-z_]|\$)" <<<"$header" || printf '%s ' "$tok"
  done <<<"$codes"
}
echo "TEST: every reason token the probe prints is in its header verdict table"
_vm="$(verdict_parity_missing "$TARGET")"
[[ -z "$_vm" ]] && pass "verdict table covers every printed reason token" || fail "verdict table is missing: $_vm"
_vn="$(grep -vE '^[[:space:]]*#' "$TARGET" | grep -oE '(verdict_fail|non_verdict) "[a-z_]+' | sort -u | grep -c . || true)"
(( _vn >= 8 )) && pass "verdict parity extraction is non-vacuous ($_vn verdict_fail/non_verdict tokens)" \
  || fail "verdict parity extracted only $_vn verdict_fail/non_verdict tokens"
echo "TEST: verdict-table parity NEGATIVE control — deleting a table row reds"
cp "$TARGET" "$WORK/probe-notable.sh"
sed -i -E '0,/^#.*done_not_resumed_past_deadline/{/^#.*done_not_resumed_past_deadline/d}' "$WORK/probe-notable.sh"
_vneg="$(verdict_parity_missing "$WORK/probe-notable.sh")"
[[ "$_vneg" == *done_not_resumed_past_deadline* ]] && pass "a table without done_not_resumed_past_deadline is caught" \
  || fail "negative control did not red (missing='$_vneg')"

# --- floor ------------------------------------------------------------------------------------
# Every assertion above gates only on FAIL, so deleting a whole block would drop PASS and still
# exit 0. Derived from a green run, never guessed: 223 measured on 2026-09-24 (#7761 rewrite).
MIN_ASSERTIONS=223
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
