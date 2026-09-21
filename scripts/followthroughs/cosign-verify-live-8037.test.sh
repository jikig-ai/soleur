#!/usr/bin/env bash
# Exit-code harness for cosign-verify-live-8037.sh (#8037: image signature verification).
#
# The probe's exit code closes #8037 (0), alarms (1), asks a human (5) or retries (2/3). The
# cardinal sins are a vacuous 0 — zero hosts, an `ok` quoted by another producer, a grade taken
# on the wrong verdict — and a FAIL that can never clear because one old blip is graded forever.
#
# FIXTURES ARE PRODUCTION-SHAPED: betterstack-query.sh emits JSONEachRow whose `raw` column is a
# JSON-ENCODED STRING holding the journald JSON (fields SYSLOG_IDENTIFIER, _MACHINE_ID,
# __REALTIME_TIMESTAMP, message — the spellings measured on a live row on 2026-09-21). Rows are
# built with jq so `raw` is genuinely double-encoded, and one case asserts that it is.
# Values are synthesized (cq-test-fixtures-synthesized-only): machine ids, digests and
# timestamps are fabricated.
#
# THE STUB ASSERTS ITS ARGV: the evidence gate is the server-side `--since`, so a probe that
# dropped it, or queried the wrong marker, must go red here.

export TMPDIR="${TMPDIR:-/var/tmp}"  # a shared /tmp tmpfs under quota must not decide this verdict
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/cosign-verify-live-8037.sh"
fails=0
checks=0
cases=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

EARLIEST_ISO="2026-09-01T00:00:00Z"
EARLIEST_SQL="2026-09-01 00:00:00"
E_US=1788220800000000            # EARLIEST_ISO in microseconds
T1=$((E_US + 3600000000))        # +1h
T2=$((E_US + 7200000000))        # +2h
T3=$((E_US + 10800000000))       # +3h
T_OLD=$((E_US - 3600000000))     # -1h: before earliest
HA="aaaaaaaaaaaa1111111111111111aaaa"
HB="bbbbbbbbbbbb2222222222222222bbbb"

cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
argv="$*"
[[ "$argv" == *"--since ${STUB_WANT_SINCE}"* ]] || { echo "stub: wrong/missing --since (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--grep IMAGE_VERIFY"* ]] || { echo "stub: missing --grep IMAGE_VERIFY (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--limit "* ]] || { echo "stub: missing --limit (argv: $argv)" >&2; exit 64; }
cat "${STUB_ROWS:-/dev/null}"
STUB
chmod +x "$WORK/stub-query"

# row <mid> <ts_us> <message> [identifier] — ONE production-shaped, double-encoded JSONEachRow line.
row() {
  local mid="$1" ts="$2" msg="$3" ident="${4:-ci-deploy}"
  jq -cn --arg mid "$mid" --arg ts "$ts" --arg msg "$msg" --arg id "$ident" \
    '{dt:"2026-09-02 10:00:00.000000",
      raw: ({SYSLOG_IDENTIFIER:$id, _MACHINE_ID:$mid, __REALTIME_TIMESTAMP:$ts,
             host:"soleur-web-platform", host_name:"soleur-web-platform", message:$msg} | tostring)}'
}
OK_MSG='IMAGE_VERIFY: ok ref=10.0.1.30:5000/jikig-ai/soleur-web-platform@sha256:0000000000000000000000000000000000000000000000000000000000000001'
fail_msg() { printf 'IMAGE_VERIFY_FAIL: result=%s ref=10.0.1.30:5000/jikig-ai/soleur-web-platform@sha256:00 mode=warn detail=SECRETISH_FREE_TEXT result=ok' "$1"; }
PREP_MSG='IMAGE_VERIFY_PREP: anon_config=unavailable'

# run_case <desc> <want-rc> <want-substring> <fixture> [env assignments...]
run_case() {
  local desc="$1" want_rc="$2" want_sub="$3" fx="$4"; shift 4
  cases=$((cases + 1))
  local rc=0
  OUT="$(env BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        SOLEUR_FT_EARLIEST="$EARLIEST_ISO" COSIGN_VERIFY_8037_BQ="$WORK/stub-query" \
        STUB_ROWS="$fx" STUB_WANT_SINCE="$EARLIEST_SQL" "$@" bash "$SUT" 2>&1)" || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$desc -- rc=$rc want=$want_rc :: $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
  elif [[ -n "$want_sub" ]] && ! grep -qF -- "$want_sub" <<<"$OUT"; then
    fail "$desc -- rc ok but missing '$want_sub' :: $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
  else
    pass "$desc (exit=$rc)"
  fi
}

fx() { printf '%s/%s.jsonl' "$WORK" "$1"; }

echo "== cosign-verify-live-8037.sh exit-code harness =="

# --- fixture fidelity: `raw` is a JSON STRING holding a JSON object ----------------------------
row "$HA" "$T1" "$OK_MSG" > "$(fx one-ok)"
if [[ "$(jq -r '.raw | type' "$(fx one-ok)")" == "string" && "$(jq -r '.raw | fromjson | .SYSLOG_IDENTIFIER' "$(fx one-ok)")" == "ci-deploy" ]]; then
  pass "fixture raw column is double-encoded (string -> journald object)"
else
  fail "fixture raw column is not double-encoded"
fi

# --- PASS arms -----------------------------------------------------------------------------------
run_case "one host, latest ok (double-encoded raw) -> PASS" 0 "PASS: 1 host(s)" "$(fx one-ok)"

{ row "$HA" "$T1" "$(fail_msg cosign_absent)"; row "$HA" "$T2" "$(fail_msg cosign_absent)"; row "$HA" "$T3" "$OK_MSG"; } > "$(fx stale-absent-then-ok)"
run_case "stale cosign_absent x2 then ok -> PASS (graded on LATEST verdict)" 0 "cosign_absent=2" "$(fx stale-absent-then-ok)"

{ row "$HA" "$T1" "$OK_MSG"; row "$HB" "$T2" "$OK_MSG"; } > "$(fx two-ok)"
run_case "two hosts, both latest ok -> PASS" 0 "PASS: 2 host(s)" "$(fx two-ok)"

{ row "$HA" "$T1" "$PREP_MSG"; row "$HA" "$T2" "$OK_MSG"; row "$HA" "$T3" "$OK_MSG"; } > "$(fx prep-old-deploy)"
run_case "PREP-unavailable in an OLDER deploy, latest ok with clean prep -> PASS" 0 "PASS" "$(fx prep-old-deploy)"

{ row "$HA" "$T1" "$OK_MSG"; row "$HA" "$T2" "$PREP_MSG"; } > "$(fx prep-in-flight)"
run_case "PREP with no following verdict (deploy in flight) does not attach -> PASS" 0 "PASS" "$(fx prep-in-flight)"

{ row "$HA" "$T_OLD" "$(fail_msg cosign_absent)"; row "$HA" "$T1" "$OK_MSG"; } > "$(fx pre-earliest-absent)"
run_case "cosign_absent BEFORE earliest is not counted -> PASS" 0 "cosign_absent=0" "$(fx pre-earliest-absent)"

# --- zero-host arms: never PASS ------------------------------------------------------------------
: > "$(fx empty)"
run_case "zero rows -> NOT YET (2)" 2 "zero IMAGE_VERIFY rows" "$(fx empty)"

row "$HA" "$T1" "GitHub webhook body quotes: $OK_MSG" doppler > "$(fx contam-only)"
run_case "only a doppler row quoting IMAGE_VERIFY: ok -> zero hosts -> 2, never PASS" 2 "Zero hosts" "$(fx contam-only)"

row "$HA" "$T1" "$OK_MSG" doppler > "$(fx contam-exact)"
run_case "exact 'IMAGE_VERIFY: ok' message under SYSLOG_IDENTIFIER=doppler does not count -> 2" 2 "Zero hosts" "$(fx contam-exact)"

row "$HA" "$T1" "$OK_MSG" ci-deploy-canary > "$(fx contam-prefix)"
run_case "SYSLOG_IDENTIFIER that merely CONTAINS ci-deploy does not count -> 2" 2 "Zero hosts" "$(fx contam-prefix)"

row "$HA" "$T_OLD" "$OK_MSG" > "$(fx ok-before-earliest)"
run_case "ok only BEFORE earliest -> zero hosts -> 2" 2 "Zero hosts" "$(fx ok-before-earliest)"

row "$HA" "$T1" "IMAGE_VERIFY: Sentry POST failed" > "$(fx sentry-only)"
run_case "'IMAGE_VERIFY: Sentry POST failed' is not a verdict -> 2" 2 "Zero hosts" "$(fx sentry-only)"

row "$HA" "$T1" "$PREP_MSG" > "$(fx prep-only)"
run_case "PREP line alone is not a verdict -> 2" 2 "Zero hosts" "$(fx prep-only)"

# --- FAIL (1) -----------------------------------------------------------------------------------
row "$HA" "$T1" "$(fail_msg cosign_absent)" > "$(fx one-absent)"
run_case "one host, latest cosign_absent -> FAIL" 1 "FAIL: 1 of 1" "$(fx one-absent)"
if grep -q 'SECRETISH_FREE_TEXT' <<<"$OUT"; then fail "FAIL output reprinted the free-text detail= into a public comment"
else pass "FAIL output withholds the free-text detail="; fi

{ row "$HA" "$T1" "$OK_MSG"; row "$HA" "$T2" "$(fail_msg cosign_absent)"; } > "$(fx ok-then-absent)"
run_case "ok then cosign_absent (latest) -> FAIL" 1 "latest=result=cosign_absent" "$(fx ok-then-absent)"

{ row "$HA" "$T1" "$(fail_msg cosign_absent)"; row "$HA" "$T2" "$OK_MSG" doppler; } > "$(fx absent-plus-contam-ok)"
run_case "ci-deploy cosign_absent + LATER doppler 'ok' on same machine id -> FAIL (ok does not count)" 1 "FAIL" "$(fx absent-plus-contam-ok)"

{ row "$HA" "$T1" "$OK_MSG"; row "$HB" "$T2" "$(fail_msg cosign_absent)"; } > "$(fx two-one-absent)"
run_case "two hosts, one ok + one cosign_absent -> FAIL (per-host, not fleet-global)" 1 "FAIL: 1 of 2" "$(fx two-one-absent)"

{ row "$HA" "$T1" "$(fail_msg unsigned)"; row "$HB" "$T2" "$(fail_msg cosign_absent)"; } > "$(fx absent-beats-unsigned)"
run_case "cosign_absent on one host + unsigned on another -> FAIL takes precedence over 5" 1 "FAIL" "$(fx absent-beats-unsigned)"

# --- ACTION REQUIRED (5) -------------------------------------------------------------------------
for cls in unsigned wrong_identity verify_failed rekor_unreachable inspect_failed; do
  row "$HA" "$T1" "$(fail_msg "$cls")" > "$(fx "cls-$cls")"
  run_case "latest result=$cls -> ACTION REQUIRED (5)" 5 "latest=result=$cls" "$(fx "cls-$cls")"
done

{ row "$HA" "$T1" "$(fail_msg cosign_absent)"; row "$HA" "$T2" "$(fail_msg wrong_identity)"; } > "$(fx absent-then-wrongid)"
run_case "stale cosign_absent then wrong_identity -> 5 (latest verdict, not FAIL)" 5 "new failure class" "$(fx absent-then-wrongid)"

{ row "$HA" "$T1" "$PREP_MSG"; row "$HA" "$T2" "$OK_MSG"; } > "$(fx prep-then-ok)"
run_case "PREP anon_config=unavailable then ok in the same deploy -> 5 (own message)" 5 "anon_config=unavailable before the latest verdict" "$(fx prep-then-ok)"

{ row "$HA" "$T2" "$OK_MSG"; row "$HA" "$T2" "$PREP_MSG"; } > "$(fx prep-tie)"
run_case "PREP and ok on the SAME timestamp (PREP emitted first) -> 5" 5 "anon_config=unavailable" "$(fx prep-tie)"

{ row "$HA" "$T1" "$PREP_MSG"; row "$HA" "$T2" "$(fail_msg cosign_absent)"; } > "$(fx prep-then-absent)"
run_case "PREP then cosign_absent -> 5 (the credentialed fallback ran, not the fix)" 5 "anon_config=unavailable" "$(fx prep-then-absent)"

{ row "$HA" "$T1" "$PREP_MSG" doppler; row "$HA" "$T2" "$OK_MSG"; } > "$(fx prep-contam)"
run_case "PREP quoted under another identifier does not attach -> PASS" 0 "PASS" "$(fx prep-contam)"

# --- CANNOT ESTABLISH (3) ------------------------------------------------------------------------
printf '%s\n' 'not json at all IMAGE_VERIFY: ok' '{"dt":"x","raw":"IMAGE_VERIFY: ok not-json"}' > "$(fx undecodable)"
run_case "rows that do not decode as the journald envelope -> 3" 3 "none decoded" "$(fx undecodable)"

row "" "$T1" "$OK_MSG" > "$(fx no-mid)"
run_case "ci-deploy verdict with no _MACHINE_ID -> 3" 3 "_MACHINE_ID" "$(fx no-mid)"

run_case "SOLEUR_FT_EARLIEST empty -> 3" 3 "SOLEUR_FT_EARLIEST is unset" "$(fx one-ok)" SOLEUR_FT_EARLIEST=
run_case "SOLEUR_FT_EARLIEST malformed ('yesterday') -> 3" 3 "not an ISO instant" "$(fx one-ok)" SOLEUR_FT_EARLIEST=yesterday
cases=$((cases + 1)); rc=0
OUT="$(env -u SOLEUR_FT_EARLIEST BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
      COSIGN_VERIFY_8037_BQ="$WORK/stub-query" STUB_ROWS="$(fx one-ok)" STUB_WANT_SINCE="$EARLIEST_SQL" bash "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 3 ]]; then pass "SOLEUR_FT_EARLIEST unset -> 3 (exit=$rc)"; else fail "SOLEUR_FT_EARLIEST unset -- rc=$rc want=3"; fi

# --- NOT YET (2): channel guards -----------------------------------------------------------------
run_case "SOLEUR_FT_EARLIEST in the future -> 2" 2 "in the future" "$(fx one-ok)" SOLEUR_FT_EARLIEST=2099-01-01T00:00:00Z
run_case "query tool exits non-zero -> 2" 2 "exited non-zero" "$(fx one-ok)" STUB_RC=7
run_case "query argv carries the wrong --since (stub refuses) -> 2, never PASS" 2 "" "$(fx one-ok)" STUB_WANT_SINCE=1999-01-01
run_case "missing query tool -> 2" 2 "not found/executable" "$(fx one-ok)" COSIGN_VERIFY_8037_BQ="$WORK/nope.sh"
run_case "invalid SOLEUR_FT_LIMIT -> 2" 2 "invalid SOLEUR_FT_LIMIT" "$(fx one-ok)" SOLEUR_FT_LIMIT=0
cases=$((cases + 1)); rc=0
OUT="$(env -u BETTERSTACK_QUERY_PASSWORD BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u SOLEUR_FT_EARLIEST="$EARLIEST_ISO" \
      COSIGN_VERIFY_8037_BQ="$WORK/stub-query" STUB_ROWS="$(fx one-ok)" STUB_WANT_SINCE="$EARLIEST_SQL" bash "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "BETTERSTACK_QUERY_PASSWORD unset -> 2, never 1 (exit=$rc)"; else fail "creds unset -- rc=$rc want=2"; fi

# --- xtrace refusal (#7797) ----------------------------------------------------------------------
cases=$((cases + 1)); rc=0
OUT="$(env BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p bash -x "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 78 ]]; then pass "refuses to run under xtrace with a credential bound (exit=78)"; else fail "xtrace refusal -- rc=$rc want=78"; fi

# --- anti-vacuity floor + accounting conservation (never routed through fail()) -----------------
MIN_CASES=40
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] vacuity guard: only %s cases ran (floor %s)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ "$checks" -lt "$cases" ]]; then
  printf '[FATAL] accounting: %s cases ran but only %s verdicts were recorded\n' "$cases" "$checks" >&2
  exit 1
fi

if [[ "$fails" -gt 0 ]]; then echo "FAILED: $fails of $checks check(s)" >&2; exit 1; fi
echo "OK: all $checks cosign-verify-live-8037 checks passed ($cases cases)"
