#!/usr/bin/env bash
# Exit-code harness for ship-merge-mergebase-verdict-8151.sh (AC-PM1 for #8091).
#
# The probe's exit code IS its authorization artifact: sweep-followthroughs.sh
# closes the tracker on 0, comments+leaves-open on 1, retries on anything else.
# The cardinal sins are a vacuous exit 0 (closing AC-PM1 before any qualifying
# event-ship-merge run) and a spurious exit 1 firing on a webhook-receipt row
# that merely QUOTES the defect markers (the #6475 contamination shape — every
# live hit for these strings so far has been a `"caller":"api"` echo).
#
# FIXTURE FIDELITY: Better Stack's `raw` column is the full journald JSON and
# betterstack-query.sh emits it via FORMAT JSONEachRow, so inner quotes arrive
# backslash-ESCAPED on stdout. The fixtures reproduce that shape. The mock is
# faithful to betterstack-query.sh: server-side `raw LIKE '%term%'` runs against
# the UNescaped column, so the mock matches each --grep term against a
# backslash-stripped copy of the line while emitting the original.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/ship-merge-mergebase-verdict-8151.sh"
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
  out="$(env "$@" ACPM1_BQ="$MOCK" "$SUT" 2>&1)" || rc=$?
  LAST_OUT="$out"
  if [[ "$rc" -eq "$expected" ]]; then pass "$desc (exit=$rc)"
  else fail "$desc -- expected exit=$expected got exit=$rc :: ${out:0:240}"; fi
}

# Fixture rows -- synthesized only (cq-test-fixtures-synthesized-only). The .raw
# value is the double-encoded journald JSON emitted by betterstack-query.sh.
pass_row() {
  printf '{"dt":"2026-09-19T13:00:00Z","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"doppler\\",\\"message\\":\\"ship-merge workspace has origin/main...HEAD merge-base\\",\\"host_name\\":\\"soleur-web-platform\\"}"}\n'
}
fail_a_row() {
  printf '{"dt":"2026-09-19T13:05:00Z","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"doppler\\",\\"message\\":\\"checkout-pr failed: no merge-base origin/main HEAD after unshallow\\",\\"host_name\\":\\"soleur-web-platform\\"}"}\n'
}
echo_row() {  # webhook receipt echoing BOTH markers -- the #6475 shape
  printf '{"dt":"2026-09-19T13:10:00Z","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"doppler\\",\\"message\\":\\"{\\"caller\\":\\"api\\",\\"event\\":{\\"data\\":{\\"action\\":\\"opened\\",\\"deliveryId\\":\\"abc\\",\\"body\\":\\"plan says: no merge-base origin/main HEAD after unshallow ; ship-merge workspace has origin/main...HEAD merge-base ; git fetch --unshallow origin failed\\"}}}\\",\\"host_name\\":\\"soleur-web-platform\\"}"}\n'
}

# 1. PASS -- one runtime mergeBaseOk row, zero non-echo defect rows.
{ pass_row; } > "$WORK/fx-pass.json"
make_mock "$WORK/fx-pass.json" 0
run_case "one mergeBaseOk row -> PASS (AC-PM1 satisfied)" 0
printf '%s' "$LAST_OUT" | grep -q 'AC-PM1' || fail "PASS output names the acceptance criterion"

# 2. TRANSIENT -- zero rows (no qualifying run yet).
: > "$WORK/fx-zero.json"
make_mock "$WORK/fx-zero.json" 0
run_case "zero rows (no qualifying run yet) -> TRANSIENT" 2

# 3. FAIL -- one real defect row (non-echo shape).
{ fail_a_row; } > "$WORK/fx-fail.json"
make_mock "$WORK/fx-fail.json" 0
run_case "runtime 'no merge-base after unshallow' row -> FAIL" 1

# 4. Contamination (load-bearing) -- a webhook receipt quoting BOTH the pass
#    marker and both defect markers must neither PASS nor FAIL.
{ echo_row; } > "$WORK/fx-echo.json"
make_mock "$WORK/fx-echo.json" 0
run_case "webhook echo quoting all markers -> TRANSIENT (excluded from every arm)" 2

# 5. Contamination mixed with a real pass row -- echo still excluded, pass counts.
{ pass_row; echo_row; fail_a_row; } > "$WORK/fx-mixed.json"
# The fail_a_row here is non-echo so this MUST be FAIL, not PASS.
make_mock "$WORK/fx-mixed.json" 0
run_case "real defect row + echo + pass row -> FAIL precedence over PASS" 1

# 6. TRANSIENT -- query fault.
make_mock "$WORK/fx-pass.json" 3
run_case "betterstack-query fault -> TRANSIENT" 2

# 7. Fault on pass-marker query only, fail markers clean: TRANSIENT (can't prove PASS).
make_mock "$WORK/fx-zero.json" 0 'ship-merge workspace has origin/main'
run_case "pass-marker query fault alone -> TRANSIENT" 2

# 8. Env gate -- missing creds -> TRANSIENT (never a FAIL page).
run_case "creds unset -> TRANSIENT" 2 BETTERSTACK_QUERY_HOST= BETTERSTACK_QUERY_USERNAME= BETTERSTACK_QUERY_PASSWORD=

# 9. Window validation.
run_case "invalid ACPM1_WINDOW -> TRANSIENT" 2 ACPM1_WINDOW=banana

printf '\n%d/%d passed\n' "$((total - fails))" "$total"
[[ $fails -eq 0 ]]
