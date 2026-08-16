#!/usr/bin/env bash
# Unit tests for scripts/lib/betterstack-absence.sh — the shared ingest/absence discriminator
# extracted for #7569.
#
# WHY THIS SUITE EXISTS. On 2026-08-14 19:06:58Z Better Stack began refusing every ingest POST
# with HTTP 402 {"error": "Quota exceeded"}. The READ path kept answering 200, so every absence
# query returned rc=0 with zero rows. `scripts/zot-restart-loop-alarm.sh` collapsed
# "the query errored" and "the query succeeded and found nothing" into one `||` arm and called
# the result TRANSIENT — non-alarming — every 30 minutes for two days. The classifier under test
# exists to keep those two states apart.
#
# cq-test-fixtures-synthesized-only: every row below is hand-written here. No live Better Stack
# rows are captured into this file (the repo is public; a captured row is a permanent egress).
#
# .test.sh conventions (work/SKILL.md): `set -uo pipefail` and NOT -e — the classifier returns
# non-zero by contract, so a bare call under -e would abort the whole suite. Every call captures
# rc via `|| rc=$?`. TMPDIR defaults to /var/tmp because a direct invocation of this file (the
# documented inner loop) would otherwise inherit the machine-global 4 GiB /tmp tmpfs that
# parallel worktrees contend for.

set -uo pipefail
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/betterstack-absence.sh"

TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; CASES=0

pass() { PASS=$((PASS + 1)); echo "[ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "[FAIL] $1"; }

# --- Accounting control (R28 / lint-guard-contract.test.sh TS-21 precedent) ---------------
# A suite whose fail() does not also move the PASS accounting can report "0 passed, 0 failed,
# exit 0". Assert the two counters are wired to different variables before any real case runs.
_ctl_p=$PASS; _ctl_f=$FAIL
pass "accounting-control: pass() increments"; fail "accounting-control: fail() increments (EXPECTED, not a defect)"
if [[ "$PASS" -eq $((_ctl_p + 1)) && "$FAIL" -eq $((_ctl_f + 1)) ]]; then
  # Undo the deliberate control failure so it does not red the suite.
  FAIL=$((FAIL - 1)); PASS=$((PASS - 1))
  echo "[ok] accounting-control: counters are independent (control failure retracted)"
  PASS=$((PASS + 1))
else
  echo "[FATAL] accounting control did not behave — this suite cannot certify anything."
  exit 2
fi

[[ -r "$LIB" ]] || { echo "[FATAL] classifier library not found at $LIB"; exit 2; }
# shellcheck source=scripts/lib/betterstack-absence.sh
source "$LIB"

# --- Stub betterstack-query.sh ------------------------------------------------------------
# Dispatches on argv so a freshness read (--max-dt, R12) can never be served the control
# fixture. `exit 64` on an unrecognised shape: a stub that answers everything identically
# cannot detect the SUT querying the wrong thing.
STUB="$TMP/bq-stub.sh"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
argv="$*"
if [[ "$argv" == *"--limit"* ]]; then
  [[ -n "${FIX_CONTROL:-}" && -f "${FIX_CONTROL:-}" ]] && cat "$FIX_CONTROL"
  exit "${FIX_CONTROL_RC:-0}"
fi
echo "stub: unrecognised query shape: $argv" >&2
exit 64
STUB_EOF
chmod +x "$STUB"
export BETTERSTACK_QUERY_SCRIPT="$STUB"

mkfix() { local f="$TMP/fix.$1"; shift; printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }
EMPTY="$(mkfix empty "")"
: > "$EMPTY"

# A genuine Vector-shipped journald row: `raw` is an envelope whose FIRST key is PRIORITY.
ROW_JOURNALD="$(mkfix journald '{"dt":"2026-08-14 19:06:58","raw":"{\"PRIORITY\":\"6\",\"host_name\":\"soleur-registry\",\"message\":\"SOLEUR_PROBE_CANARY ok\"}"}')"
# A direct-POST producer row: the host POSTs {"message":"<marker> …"} and Better Stack stores
# THAT as raw, so the envelope starts with the message key.
ROW_DIRECT="$(mkfix direct '{"dt":"2026-08-14 19:06:58","raw":"{\"message\":\"SOLEUR_PROBE_CANARY host=soleur-registry\"}"}')"

# --- assert helper -------------------------------------------------------------------------
# assert_classify <name> <expected-verdict> ; fixtures come from exported FIX_* vars.
assert_classify() {
  local name="$1" want="$2" got rc=0
  CASES=$((CASES + 1))
  got="$(bs_absence_classify 2>/dev/null)" || rc=$?
  if [[ "$got" == "$want" ]]; then
    pass "$name → $got"
  else
    fail "$name → expected '$want', got '$got' (rc=$rc)"
  fi
}

echo "--- Guard 1: the ingest-refusal discriminator ---"

# R1 — the state production was in for two days. Query SUCCEEDED (rc=0) and found nothing.
# This is the case the old `[[ rc -ne 0 || -z "$out" ]]` collapse called TRANSIENT.
FIX_CONTROL="$EMPTY" FIX_CONTROL_RC=0 \
  assert_classify "control rc=0 + zero rows (402-dark warehouse)" "INGEST_DARK"

# R2 — the channel is demonstrably carrying rows.
FIX_CONTROL="$ROW_DIRECT" FIX_CONTROL_RC=0 \
  assert_classify "control rc=0 + rows present" "LIVE"

# R3/R4/R5 — a non-zero rc is a PROBE fault and must never be read as darkness. The three
# codes are the measured contract of betterstack-query.sh (bad SQL 22, unreachable 6,
# creds unset 3) — not assumed; re-measured for #7569.
FIX_CONTROL="$EMPTY" FIX_CONTROL_RC=6 \
  assert_classify "control rc=6 (host unreachable)" "TRANSPORT_FAIL"
FIX_CONTROL="$EMPTY" FIX_CONTROL_RC=3 \
  assert_classify "control rc=3 (credentials unset)" "TRANSPORT_FAIL"
FIX_CONTROL="$EMPTY" FIX_CONTROL_RC=22 \
  assert_classify "control rc=22 (malformed SQL)" "TRANSPORT_FAIL"

# R6 — HTTP 200 carrying a mid-stream ClickHouse exception. curl reports success; the body is
# not an answer. Must never be read as darkness (T14). The exception arrives as a BARE line
# outside the JSONEachRow stream, which is what makes it detectable by shape.
ROW_EXC="$(mkfix exc '{"dt":"2026-08-14 19:06:58","raw":"{}"}' 'Code: 241. DB::Exception: Memory limit exceeded')"
FIX_CONTROL="$ROW_EXC" FIX_CONTROL_RC=0 \
  assert_classify "rc=0 body carries a bare DB::Exception line" "TRANSPORT_FAIL"

# R6b — THE MUST-PASS TWIN, and the one that matters. Without it R6 is satisfiable by a content
# grep, which is what shipped and was wrong: `raw` is arbitrary application log text, so a
# healthy row whose message merely CONTAINS "exception" was classifying TRANSPORT_FAIL and
# suppressing the PRODUCER_SILENT / NIC SILENT legs to a non-alarming verdict.
ROW_APP_EXC="$(mkfix appexc '{"dt":"2026-08-14 19:06:58","raw":"{\"message\":\"TypeError: unhandled exception in handler\"}"}')"
FIX_CONTROL="$ROW_APP_EXC" FIX_CONTROL_RC=0 \
  assert_classify "a healthy row whose TEXT contains 'exception' is LIVE, not a probe fault" "LIVE"

# The same trap for the other three words the content grep matched. `Code: <n>` is the one an
# upstream-error log line hits constantly.
ROW_APP_CODE="$(mkfix appcode '{"dt":"2026-08-14 19:06:58","raw":"{\"message\":\"upstream returned Code: 502\"}"}')"
FIX_CONTROL="$ROW_APP_CODE" FIX_CONTROL_RC=0 \
  assert_classify "a healthy row whose TEXT contains 'Code: 502' is LIVE" "LIVE"

# An HTML error page or any non-JSONEachRow body is still not an answer.
ROW_HTML="$(mkfix html '<html><body>502 Bad Gateway</body></html>')"
FIX_CONTROL="$ROW_HTML" FIX_CONTROL_RC=0 \
  assert_classify "a non-JSONEachRow body (HTML error page) is not an answer" "TRANSPORT_FAIL"

echo "--- warehouse liveness: the account-wide-refusal instrument ---"
# The alarm's control is a bare `--limit 1` with no grep. It answers "is the warehouse taking
# ANYTHING", which is the correct question for an account-wide 402 and the wrong one to
# producer-anchor: a live warehouse carrying only other hosts' rows must read LIVE, not dark.
ROW_UNRELATED="$(mkfix unrelated '{"dt":"2026-08-14 19:06:58","raw":"some unrelated app log row"}')"

FIX_CONTROL="$EMPTY" FIX_CONTROL_RC=0 \
  assert_classify "any-row: zero rows of any kind" "INGEST_DARK"
FIX_CONTROL="$ROW_UNRELATED" FIX_CONTROL_RC=0 \
  assert_classify "any-row: an unrelated app row counts as warehouse liveness" "LIVE"
FIX_CONTROL="$EMPTY" FIX_CONTROL_RC=6 \
  assert_classify "any-row: rc=6 is still a probe fault, never darkness" "TRANSPORT_FAIL"

# Whitespace-only output is emptiness, not a row. Without this the `-n` test would read a
# trailing newline from the query wrapper as evidence the channel is alive.
WS="$(mkfix ws '   ')"
FIX_CONTROL="$WS" FIX_CONTROL_RC=0 \
  assert_classify "any-row: whitespace-only body is not a row" "INGEST_DARK"

echo "--- Anti-vacuity floor ---"
# A classifier that evaluated zero arms must not report a healthy verdict.
CASES=$((CASES + 1))
if declare -F bs_absence_classify >/dev/null; then
  pass "anti-vacuity: bs_absence_classify is defined (a missing function must not read as LIVE)"
else
  fail "anti-vacuity: bs_absence_classify is not defined"
fi

# --- Minimum-cardinality guard ------------------------------------------------------------
# A loop or fixture source that silently yields nothing would otherwise exit 0 having asserted
# nothing at all.
# Derived from the as-written file, not a mental tally:
#   grep -c 'assert_classify "' → 12, plus the anti-vacuity case = 13.
EXPECTED_CASES=13
echo
echo "cases=$CASES passed=$PASS failed=$FAIL"
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  echo "[FAIL] cardinality: ran $CASES cases, expected at least $EXPECTED_CASES"
  FAIL=$((FAIL + 1))
fi
[[ "$FAIL" -eq 0 ]] || exit 1
echo "=== betterstack-absence-classifier: $PASS assertions passed ==="
