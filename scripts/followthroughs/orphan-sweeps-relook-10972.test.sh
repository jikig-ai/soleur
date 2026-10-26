#!/usr/bin/env bash
# Fixture suite for the #10972 follow-through probe (orphan-sweeps-relook-10972.sh).
#
# The probe closes its tracker on exit 0, so every branch that can end in 0 or 1 has a row, and every
# row that must NOT end in 0 asserts the exit code AND that the probe never echoed a response body.
# `curl` and `date` are PATH shims: the curl shim REFUSES (exit 64) any request that is not the one
# shape the probe is meant to send, so a wrong URL, a missing --max-time/--proto, or a token placed in
# argv reads as a curl failure and reds the clean row instead of being answered with a fixture.
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

# --- curl shim -------------------------------------------------------------------------------------
# Replays $FT_FIXTURE with $FT_STATUS, logs one line per call to $FT_CALLS, refuses unexpected argv.
cat > "$SHIMS/curl" <<'SHIM'
#!/usr/bin/env bash
printf 'call\n' >> "$FT_CALLS"
args=("$@")
have_max=0; have_proto=0; have_cfg=0; url=""
i=0
while [[ $i -lt ${#args[@]} ]]; do
  a="${args[$i]}"
  case "$a" in
    --max-time) [[ "${args[$((i+1))]:-}" == "30" ]] && have_max=1; i=$((i+1)) ;;
    --proto) [[ "${args[$((i+1))]:-}" == "=https" ]] && have_proto=1; i=$((i+1)) ;;
    --config) [[ "${args[$((i+1))]:-}" == "-" ]] && have_cfg=1; i=$((i+1)) ;;
    https://*) url="$a" ;;
  esac
  [[ -n "${FT_TOKEN_NEEDLE:-}" && "$a" == *"$FT_TOKEN_NEEDLE"* ]] && { echo "shim: token in argv" >&2; exit 64; }
  i=$((i+1))
done
[[ $have_max -eq 1 ]] || { echo "shim: missing --max-time 30" >&2; exit 64; }
[[ $have_proto -eq 1 ]] || { echo "shim: missing --proto =https" >&2; exit 64; }
[[ $have_cfg -eq 1 ]] || { echo "shim: missing --config -" >&2; exit 64; }
[[ "$url" == "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-orphan-sweeps/checkins/?per_page=100" ]] \
  || { echo "shim: unexpected url" >&2; exit 64; }
cfg="$(cat)"
[[ "$cfg" == 'header = "Authorization: Bearer '*'"' ]] || { echo "shim: no bearer on the stdin config channel" >&2; exit 64; }
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
calls_are() { # calls_are <expected-request-count> <label>   (reads NCALLS from the last run_probe)
  if [[ "$NCALLS" == "$1" ]]; then pass "$2"; else fail "$2 (got $NCALLS requests)"; fi
}
present() { # present <fixed-string> <haystack-file> <label>
  if grep -qF -- "$1" "$2"; then pass "$3"; else fail "$3 — missing '$1'"; fi
}

# --- instrument self-test: both verdict helpers must move their own counters ----------------------
_p0=$passes; _f0=$fails
pass "instrument self-test (pass branch)" > /dev/null
fail "instrument self-test (fail branch, expected)" > /dev/null
if [[ $((passes - _p0)) -ne 1 || $((fails - _f0)) -ne 1 ]]; then
  echo "FATAL: instrument self-test: helpers did not move their counters" >&2
  exit 1
fi
fails=$((fails - 1)) # the self-test's deliberate failure is not a result
passes=$((passes - 1))

# --- fixtures ------------------------------------------------------------------------------------
WIN_START=1792994400 # 2026-10-26T06:00:00Z
WIN_END=1794204000   # 2026-11-09T06:00:00Z
TOKEN="synthetic-token-0123456789abcdef"
NOW_AFTER=$((WIN_END + 3600))  # 07:00Z on the window-close day
NOW_BEFORE=$((WIN_END - 60))

iso() { "$REAL_DATE" -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# ok rows for slots 0..N-1, newest first, some with fractional seconds (Sentry's own shape).
ok_rows() { # ok_rows <count> [last-offset-seconds]
  "$REAL_JQ" -n -c --argjson n "$1" --argjson s "$WIN_START" --argjson off "${2:-40}" '
    [range(0; $n) | . as $i | { status: "ok",
       dateAdded: (($s + $i * 43200 + (if $i == $n - 1 then $off else 40 end)) | strftime("%Y-%m-%dT%H:%M:%S")
                    + (if $i % 2 == 0 then ".123456Z" else "Z" end)) }] | reverse'
}
row() { # row <status> <epoch>
  "$REAL_JQ" -n -c --arg st "$1" --arg ts "$(iso "$2")" '{status:$st, dateAdded:$ts}'
}
with() { # with <rows-json> <extra-row-json>...   (extra rows prepended; order is irrelevant to the probe)
  local base="$1"; shift
  local extra; extra="$("$REAL_JQ" -s -c '.' <<<"$(printf '%s\n' "$@")")"
  "$REAL_JQ" -n -c --argjson a "$extra" --argjson b "$base" '$a + $b'
}

CALLS="$TMP_ROOT/calls"
OUT="$TMP_ROOT/out"
FIX="$TMP_ROOT/fixture"

# run_probe <fixture-json-or-text> <status> <now> [extra env assignments...]  → exit code in $RC
run_probe() {
  local body="$1" status="$2" now="$3"; shift 3
  printf '%s' "$body" > "$FIX"
  : > "$CALLS"
  env -i PATH="$SHIMS:$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
    FT_FIXTURE="$FIX" FT_STATUS="$status" FT_CALLS="$CALLS" FT_NOW="$now" FT_TOKEN_NEEDLE="$TOKEN" \
    SENTRY_ACTIONS_RO_TOKEN="$TOKEN" "$@" \
    "$REAL_BASH" "$PROBE" > "$OUT" 2>&1
  RC=$?
  NCALLS=$(wc -l < "$CALLS" | tr -d ' ')
}

echo "== verdict rows"

CLEAN="$(ok_rows 28)"
run_probe "$CLEAN" 200 "$NOW_AFTER"
check "$RC" 0 "1  clean fixture: 28 ok rows across the window"
present "PASS" "$OUT" "1b clean run prints a PASS line"
present "Sentry issue state was not read" "$OUT" "1c output states what was not measured"
calls_are 1 "1d exactly one request sent"
absent "$TOKEN" "$OUT" "1e token never appears in output"

run_probe "[]" 200 "$NOW_AFTER"
check "$RC" 3 "2  empty array (zero rows) is exit 3, never 0"
present "0 check-in rows returned" "$OUT" "2b the zero-row read names itself (not only the floor)"

run_probe "$(with "$CLEAN" "$(row missed $((WIN_START + 5 * 43200 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 1 "3  one missed row among 28 ok rows"

run_probe "$(with "$CLEAN" "$(row timeout $((WIN_START + 3 * 43200 + 60)))" "$(row error $((WIN_START + 9 * 43200 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 1 "4  timeout and a later error row"
present "  - timeout @ $(iso $((WIN_START + 3 * 43200 + 60)))" "$OUT" "4b the timeout row is itemised (not only named in the header)"
present "$(iso $((WIN_START + 9 * 43200 + 60)))" "$OUT" "4c the second bad row is reported too (no stop at the first)"

run_probe "$(with "$CLEAN" "$(row timeout $((WIN_START + 3 * 43200 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 1 "4d a lone timeout row (no other bad row to mask it)"

run_probe "$(with "$CLEAN" "$(row error $((WIN_START + 11 * 43200 + 60)))")" 200 "$NOW_AFTER"
check "$RC" 1 "5  one error row among otherwise ok rows"

run_probe "$(with "$CLEAN" "$(row missed $((WIN_END + 40)))")" 200 "$NOW_AFTER"
check "$RC" 0 "6  a bad row dated after the pinned end is ignored"
run_probe "$(with "$CLEAN" "$(row missed "$WIN_END")")" 200 "$NOW_AFTER"
check "$RC" 0 "6b a bad row exactly AT the pinned end is outside the window (end is exclusive)"

# 7: a full page (100 rows) whose oldest row is newer than the window start is truncation
TRUNC="$("$REAL_JQ" -n -c --argjson e "$WIN_END" '[range(0;100) | {status:"ok", dateAdded: (($e - 3600 - .*3600) | strftime("%Y-%m-%dT%H:%M:%SZ"))}]')"
run_probe "$TRUNC" 200 "$NOW_AFTER"
check "$RC" 3 "7  full page, oldest row newer than the window start: exit 3"

# 7b: exactly 100 rows with the oldest before the window start passes the truncation guard
# (an older missed row, before the start, is outside the window and ignored)
OLDER="$("$REAL_JQ" -n -c --argjson s "$WIN_START" '[range(0;72) | {status:"ok", dateAdded: (($s - 3600 - .*3600) | strftime("%Y-%m-%dT%H:%M:%SZ"))}]')"
OLDER="$(with "$OLDER" "$(row missed $((WIN_START - 100)))")"
OLDER="$("$REAL_JQ" -n -c --argjson a "$CLEAN" --argjson b "$OLDER" '$a + $b | .[0:100]')"
run_probe "$OLDER" 200 "$NOW_AFTER"
check "$RC" 0 "7b exactly 100 rows, oldest before the window start, passes the guard"

# 7c: 100 rows whose oldest row sits exactly ON the window start reaches the start (not truncation)
EDGE="$("$REAL_JQ" -n -c --argjson s "$WIN_START" '[range(0;100) | {status:"ok", dateAdded: (($s + .*3600) | strftime("%Y-%m-%dT%H:%M:%SZ"))}] | reverse')"
run_probe "$EDGE" 200 "$NOW_AFTER"
check "$RC" 0 "7c 100 rows with the oldest exactly at the window start is not truncation"

# 7d: 99 rows is not a full page, so an oldest row newer than the window start is not truncation
SHORT="$("$REAL_JQ" -n -c --argjson e "$WIN_END" '[range(0;99) | {status:"ok", dateAdded: (($e - 3600 - .*3600) | strftime("%Y-%m-%dT%H:%M:%SZ"))}]')"
run_probe "$SHORT" 200 "$NOW_AFTER"
check "$RC" 0 "7d 99 rows (not a full page), oldest newer than the window start, is not truncation"

run_probe '{"detail":"not an array"}' 200 "$NOW_AFTER"
check "$RC" 3 "8  object response is exit 3"
present "not a JSON array" "$OUT" "8b the shape check names itself (not a downstream jq error)"

run_probe "$CLEAN" 500 "$NOW_AFTER"
check "$RC" 3 "8c a non-200 status with an array-shaped body is still exit 3"
present "HTTP 500" "$OUT" "8d the HTTP status check names itself"

run_probe "$(ok_rows 27)" 200 "$NOW_AFTER"
check "$RC" 3 "9  27 ok rows is below the 28-slot floor: exit 3"

run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ORG=other-org
check "$RC" 3 "10 SENTRY_ORG differing from the pin is exit 3"
calls_are 0 "10b no request sent for an unpinned org"
run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_API_HOST=evil.example
check "$RC" 3 "10c SENTRY_API_HOST differing from the pin is exit 3"
calls_are 0 "10d no request sent for an unpinned host"

run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN=
check "$RC" 3 "11 empty token is exit 3"
calls_are 0 "11b no request sent without a token"
run_probe "$CLEAN" 200 "$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN=$'abc\nheader = "X: y"'
check "$RC" 3 "11c a token containing a newline is exit 3"
calls_are 0 "11d no request sent for an injected token"

# 12: under xtrace with a token set → 78, and the token is not in the output
printf '%s' "$CLEAN" > "$FIX"; : > "$CALLS"
env -i PATH="$SHIMS:$PATH" HOME="$HOME" TMPDIR="$TMPDIR" FT_FIXTURE="$FIX" FT_STATUS=200 FT_CALLS="$CALLS" \
  FT_NOW="$NOW_AFTER" SENTRY_ACTIONS_RO_TOKEN="$TOKEN" "$REAL_BASH" -x "$PROBE" > "$OUT" 2>&1
check "$?" 78 "12 refuses to run under bash -x with a token set"
absent "$TOKEN" "$OUT" "12b token not in the xtrace-refusal output"

run_probe "$CLEAN" 200 "$NOW_BEFORE"
check "$RC" 2 "13 before the pinned end: exit 2 (NOT YET)"
calls_are 0 "13b no request sent before the pinned end"

# 14: nothing from a non-200 / non-array body may reach the output
LEAK="LEAKMARK-7f3a91c2"
run_probe "{\"detail\":\"$LEAK\"}" 401 "$NOW_AFTER"
check "$RC" 3 "14 a 401 is exit 3"
absent "$LEAK" "$OUT" "14b a 401 body is not echoed"
run_probe "{\"detail\":\"$LEAK\"}" 200 "$NOW_AFTER"
check "$RC" 3 "14c a non-array 200 is exit 3"
absent "$LEAK" "$OUT" "14d a non-array body is not echoed"

echo "== must-PASS inputs beyond the canonical fixture"
run_probe "$(with "$CLEAN" "$(row in_progress $((WIN_START + 7 * 43200 + 5)))")" 200 "$NOW_AFTER"
check "$RC" 0 "15 an in_progress row inside the window is ignored"

run_probe "$(ok_rows 28 $((43200 - 40 - 30)))" 200 "$NOW_AFTER"
check "$RC" 0 "16 an ok row arriving at the end of its slot still counts"

echo "== read and integrity failures"
run_probe "$CLEAN" 200 "$NOW_AFTER" FT_CURL_RC=7
check "$RC" 3 "17 a failed request (curl rc 7) is exit 3"
present "curl rc 7" "$OUT" "17b the transport failure names itself"

run_probe "$(with "$CLEAN" '{"status":"ok","dateAdded":"not-a-date"}')" 200 "$NOW_AFTER"
check "$RC" 3 "18 a row with an unparseable timestamp is exit 3"

run_probe "$(with "$CLEAN" '{"status":"ok"}')" 200 "$NOW_AFTER"
check "$RC" 3 "18b a row with no timestamp is exit 3"

# --- accounting floor: reported with printf + exit, never through the helpers it backstops -------
echo
echo "executed assertions: $((passes + fails)) (pass=$passes fail=$fails)"
EXPECTED_MIN=46
total=$((passes + fails))
if [[ "$total" -lt "$EXPECTED_MIN" ]]; then
  printf 'FATAL: only %s assertions executed (floor %s): the suite dispatched too little\n' "$total" "$EXPECTED_MIN" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
exit 0
