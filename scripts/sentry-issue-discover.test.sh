#!/usr/bin/env bash
#
# Tests for scripts/sentry-issue.sh's DISCOVER modes (--host-events / --liveness), added by
# #7481 and reviewed into existence: those ~200 lines shipped with zero behavioural coverage,
# and eight independent mutations of them left every other suite in the PR fully green —
# including dropping `level:fatal` (which reopens #7481 defect 1, false-FAILing every
# rehearsal), dropping `field=detail` (the verdict-without-a-cause incident this route exists
# to end), and un-pinning PINNED_ORG (defect 2, verbatim).
#
# WHY A CURL SPY. Every one of those mutations perturbs the OUTBOUND REQUEST and nothing else
# — same exit code, same stdout shape, same everything a stubbed-reader test can see. The
# only assertion surface that can distinguish them is the argv the SUT hands curl, so that is
# what this suite reads. A stub that answered identically regardless of arguments would be
# the "fixture cannot express the difference" shape the repo's own learnings name.
#
# Run: bash scripts/sentry-issue-discover.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$ROOT/scripts/sentry-issue.sh"
TMP="$(mktemp -d -t sidisc.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0; fails=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1)); FAILURES+=("$1")
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

printf '\n=== sentry-issue discover modes ===\n\n'
[[ -r "$SUT" ]] || { echo "SUT not readable at $SUT" >&2; exit 2; }

# A curl spy: records the full argv, returns a canned discover body, exits with $SPY_HTTP.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'SPY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SPY_ARGV"
_out=""; _prev=""
for a in "$@"; do [[ "$_prev" == "-o" ]] && _out="$a"; _prev="$a"; done
[[ -n "$_out" ]] && printf '%s' "${SPY_BODY:-{\"data\":[]\}}" > "$_out"
printf '%s' "${SPY_HTTP:-200}"
exit 0
SPY
chmod +x "$TMP/bin/curl"

ARGV="$TMP/argv.txt"
run() {  # $1 = SPY_HTTP, rest = SUT args
  local http="$1"; shift
  : > "$ARGV"
  PATH="$TMP/bin:$PATH" SPY_ARGV="$ARGV" SPY_HTTP="$http" \
    SENTRY_ISSUE_RO_TOKEN='ro-fake-not-a-credential' \
    bash "$SUT" "$@" 2>"$TMP/err" ; echo $? > "$TMP/rc"
}
rc() { cat "$TMP/rc"; }
argv() { cat "$ARGV" 2>/dev/null; }

H=soleur-git-data-rehearsal-30649892865

# ── the query composition — the half no stubbed-reader test can see ────────────────
run 200 --host-events "$H" --stats-period 30d >/dev/null
if argv | grep -qF -- "query=host_name:${H} level:fatal"; then
  pass "host-events filters on level:fatal AT THE EVENT LEVEL (#7481 defect 1)"
else
  fail "host-events filters on level:fatal AT THE EVENT LEVEL (#7481 defect 1)" "$(argv | head -1)"
fi
for f in timestamp level host_name stage rc detail; do
  if argv | grep -qF -- "field=$f"; then
    pass "host-events projects field=$f"
  else
    fail "host-events projects field=$f" "dropping field=detail restores the verdict-without-a-cause incident"
  fi
done

# ── the pins — defect 2, on all three operands ────────────────────────────────────
if argv | grep -qF -- 'project=4511404943671376'; then pass "the project id is PINNED into the request"; else
  fail "the project id is PINNED into the request" "$(argv | head -1)"; fi
if argv | grep -qF -- 'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/'; then
  pass "org AND host are pinned into the URL"
else
  fail "org AND host are pinned into the URL" "$(argv | head -1)"; fi
# ...and a hostile environment cannot move any of them. This is defect 2's actual test:
# the caller runs under `doppler run -c prd_terraform`, which exports the whole config.
: > "$ARGV"
PATH="$TMP/bin:$PATH" SPY_ARGV="$ARGV" SPY_HTTP=200 \
  SENTRY_ISSUE_RO_TOKEN='ro-fake' SENTRY_ORG='attacker-org' SENTRY_API_HOST='evil.example.com' \
  bash "$SUT" --host-events "$H" --stats-period 30d >/dev/null 2>&1
if argv | grep -qF 'jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/' \
   && ! argv | grep -qF 'evil.example.com' && ! argv | grep -qF 'attacker-org'; then
  pass "SENTRY_ORG and SENTRY_API_HOST in the environment CANNOT redirect a discover read"
else
  fail "SENTRY_ORG and SENTRY_API_HOST in the environment CANNOT redirect a discover read" "$(argv | head -1)"
fi

# ── the liveness anchor must EXCLUDE its host, or it is vacuous when it matters ────
run 200 --liveness "$H" --stats-period 90d >/dev/null
if argv | grep -qF -- "query=!host_name:${H}"; then
  pass "liveness EXCLUDES the anchored host (a bare host_name: makes it vacuous)"
else
  fail "liveness EXCLUDES the anchored host (a bare host_name: makes it vacuous)" "$(argv | head -1)"
fi
if argv | grep -qF -- 'field=count()' && ! argv | grep -qF -- 'field=detail'; then
  pass "liveness projects a COUNT only — never event content into a public artifact"
else
  fail "liveness projects a COUNT only — never event content into a public artifact" "$(argv | head -1)"
fi

# ── the terminal exit contract: 401 and 403 are DISTINCT and not retryable ─────────
run 401 --host-events "$H" --stats-period 30d >/dev/null
if [[ "$(rc)" == "77" ]]; then pass "401 exits 77 (distinct, terminal)"; else
  fail "401 exits 77 (distinct, terminal)" "rc=$(rc)"; fi
run 403 --host-events "$H" --stats-period 30d >/dev/null
if [[ "$(rc)" == "78" ]]; then pass "403 exits 78 (distinct, terminal)"; else
  fail "403 exits 78 (distinct, terminal)" "rc=$(rc)"; fi
if grep -q 'DETERMINISTIC' "$TMP/err"; then pass "a terminal refusal SAYS it is deterministic"; else
  fail "a terminal refusal SAYS it is deterministic" "$(head -1 "$TMP/err")"; fi

# ── shape before count: a 200 whose body is not a discover object must not read clean ──
: > "$ARGV"
PATH="$TMP/bin:$PATH" SPY_ARGV="$ARGV" SPY_HTTP=200 SPY_BODY='<html>captive portal</html>' \
  SENTRY_ISSUE_RO_TOKEN='ro-fake' bash "$SUT" --host-events "$H" --stats-period 30d >/dev/null 2>"$TMP/err"
if [[ "$?" != "0" ]] || grep -q 'not a discover result object' "$TMP/err"; then
  pass "an HTTP 200 with a non-discover body is refused, not read as zero events"
else
  fail "an HTTP 200 with a non-discover body is refused, not read as zero events" "$(head -1 "$TMP/err")"
fi

# ── input validation: the host is interpolated into a search query ─────────────────
for bad in 'a b' 'a"b' 'x AND level:info' '../etc'; do
  PATH="$TMP/bin:$PATH" SPY_ARGV="$ARGV" bash "$SUT" --host-events "$bad" --stats-period 30d >/dev/null 2>&1
  if [[ "$?" == "64" ]]; then pass "a host name outside the charset is refused: [$bad]"; else
    fail "a host name outside the charset is refused: [$bad]" "rc=$?"; fi
done
PATH="$TMP/bin:$PATH" bash "$SUT" --host-events "$H" --start 2026-01-01T00:00:00 >/dev/null 2>&1
[[ "$?" == "64" ]] && pass "--start without --end is refused (Sentry rejects one without the other)" \
                   || fail "--start without --end is refused"
PATH="$TMP/bin:$PATH" bash "$SUT" --host-events "$H" --start 2026-01-01T00:00:00 --end 2026-01-02T00:00:00 --stats-period 30d >/dev/null 2>&1
[[ "$?" == "64" ]] && pass "--stats-period and --start/--end are mutually exclusive" \
                   || fail "--stats-period and --start/--end are mutually exclusive"

# ── ADMISSIBILITY: the window the CAPTURE SCRIPT builds must parse here ────────────
# The consult maps `--window '30 DAY'` to a Sentry stats-period. Nothing pinned the mapping,
# so `${n} DAY` instead of `${n}d` would make EVERY consult exit 64 in production while the
# capture suite — which stubs this reader — stayed green. That is #7481's originating
# incident restored. This arm runs the REAL parser against the REAL producer's output.
CAP="$ROOT/scripts/followthroughs/git-data-rung2-evidence-capture.sh"
if [[ -r "$CAP" ]]; then
  _w=$(sed -n '/^_sentry_window_args() {/,/^}/p' "$CAP")
  _args=$(SENTRY_SINCE="" WINDOW="30 DAY"; eval "$_w"; _sentry_window_args | tr '\n' ' ')
  PATH="$TMP/bin:$PATH" SPY_ARGV="$ARGV" SPY_HTTP=200 SENTRY_ISSUE_RO_TOKEN='ro-fake' \
    bash "$SUT" --host-events "$H" $_args >/dev/null 2>"$TMP/err"
  if [[ "$?" != "64" ]]; then
    pass "the window the capture script emits is ADMISSIBLE to this reader ($_args)"
  else
    fail "the window the capture script emits is ADMISSIBLE to this reader" "$_args -> $(head -1 "$TMP/err")"
  fi
else
  fail "the capture script is readable (admissibility arm could not run)"
fi

# ── anti-vacuity ──────────────────────────────────────────────────────────────────
# THE FLOOR EXITS DIRECTLY — it does NOT route through fail() or the FAILURES ledger.
# Caught by scripts/guard-vacuity-floor, which exists for exactly this: a floor pushed onto
# the same ledger the verdict reads is disarmed by the one edit that disarms every assertion
# it was written to backstop, so it exits 0 under a neutered assertion machinery. This suite
# was written to close a vacuity and shipped carrying one.
_ran=$((passes + fails))
if [[ "$_ran" -lt 23 ]]; then
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 23.\n' "$_ran" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor 23)\n' "$_ran"
# Same discipline: the reconciliation exits directly rather than recording a failure through
# the mechanism whose tampering it is detecting.
if [[ "${#FAILURES[@]}" -ne "$fails" ]]; then
  printf '  FAIL LEDGER: %s counted but %s recorded — fail() was tampered with.\n' "$fails" "${#FAILURES[@]}" >&2
  exit 1
fi
printf '\nsentry-issue-discover: %d passed, %d failed\n\n' "$passes" "$fails"
exit $(( ${#FAILURES[@]} > 0 ))
