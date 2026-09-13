#!/usr/bin/env bash
# Exit-code harness for bwrap-probe-selfreport-8016.sh (#8016 soak / next-occurrence arms).
#
# The follow-through's exit code IS its authorization artifact: sweep-followthroughs.sh closes
# #8016 on 0, comments+leaves-open on 1, retries on anything else. The cardinal sins are a
# vacuous exit 0 that closes #8016 while a rollback is live or before the marker has been
# exercised, and a spurious exit 1 that pages on a clean window. Every case pins one arm.
#
# FIXTURE FIDELITY: Better Stack's `raw` column is the full journald JSON and
# betterstack-query.sh emits it via FORMAT JSONEachRow, so inner quotes arrive backslash-ESCAPED
# on stdout. The fixtures reproduce that shape. The mock is faithful to betterstack-query.sh:
# server-side `raw LIKE '%term%'` runs against the UNescaped column, so the mock matches each
# --grep term against a backslash-stripped copy of the line while emitting the original.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/bwrap-probe-selfreport-8016.sh"
fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

# Instrument self-test (ADR-193): both counters must move before any verdict is trusted.
_p0=$total; pass "instrument: pass() moves the counter" >/dev/null; _f0=$fails
fail "instrument: fail() moves the counter" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move their counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

export BETTERSTACK_QUERY_HOST=dummy-host
export BETTERSTACK_QUERY_USERNAME=dummy-user
export BETTERSTACK_QUERY_PASSWORD=dummy-pass

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
MOCK="$WORK/mock-bq.sh"

# make_mock <fixture-file> <exit-rc> [<fault-term>]
make_mock() {
  local fixture="$1" rc="$2" fault_term="${3:-}"
  cat > "$MOCK" <<MOCKEOF
#!/usr/bin/env bash
set -uo pipefail
terms=()
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --grep) terms+=("\$2"); shift 2 ;;
    --since|--until|--limit|--table|--table-s3) shift 2 ;;
    *) shift ;;
  esac
done
if [[ $rc -ne 0 ]]; then exit $rc; fi
fault_term='$fault_term'
if [[ -n "\$fault_term" ]]; then
  for t in "\${terms[@]}"; do [[ "\$t" == "\$fault_term" ]] && exit 3; done
fi
while IFS= read -r line; do
  probe="\${line//\\\\/}"
  for t in "\${terms[@]}"; do
    if [[ "\$probe" == *"\$t"* ]]; then printf '%s\n' "\$line"; break; fi
  done
done < "$fixture"
exit 0
MOCKEOF
  chmod 0755 "$MOCK"
}

# run_case <desc> <expected-rc> [env assignments...]
run_case() {
  local desc="$1" expected="$2"; shift 2
  local rc=0 out
  out="$(env "$@" BWRAP_SOAK_BQ="$MOCK" "$SUT" 2>&1)" || rc=$?
  LAST_OUT="$out"
  if [[ "$rc" -eq "$expected" ]]; then pass "$desc (exit=$rc)"
  else fail "$desc -- expected exit=$expected got exit=$rc :: ${out:0:240}"; fi
}

ok_row() { # <n> -> one synthesized SANDBOX_PROBE_OK row
  printf '{"dt":"2026-09-1%dT09:00:00Z","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"ci-deploy\\",\\"MESSAGE\\":\\"SANDBOX_PROBE_OK: bwrap sandbox verified in 10.0.1.30:5000/jikig-ai/soleur-web-platform:v0.266.%d rc=0 ms=41 cstate=running err_chars=0 bwrap_err=\\\\\\"<empty>\\\\\\"\\",\\"host\\":\\"soleur-web-platform\\"}"}\n' $(( n % 10 )) "$1"
}
n=2
gen_ok_rows() { local i; for (( i = 0; i < $1; i++ )); do ok_row "$i"; done; }

# 1. PASS -- 25 OK rows (>= default 20), zero rollbacks.
gen_ok_rows 25 > "$WORK/fx-pass.json"
make_mock "$WORK/fx-pass.json" 0
run_case "25 OK rows, zero rollbacks -> PASS (soak arm)" 0
printf '%s' "$LAST_OUT" | grep -q 'PASS: 25 deploys' || fail "PASS output names the liveness count"

# 2. TRANSIENT -- marker live but under-exercised (5 OK rows < 20).
gen_ok_rows 5 > "$WORK/fx-few.json"
make_mock "$WORK/fx-few.json" 0
run_case "5 OK rows < MIN_DEPLOYS -> TRANSIENT (not a vacuous PASS)" 2
run_case "5 OK rows with MIN_DEPLOYS=5 -> PASS (threshold is a knob)" 0 BWRAP_SOAK_MIN_DEPLOYS=5
run_case "5 OK rows with MIN_DEPLOYS=6 -> TRANSIENT (boundary pinned)" 2 BWRAP_SOAK_MIN_DEPLOYS=6

# 3. FAIL (load-bearing alarm) -- one real rollback row among 25 OK rows. Also asserts the
#    comment carries the trusted fields and NOT the free-text bwrap_err (public issue).
{ gen_ok_rows 25
  printf '{"dt":"2026-09-13T22:31:56Z","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"ci-deploy\\",\\"MESSAGE\\":\\"DEPLOY_ROLLBACK: bwrap sandbox non-functional in 10.0.1.30:5000/jikig-ai/soleur-web-platform:v0.266.9 rc=137 ms=30012 cstate=exited err_chars=0 bwrap_err=\\\\\\"SECRETISH_FREE_TEXT rc=0\\\\\\"\\",\\"host\\":\\"soleur-web-platform\\"}"}\n'
} > "$WORK/fx-fail.json"
make_mock "$WORK/fx-fail.json" 0
run_case "one rollback row among clean deploys -> FAIL (next-occurrence arm)" 1
if printf '%s' "$LAST_OUT" | grep -q 'rc=137 ms=30012 cstate=exited err_chars=0'; then pass "FAIL output carries the trusted fields"
else fail "FAIL output lacks trusted fields :: ${LAST_OUT:0:300}"; fi
if printf '%s' "$LAST_OUT" | grep -q 'SECRETISH_FREE_TEXT'; then fail "FAIL output reprinted bwrap_err free text into a public comment"
else pass "FAIL output withholds bwrap_err free text (query pointer instead)"; fi
if printf '%s' "$LAST_OUT" | grep -qE '^  [^ ]+ rc=137'; then pass "trusted rc read from the region BEFORE bwrap_err (not the forged rc=0 inside it)"
else fail "trusted-field extraction shape wrong :: ${LAST_OUT:0:300}"; fi

# 4. FAIL-precedence -- rollback present, liveness query faults. Must still be FAIL.
make_mock "$WORK/fx-fail.json" 0 'SANDBOX_PROBE_OK: bwrap sandbox verified'
run_case "rollback not masked by a liveness-query fault -> FAIL (not TRANSIENT)" 1

# 5. TRANSIENT -- query fault on the rollback query.
make_mock "$WORK/fx-pass.json" 3
run_case "betterstack-query fault -> TRANSIENT" 2

# 6. TRANSIENT -- zero rows at all (source dark).
: > "$WORK/fx-zero.json"
make_mock "$WORK/fx-zero.json" 0
run_case "zero rows (source dark / marker not live) -> TRANSIENT" 2

# 7. Contamination (load-bearing) -- a doppler-tagged webhook row quoting BOTH markers must
#    neither count as liveness nor fire the alarm.
{ gen_ok_rows 25
  printf '{"dt":"2026-09-13T10:00:00Z","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"doppler\\",\\"MESSAGE\\":\\"GitHub webhook issue body quotes: DEPLOY_ROLLBACK: bwrap sandbox non-functional and SANDBOX_PROBE_OK: bwrap sandbox verified\\",\\"host\\":\\"soleur-web-platform\\"}"}\n'
} > "$WORK/fx-contam.json"
make_mock "$WORK/fx-contam.json" 0
run_case "webhook contamination row does not false-alarm -> PASS" 0
{ gen_ok_rows 3
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    printf '{"dt":"2026-09-13T10:%02d:00Z","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"doppler\\",\\"MESSAGE\\":\\"quote: SANDBOX_PROBE_OK: bwrap sandbox verified\\",\\"host\\":\\"x\\"}"}\n' "$i"
  done
} > "$WORK/fx-contam-liveness.json"
make_mock "$WORK/fx-contam-liveness.json" 0
run_case "20 contamination rows do not inflate liveness past 3 real -> TRANSIENT" 2

# 8. TRANSIENT -- creds unset. Must be 2, never 1.
make_mock "$WORK/fx-pass.json" 0
rc=0
out="$(env -u BETTERSTACK_QUERY_HOST -u BETTERSTACK_QUERY_USERNAME -u BETTERSTACK_QUERY_PASSWORD BWRAP_SOAK_BQ="$MOCK" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "unset BETTERSTACK_QUERY_* -> TRANSIENT (exit=$rc, never 1)"
else fail "unset creds -- expected 2 got $rc :: ${out:0:200}"; fi

# 9. TRANSIENT -- bad knobs / missing BQ.
run_case "invalid BWRAP_SOAK_WINDOW -> TRANSIENT" 2 BWRAP_SOAK_WINDOW=bogus
run_case "invalid BWRAP_SOAK_MIN_DEPLOYS -> TRANSIENT" 2 BWRAP_SOAK_MIN_DEPLOYS=0
rc=0; out="$(BWRAP_SOAK_BQ="$WORK/nope.sh" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "missing BQ -> TRANSIENT"; else fail "missing BQ -- expected 2 got $rc"; fi

# 10. xtrace refusal (#7797): never 0/1 with a live credential and tracing on.
rc=0; out="$(bash -x "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 78 ]]; then pass "refuses to run under xtrace with a credential bound (exit=78)"
else fail "xtrace refusal -- expected 78 got $rc"; fi

if [[ "$fails" -gt 0 ]]; then echo "FAILED: $fails of $total case(s)" >&2; exit 1; fi
echo "OK: all $total bwrap-probe-selfreport-8016 arms passed"
