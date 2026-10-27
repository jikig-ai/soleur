#!/usr/bin/env bash
# Fixture suite for the #10972 follow-through probe (orphan-sweeps-relook-10972.sh).
#
# The probe closes its tracker on exit 0, so every branch that can end in 0 or 1 has a row, and each row
# is there because a named mutant of the probe survives without it. `curl` and `date` are PATH shims: the
# curl shim accepts exactly ONE argv (an exact-argv allowlist, bearer compared to the token) and logs every
# refusal, and run_probe asserts that log is empty after every run, so a changed flag, a wrong URL or a token
# in argv reads as a failed row instead of being answered with a fixture. Every fixture row and body carries
# a leak marker, and run_probe asserts after every run that neither the marker nor the token reached the output.
#
# RETIREMENT: with the probe — delete this suite, its run_suite line in scripts/test-all.sh, its rows in
# scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv (scripts/regenerate-shard-manifest.py
# --incremental --write) and the follow-through label on #10972.
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
set -uo pipefail

# One scratch root; TMPDIR points into it so every mktemp (this file's and the probe's) lands inside it.
TMP_ROOT=$(mktemp -d -t ft10972root.XXXXXXXX) || {
  echo "FATAL: could not create scratch root (is the filesystem full?)" >&2
  exit 1
}
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || {
  echo "FATAL: scratch root is not a plain absolute directory: '$TMP_ROOT'" >&2
  exit 1
}
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM
export TMPDIR="$TMP_ROOT"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/orphan-sweeps-relook-10972.sh"
[[ -f "$PROBE" ]] || { echo "FATAL: probe not found: $PROBE" >&2; exit 1; }

SHIMS="$TMP_ROOT/shims"
mkdir -p "$SHIMS"
REAL_DATE="$(command -v date)"
REAL_JQ="$(command -v jq)"
REAL_BASH="$(command -v bash)"

# The one request the probe may send. Owned by the suite (an independent oracle), not read from the probe.
URL_EXPECTED="https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-orphan-sweeps/checkins/?per_page=100"

# --- curl shim -------------------------------------------------------------------------------------
# Replays $FT_FIXTURE with $FT_STATUS, logs one line per call to $FT_CALLS, and REFUSES (exit 64, logged to
# $FT_REFUSE) any argv that is not exactly the expected one or any bearer that is not $FT_TOKEN.
cat > "$SHIMS/curl" <<'SHIM'
#!/usr/bin/env bash
printf 'call\n' >> "$FT_CALLS"
refuse() { printf '%s\n' "$1" >> "$FT_REFUSE"; echo "shim: $1" >&2; exit 64; }
expected=(--disable --noproxy '*' --proto '=https' --max-time 30 --max-filesize 5242880 -sS
  -w '\nHTTP_STATUS:%{http_code}' -H 'Accept: application/json' --config - "$FT_URL")
args=("$@")
[[ ${#args[@]} -eq ${#expected[@]} ]] || refuse "argc ${#args[@]} != ${#expected[@]}"
for i in "${!expected[@]}"; do
  [[ "${args[$i]}" == "${expected[$i]}" ]] || refuse "argv[$i] differs from the allowlist"
done
cfg="$(cat)"
[[ "$cfg" == "header = \"Authorization: Bearer ${FT_TOKEN}\"" ]] || refuse "bearer differs from the token"
[[ -z "${FT_CURL_RC:-}" || "$FT_CURL_RC" == 0 ]] || exit "$FT_CURL_RC"
cat "$FT_FIXTURE"
printf '\nHTTP_STATUS:%s' "${FT_STATUS:-200}"
SHIM
chmod +x "$SHIMS/curl"

# --- date shim: only `date -u +%s` is faked ("now"); everything else is the real date -------------
cat > "$SHIMS/date" <<SHIM
#!/usr/bin/env bash
if [[ "\$*" == "-u +%s" && -n "\${FT_NOW:-}" ]]; then printf '%s\n' "\$FT_NOW"; exit 0; fi
exec "$REAL_DATE" "\$@"
SHIM
chmod +x "$SHIMS/date"

fails=0
passes=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }
check() { # check <actual> <expected> <label>
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 — expected exit $2, got $1"; fi
}
absent() { # absent <needle> <haystack-file> <label>
  if grep -qF -- "$1" "$2"; then fail "$3 — found forbidden text"; else pass "$3"; fi
}
present() { # present <fixed-string> <haystack-file> <label>
  if grep -qF -- "$1" "$2"; then pass "$3"; else fail "$3 — missing '$1'"; fi
}
calls_are() { # calls_are <expected-request-count> <label>   (reads NCALLS from the last run_probe)
  if [[ "$NCALLS" == "$1" ]]; then pass "$2"; else fail "$2 (got $NCALLS requests)"; fi
}

# finish: the suite's final verdict, driven in-process by the instrument self-test below. The floor literal
# and its `total` assignment sit directly above the `if`, the shape the repo's vacuity meta-guard slices.
finish() {
  echo
  echo "executed assertions: $((passes + fails)) (pass=$passes fail=$fails)"
  EXPECTED_MIN=189
  total=$((passes + fails))
  if [[ "$total" -lt "$EXPECTED_MIN" ]]; then
    printf 'FATAL: only %s assertions executed (floor %s): the suite dispatched too little\n' "$total" "$EXPECTED_MIN" >&2
    return 1
  fi
  [[ "$fails" -eq 0 ]] || return 1
  return 0
}

# Accepted survivor (unobservable by construction): deleting the nested-gate `if` itself leaves nothing in this
# file able to notice; every other mutation of the nested gate (wrong path, no injected failure) is pinned.
# --- instrument self-test (every verdict-owning helper must be able to say NO) --------------------
# Each helper is driven in a subshell with a deliberately wrong expectation; its failure counter must move.
# Reported with printf + exit, never through the helpers under test.
selftest_fail() { printf 'FATAL: instrument self-test: %s\n' "$1" >&2; exit 1; }
_st="$TMP_ROOT/selftest"; printf 'present-text\n' > "$_st"
(fails=0; passes=0; pass "x" >/dev/null; [[ $passes -eq 1 && $fails -eq 0 ]]) || selftest_fail "pass() did not move passes"
(fails=0; passes=0; fail "x" >/dev/null; [[ $fails -eq 1 && $passes -eq 0 ]]) || selftest_fail "fail() did not move fails"
(fails=0; passes=0; check 1 2 "x" >/dev/null; [[ $fails -eq 1 && $passes -eq 0 ]]) || selftest_fail "check() accepted a mismatch"
(fails=0; passes=0; check 2 2 "x" >/dev/null; [[ $fails -eq 0 && $passes -eq 1 ]]) || selftest_fail "check() rejected a match"
(fails=0; passes=0; present "no-such-text" "$_st" "x" >/dev/null; [[ $fails -eq 1 && $passes -eq 0 ]]) || selftest_fail "present() accepted a missing needle"
(fails=0; passes=0; absent "present-text" "$_st" "x" >/dev/null; [[ $fails -eq 1 && $passes -eq 0 ]]) || selftest_fail "absent() accepted a present needle"
(fails=0; passes=0; NCALLS=3; calls_are 1 "x" >/dev/null; [[ $fails -eq 1 && $passes -eq 0 ]]) || selftest_fail "calls_are() accepted a wrong count"
# the final verdict: fails > 0 must fail, a short run must fail, a clean full run must pass
if (passes=1000; fails=1; finish >/dev/null 2>&1); then selftest_fail "finish() passed with a failed assertion"; fi
if (passes=0; fails=0; finish >/dev/null 2>&1); then selftest_fail "finish() passed with zero assertions"; fi
(passes=1000; fails=0; finish >/dev/null 2>&1) || selftest_fail "finish() rejected a clean run"

# --- fixtures ------------------------------------------------------------------------------------
WIN_START=1792994400 # 2026-10-26T06:00:00Z
WIN_END=1794204000   # 2026-11-09T06:00:00Z
SLOT=43200
TOKEN="synthetic-token-0123456789abcdef"
LEAK="LEAKMARK-7f3a91c2"
NOW_AFTER=$((WIN_END + 3600))  # 07:00Z on the window-close day
NOW_BEFORE=$((WIN_END - 60))

iso() { "$REAL_DATE" -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# row <status> <epoch> [timestamp-field]: one check-in row (carries the leak marker)
row() {
  "$REAL_JQ" -n -c --arg st "$1" --arg ts "$(iso "$2")" --arg lk "$LEAK" --arg f "${3:-dateAdded}" \
    '{status:$st, leak:$lk} + {($f):$ts}'
}
# slot_rows <count> [first-offset-seconds] [last-offset-seconds]: ok rows for slots 0..count-1 (fractional
# seconds on every other row, Sentry's own shape)
slot_rows() {
  "$REAL_JQ" -n -c --argjson n "$1" --argjson s "$WIN_START" --argjson sl "$SLOT" --arg lk "$LEAK" \
    --argjson fo "${2:-40}" --argjson lo "${3:-40}" '
    [range(0; $n) | . as $i | { status: "ok", leak: $lk,
       dateAdded: (($s + $i * $sl + (if $i == 0 then $fo elif $i == $n - 1 then $lo else 40 end))
                   | strftime("%Y-%m-%dT%H:%M:%S") + (if $i % 2 == 0 then ".123456Z" else "Z" end)) }]'
}
# padded <extra> [first-offset]: 28 slot rows plus <extra> more ok rows inside already-covered buckets
padded() {
  "$REAL_JQ" -n -c --argjson e "$1" --argjson s "$WIN_START" --arg lk "$LEAK" \
    --argjson base "$(slot_rows 28 "${2:-40}")" \
    '$base + [range(0; $e) | {status:"ok", leak:$lk, dateAdded: (($s + (. + 1) * 3600 + 100) | strftime("%Y-%m-%dT%H:%M:%SZ"))}]'
}
# with <rows-json> <extra-row-json>...: extra rows prepended (order is irrelevant to the probe)
with() {
  local base="$1"; shift
  local extra; extra="$(printf '%s\n' "$@" | "$REAL_JQ" -s -c '.')"
  "$REAL_JQ" -n -c --argjson a "$extra" --argjson b "$base" '$a + $b'
}

CALLS="$TMP_ROOT/calls"
REFUSE="$TMP_ROOT/refuse"
OUT="$TMP_ROOT/out"
FIX="$TMP_ROOT/fixture"

# run_probe <fixture-text> <status> <now> [extra env assignments...]  → exit code in $RC, requests in $NCALLS.
# After EVERY run: the curl shim refused nothing, and neither the leak marker nor the token reached the output.
run_probe() {
  local body="$1" status="$2" now="$3"; shift 3
  printf '%s' "$body" > "$FIX"
  : > "$CALLS"; : > "$REFUSE"
  env -i PATH="$SHIMS:$PATH" HOME="${HOME:-/}" TMPDIR="$TMPDIR" \
    FT_FIXTURE="$FIX" FT_STATUS="$status" FT_CALLS="$CALLS" FT_REFUSE="$REFUSE" FT_NOW="$now" \
    FT_URL="$URL_EXPECTED" FT_TOKEN="$TOKEN" SENTRY_ACTIONS_RO_TOKEN="$TOKEN" "$@" \
    "$REAL_BASH" "$PROBE" > "$OUT" 2>&1
  RC=$?
  NCALLS=$(wc -l < "$CALLS" | tr -d ' ')
  # the token of THIS run (an override replaces the default), checked as well as the default
  tok_leak=0
  for a in "$@"; do
    case "$a" in SENTRY_ACTIONS_RO_TOKEN=?*) grep -qF -- "${a#SENTRY_ACTIONS_RO_TOKEN=}" "$OUT" && tok_leak=1 ;; esac
  done
  if [[ -s "$REFUSE" || "$tok_leak" -ne 0 ]] || grep -qF -- "$LEAK" "$OUT" || grep -qF -- "$TOKEN" "$OUT"; then
    fail "universal: shim refusal, body leak or token in output (rc=$RC; refusals: $(tr '\n' ';' < "$REFUSE"))"
  else
    pass "universal: no shim refusal, no body leak, no token in output (rc=$RC)"
  fi
}

# main_rows: every verdict row. A function so the nested gate self-test below can skip them.
main_rows() {
CLEAN="$(slot_rows 28)"
B_T3=$((WIN_START + 3 * SLOT + 60)); B_T9=$((WIN_START + 9 * SLOT + 60))

echo "== verdict rows"

run_probe "$CLEAN" 200 "$NOW_AFTER"
check "$RC" 0 "1  clean fixture: all 28 slots have an ok row"
present "PASS" "$OUT" "1b clean run prints a PASS line"
present "were not measured" "$OUT" "1c output states what was not measured"
calls_are 1 "1d exactly one request sent"
present "counts in window: ok=28" "$OUT" "1e the per-status counts are printed"

run_probe "[]" 200 "$NOW_AFTER"
check "$RC" 3 "2  empty array (zero rows) is exit 3, never 0"
present "0 check-in rows returned" "$OUT" "2b the zero-row read names itself (not only the coverage check)"

run_probe "$(with "$CLEAN" "$(row missed $B_T3)")" 200 "$NOW_AFTER"
check "$RC" 1 "3  one missed row among 28 ok rows"

run_probe "$(with "$CLEAN" "$(row timeout $B_T3)" "$(row error $B_T9)")" 200 "$NOW_AFTER"
check "$RC" 1 "4  timeout and a later error row"
present "  - timeout @ $(iso $B_T3)" "$OUT" "4b the timeout row is itemised (not only named in the header)"
present "  - error @ $(iso $B_T9)" "$OUT" "4c the later bad row is itemised too (no stop at the first)"

run_probe "$(with "$CLEAN" "$(row timed_out $B_T3)")" 200 "$NOW_AFTER"
check "$RC" 1 "4e a timed_out row is a bad row"
present "  - timeout @ $(iso $B_T3)" "$OUT" "4f timed_out is printed as the closed token timeout"
absent "timed_out" "$OUT" "4g the raw spelling is never printed"

run_probe "$(with "$CLEAN" "$(row error $((WIN_START + 11 * SLOT + 60)))")" 200 "$NOW_AFTER"
check "$RC" 1 "5  one error row among otherwise ok rows"

run_probe "$(with "$CLEAN" "$(row missed $((WIN_END + 40)))")" 200 "$NOW_AFTER"
check "$RC" 0 "6  a bad row dated after the pinned end is ignored"
run_probe "$(with "$CLEAN" "$(row missed "$WIN_END")")" 200 "$NOW_AFTER"
check "$RC" 0 "6b a bad row exactly AT the pinned end is outside the window (end is exclusive)"
run_probe "$(with "$CLEAN" "$(row missed "$WIN_START")")" 200 "$NOW_AFTER"
check "$RC" 1 "6c a bad row exactly AT the window start is inside it (start is inclusive)"
run_probe "$(with "$CLEAN" "$(row missed $((WIN_START - 1)))")" 200 "$NOW_AFTER"
check "$RC" 0 "6d a bad row one second before the window start is ignored"

run_probe "$(with "$CLEAN" "$(row missed $B_T3)" '{"status":"failed","leak":"'"$LEAK"'","dateAdded":"2026-10-30T06:00:00Z"}')" 200 "$NOW_AFTER"
check "$RC" 1 "6e a bad row outranks an unrecognised status"

run_probe "$(with "$(padded 72 40)" "$(row missed $B_T3)")" 200 "$NOW_AFTER"
check "$RC" 1 "6f a bad row on a full truncated page is still a FAIL (exit 1, not 3)"
run_probe "$(with "$(slot_rows 27)" "$(row missed $B_T3)")" 200 "$NOW_AFTER"
check "$RC" 1 "6g a bad row with an uncovered slot is still a FAIL (exit 1, not 3)"
run_probe "$(with "$CLEAN" "$(row missed $B_T3)" '{"status":"ok","leak":"'"$LEAK"'","dateAdded":"'"$LEAK"'"}')" 200 "$NOW_AFTER"
check "$RC" 3 "6h an unparseable row outranks a bad row (documented order: integrity first)"
run_probe "$(with "$CLEAN" "$(row failed $((WIN_START - 5)))" "$(row weird $((WIN_END + 5)))")" 200 "$NOW_AFTER"
check "$RC" 0 "6i an unrecognised status outside the window is ignored"
bad_rows=(); for k in $(seq 0 13); do bad_rows+=("$(row missed $((WIN_START + k * 3600 + 60)))"); done
run_probe "$(with "$CLEAN" "${bad_rows[@]}")" 200 "$NOW_AFTER"
check "$RC" 1 "6j fourteen bad rows are a FAIL"
check "$(grep -c '^  - ' "$OUT")" 10 "6k the itemised bad-row list is capped at 10 lines (count shown in the exit slot)"
run_probe "$(with "$CLEAN" "$(row error $B_T9)" "$(row timeout $B_T3)")" 200 "$NOW_AFTER"
check "$(grep '^  - ' "$OUT" | head -1)" "  - timeout @ $(iso $B_T3)" "6l itemised rows are oldest first (the exit slot shows the first line)"

echo "== truncation"
run_probe "$(padded 72 40)" 200 "$NOW_AFTER"
check "$RC" 3 "7  full page (100 rows), oldest row newer than the window start: exit 3"
present "page is full" "$OUT" "7b the truncation check names itself"
run_probe "$(padded 72 0)" 200 "$NOW_AFTER"
check "$RC" 0 "7c 100 rows with the oldest exactly at the window start is not truncation"
run_probe "$(padded 71 40)" 200 "$NOW_AFTER"
check "$RC" 0 "7d 99 rows (not a full page), oldest newer than the window start, is not truncation"

echo "== slot coverage (distinct slots, not row count)"
# Equivalent mutant (documented, not killable): counting coverage over ALL rows instead of the in-window rows yields the
# same verdict, because the probe subtracts the covered set from [0..27]; rows outside the window map to buckets
# outside it. 9g/9h still pin that out-of-window rows never reach a bucket.
run_probe "$(slot_rows 27)" 200 "$NOW_AFTER"
check "$RC" 3 "9  27 slots with an ok row: exit 3"
present "1 of 28 slots have no ok check-in" "$OUT" "9b the coverage check names the count"
run_probe "$(slot_rows 5)" 200 "$NOW_AFTER"
check "$RC" 3 "9b2 five slots covered is exit 3"
check "$(grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' "$OUT" | wc -l | tr -d ' ')" 10 "9b3 the uncovered-slot list is capped at 10 timestamps (count shown in the exit slot)"
DUP="$("$REAL_JQ" -n -c --argjson b "$CLEAN" '$b | .[1:] + [.[1]]')"
run_probe "$DUP" 200 "$NOW_AFTER"
check "$RC" 3 "9c 28 ok rows but slot 0 uncovered (a duplicate stands in): exit 3"
present "$(iso "$WIN_START")" "$OUT" "9d the uncovered slot start is printed"
run_probe "$(with "$CLEAN" "$(row ok $((WIN_START + SLOT + 500)))" "$(row ok $((WIN_START + 20 * SLOT + 900)))")" 200 "$NOW_AFTER"
check "$RC" 0 "9e extra ok rows inside covered slots are harmless (a manual re-dispatch)"
run_probe "$(slot_rows 28 0 43199)" 200 "$NOW_AFTER"
check "$RC" 0 "9f the first slot at exactly the window start and the last at the end-1 edge are covered"
run_probe "$(with "$(slot_rows 27)" "$(row ok $((WIN_START - 100)))" "$(row ok $((WIN_START - 40000)))")" 200 "$NOW_AFTER"
check "$RC" 3 "9g ok rows BEFORE the window never cover a slot"
run_probe "$(with "$(slot_rows 27)" "$(row ok $((WIN_END + 10)))" "$(row ok $((WIN_END + 40000)))")" 200 "$NOW_AFTER"
check "$RC" 3 "9h ok rows AFTER the window never cover a slot"
run_probe "$(with "$(slot_rows 27)" "$(row in_progress $((WIN_START + 27 * SLOT + 40)))")" 200 "$NOW_AFTER"
check "$RC" 3 "9i an in_progress row never covers a slot"
run_probe "$(with "$CLEAN" "$(row in_progress $((WIN_START + 7 * SLOT + 5)))")" 200 "$NOW_AFTER"
check "$RC" 0 "9j an in_progress row inside a covered slot is ignored"

echo "== waived slot (CTO ruling D7: an error row inside slot bucket 1 only)"
NO1="$("$REAL_JQ" -n -c --argjson c "$CLEAN" '$c | del(.[1])')" # CLEAN without its slot-1 ok row
S1=$((WIN_START + SLOT))
run_probe "$(with "$NO1" "$(row error $((S1 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 0 "W1 an error row inside slot 1 covers slot 1 (waived)"
present "waived=1" "$OUT" "W1b the waived count is printed"
run_probe "$(with "$NO1" "$(row error "$S1")")" 200 "$NOW_AFTER"
check "$RC" 0 "W2 an error row exactly at the slot 1 start is waived"
run_probe "$(with "$NO1" "$(row error $((S1 + SLOT - 1)))")" 200 "$NOW_AFTER"
check "$RC" 0 "W3 an error row in the last second of slot 1 is waived"
run_probe "$(with "$NO1" "$(row error $((S1 + SLOT)))")" 200 "$NOW_AFTER"
check "$RC" 1 "W4 an error row at the start of slot 2 is NOT waived (exit 1)"
run_probe "$(with "$NO1" "$(row error $((S1 - 1)))")" 200 "$NOW_AFTER"
check "$RC" 1 "W5 an error row in the last second of slot 0 is NOT waived (exit 1)"
run_probe "$(with "$NO1" "$(row missed $((S1 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 1 "W6 a missed row inside slot 1 is not waived (exit 1)"
run_probe "$(with "$NO1" "$(row timeout $((S1 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 1 "W7 a timeout row inside slot 1 is not waived (exit 1)"
run_probe "$NO1" 200 "$NOW_AFTER"
check "$RC" 3 "W8 slot 1 with neither an ok nor a waived row stays uncovered (exit 3)"
run_probe "$(with "$NO1" "$(row weird $((S1 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 3 "W9 an unrecognised status inside slot 1 is not waived (exit 3)"
run_probe "$(with "$CLEAN" "$(row error $((S1 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 0 "W10 an error row beside an ok row in slot 1 is harmless (exit 0)"
run_probe "$(with "$(slot_rows 27)" "$(row error $((S1 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 3 "W11 a waived slot 1 does not cover the missing last slot (exit 3)"

echo "== status vocabulary (allowlist)"
for odd in failed 'error ' miss unknown; do
  run_probe "$(with "$CLEAN" "$(row "$odd" $B_T3)")" 200 "$NOW_AFTER"
  check "$RC" 3 "10 unrecognised status '$odd' is exit 3, never 0"
done
present "does not recognise" "$OUT" "10b the vocabulary gap names itself"
run_probe "$(with "$CLEAN" "$(row zzstatus-7q $B_T3)")" 200 "$NOW_AFTER"
check "$RC" 3 "10c an unrecognised status word is exit 3"
absent "zzstatus-7q" "$OUT" "10d the raw unrecognised word is never printed (closed output token set)"
run_probe "$(with "$CLEAN" '{"leak":"'"$LEAK"'","dateAdded":"2026-10-30T06:00:00Z"}')" 200 "$NOW_AFTER"
check "$RC" 3 "10e a row with no status is exit 3"
run_probe "$(with "$CLEAN" '{"status":5,"leak":"'"$LEAK"'","dateAdded":"2026-10-30T06:00:00Z"}')" 200 "$NOW_AFTER"
check "$RC" 3 "10f a numeric status is exit 3"
run_probe "$(with "$CLEAN" '{"status":null,"leak":"'"$LEAK"'","dateAdded":"2026-10-30T06:00:00Z"}')" 200 "$NOW_AFTER"
check "$RC" 3 "10g a null status is exit 3"

run_probe "$(with "$CLEAN" "$(row MISSED $B_T3)")" 200 "$NOW_AFTER"
check "$RC" 1 "10h an upper-case bad status is folded and read as missed (ruling D3)"
present "  - missed @ $(iso $B_T3)" "$OUT" "10i the folded status is printed as the closed token"
run_probe "$(with "$(slot_rows 27)" "$(row OK $((WIN_START + 27 * SLOT + 40)))")" 200 "$NOW_AFTER"
check "$RC" 0 "10j an upper-case OK covers its slot (the ok side of the fold)"

echo "== inputs, pins, clock"
run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ORG=other-org
check "$RC" 3 "11 SENTRY_ORG differing from the pin is exit 3"
calls_are 0 "11b no request sent for an unpinned org"
run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_API_HOST=evil.example
check "$RC" 3 "11c SENTRY_API_HOST differing from the pin is exit 3"
calls_are 0 "11d no request sent for an unpinned host"

run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN=
check "$RC" 3 "12 empty token is exit 3"
calls_are 0 "12b no request sent without a token"
run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN=$'abc\nheader = "X: y"'
check "$RC" 3 "12c a token containing a newline is exit 3"
calls_are 0 "12d no request sent for an injected token"
CHARSET_TOKEN='sntrys_aB3.dE4+fG5/hI6~jK7=='
run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN="$CHARSET_TOKEN" FT_TOKEN="$CHARSET_TOKEN"
check "$RC" 0 "12e every character of the token allowlist (_ . ~ + / = -) is accepted"

i=0
for stray in '"' ' ' $'\\' $'\t' $'\r' ';' $'\''; do
  i=$((i + 1))
  run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN="abc${stray}def" FT_TOKEN="abc${stray}def"
  check "$RC" 3 "12f stray token character #$i is refused"
  calls_are 0 "12g no request sent for stray token character #$i"
done

# xtrace with a token set → 78, and the token is not in the output
printf '%s' "$CLEAN" > "$FIX"; : > "$CALLS"
env -i PATH="$SHIMS:$PATH" HOME="${HOME:-/}" TMPDIR="$TMPDIR" FT_FIXTURE="$FIX" FT_STATUS=200 FT_CALLS="$CALLS" \
  FT_REFUSE="$REFUSE" FT_URL="$URL_EXPECTED" FT_TOKEN="$TOKEN" FT_NOW="$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN="$TOKEN" \
  "$REAL_BASH" -x "$PROBE" > "$OUT" 2>&1
check "$?" 78 "13 refuses to run under bash -x with a token set"
absent "$TOKEN" "$OUT" "13b token not in the xtrace-refusal output"

run_probe "$CLEAN" 200 "$NOW_BEFORE"
check "$RC" 2 "14 before the pinned end: exit 2 (NOT YET)"
calls_are 0 "14b no request sent before the pinned end"
run_probe "$CLEAN" 200 "$WIN_END"
check "$RC" 0 "14c at exactly the pinned end the window has closed"
run_probe "$CLEAN" 200 "08"
check "$RC" 3 "14d a leading-zero clock reading is exit 3, not a fall-through to PASS"
run_probe "$CLEAN" 200 "abc"
check "$RC" 3 "14e a non-numeric clock reading is exit 3"
run_probe "$CLEAN" 200 "99999999999999999999"
check "$RC" 3 "14f a 20-digit clock reading is exit 3 (bash arithmetic would overflow)"

echo "== reads and integrity failures"
run_probe "{\"detail\":\"$LEAK\"}" 401 "$NOW_AFTER"
check "$RC" 3 "15 a 401 is exit 3"
run_probe "{\"detail\":\"$LEAK\"}" 200 "$NOW_AFTER"
check "$RC" 3 "15b a non-array 200 is exit 3"
present "not exactly one JSON array" "$OUT" "15c the shape check names itself (not a downstream jq error)"
run_probe "$CLEAN" 500 "$NOW_AFTER"
check "$RC" 3 "15d a non-200 status with an array-shaped body is still exit 3"
present "HTTP 500" "$OUT" "15e the HTTP status check names itself"
run_probe "$CLEAN"$'\n'"$(with '[]' "$(row missed $B_T3)")" 200 "$NOW_AFTER"
check "$RC" 3 "15f two concatenated JSON documents are exit 3 (never judged on one and shape-checked on another)"
run_probe "5"$'\n'"$CLEAN" 200 "$NOW_AFTER"
check "$RC" 3 "15g a scalar followed by an array is exit 3"
run_probe "$CLEAN" 200 "$NOW_AFTER" FT_CURL_RC=7
check "$RC" 3 "15h a failed request (curl rc 7) is exit 3"
present "curl rc 7" "$OUT" "15i the transport failure names itself"

run_probe "$(with "$CLEAN" '{"status":"ok","leak":"'"$LEAK"'","dateAdded":"'"$LEAK"'"}')" 200 "$NOW_AFTER"
check "$RC" 3 "16 a row with an unparseable timestamp is exit 3"
run_probe "$(with "$CLEAN" '{"status":"ok","leak":"'"$LEAK"'"}')" 200 "$NOW_AFTER"
check "$RC" 3 "16b a row with no timestamp is exit 3"
run_probe "$(with "$CLEAN" '{"status":"missed","leak":"'"$LEAK"'","dateAdded":"2026-10-30T06:00:00+00:00"}')" 200 "$NOW_AFTER"
check "$RC" 3 "16c a timestamp with an offset instead of Z is exit 3"
run_probe "$(with "$CLEAN" "$(row missed $B_T3 dateCreated)")" 200 "$NOW_AFTER"
check "$RC" 1 "16d a bad row carrying only dateCreated is read (the fallback field)"

}

# --- nested gate self-test: the LAST lines of this file must turn a failed row into a nonzero exit ---------
# A child run of this very file skips every row, records one injected failure, and must exit 1 and say so.
# It proves the final `finish` / `exit $?` below are wired (neutering either turns the child green, which no
# in-process check can see); the `fails > 0` branch of finish() itself is pinned by the in-process self-test above.
if [[ -n "${FT_NESTED_GATE:-}" ]]; then
  fail "injected failure (nested gate self-test)"
else
  main_rows
  child_rc=0
  child_out=$(FT_NESTED_GATE=1 "$REAL_BASH" "${BASH_SOURCE[0]}" 2>&1) || child_rc=$?
  if [[ "$child_rc" -ne 1 || "$child_out" != *"injected failure"* ]]; then
    printf 'FATAL: nested gate self-test: the child run (injected failed assertion) must exit 1 and report it; got rc=%s\n' "$child_rc" >&2
    exit 1
  fi
fi

# --- accounting floor: reported with printf + exit, never through the helpers it backstops -------
finish
exit $?
