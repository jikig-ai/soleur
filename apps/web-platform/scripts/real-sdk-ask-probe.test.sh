#!/usr/bin/env bash
# Offline tests for real-sdk-ask-probe.sh — #10111 Part 1 (Guards 3 and 4 of the plan's Guard Contract).
#
# Run via:  bash apps/web-platform/scripts/real-sdk-ask-probe.test.sh
# No network, no key, no paid call: the probe is a stub script, `gh` is a stub that EXITS 64 on any argv the runner is not
# supposed to send, and the should-run fixtures are tiny real git repos. All fixtures are synthesized (cq-test-fixtures-synthesized-only);
# the "API key" planted for the redaction row is assembled from fragments so no scanner sees a token-shaped literal.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/real-sdk-ask-probe.sh"
PROBE_SRC="$SCRIPT_DIR/dev-probe-destroy-ask.ts"
BUDGET_SRC="$SCRIPT_DIR/lib/probe-budget.ts"

if [[ ! -f "$RUNNER" ]]; then
  echo "ERROR: $RUNNER not found (RED: the runner does not exist yet)" >&2
  exit 1
fi

# Git hygiene: a hook-inherited GIT_* location would make the fixture repos operate on the real checkout.
while IFS= read -r v; do
  case "$v" in GIT_*) unset "$v" ;; esac
done < <(compgen -e)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# the verbatim body; see plugins/soleur/test/test-helpers.sh).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

T="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
trap 'rm -rf "$T"' EXIT
assert_fixture_dir "$T"
mkdir -p "$T/bin"

PASS=0
FAIL=0
ok() { echo "  pass: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { # name, command...
  local name="$1"; shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

# INSTRUMENT SELF-TEST: drive the tally and both verdict-owning helpers once with a must-pass and once with a must-fail input, in a subshell
# so the real counters are untouched, and read the result back. Reported with printf + exit, NOT through ok/bad/check/eq: a neutered
# instrument must stop the suite, and it cannot be allowed to vouch for itself.
st_tally="$( ( PASS=0; FAIL=0; ok a >/dev/null; bad b >/dev/null; echo "$PASS $FAIL" ) )"
st_check_ok="$( ( PASS=0; FAIL=0; check a true >/dev/null; echo "$PASS $FAIL" ) )"
st_check_bad="$( ( PASS=0; FAIL=0; check b false >/dev/null; echo "$PASS $FAIL" ) )"
st_eq_ok="$( ( PASS=0; FAIL=0; eq a x x >/dev/null; echo "$PASS $FAIL" ) )"
st_eq_bad="$( ( PASS=0; FAIL=0; eq b x y >/dev/null; echo "$PASS $FAIL" ) )"
if [[ "$st_tally" != "1 1" || "$st_check_ok" != "1 0" || "$st_check_bad" != "0 1" || "$st_eq_ok" != "1 0" || "$st_eq_bad" != "0 1" ]]; then
  printf 'FATAL: instrument self-test: tally "%s" (want "1 1"), check ok "%s" (want "1 0"), check must-fail "%s" (want "0 1"), eq ok "%s" (want "1 0"), eq must-fail "%s" (want "0 1")\n' \
    "$st_tally" "$st_check_ok" "$st_check_bad" "$st_eq_ok" "$st_eq_bad" >&2
  exit 1
fi

HOST_ONLY_LITERAL="host-only residual"
NOT_OBSERVED_LITERAL="production arrival not observed"
FORBIDDEN_LITERAL="verified in ""production"
FAKE_KEY="sk-ant-""api03-FAKEFAKEFAKEFAKEFAKE1234567890"

# ---------------------------------------------------------------------------------------------------------------------------------
# Stub probe: invocation N prints $SD/out.N (else out.last) and exits with $SD/rc.N (else rc.last); it records its budget env.
# ---------------------------------------------------------------------------------------------------------------------------------
cat >"$T/bin/probe-stub.sh" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
n=$(( $(cat "$d/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$d/count"
echo "${PROBE_RUN_BUDGET_USD-unset}|${NODE_ENV-unset}" >>"$d/env.log"
f="$d/out.$n"; [ -f "$f" ] || f="$d/out.last"
cat "$f"
r="$d/rc.$n"; [ -f "$r" ] || r="$d/rc.last"
exit "$(cat "$r")"
STUB
chmod +x "$T/bin/probe-stub.sh"

PROV_LINE="sdk=0.3.284 cli=2.1.284"
# gen_out <case-lines> <refs true|false> <total|-> <result line>
gen_out() {
  local n="$1" refs="$2" total="$3" result="$4" i
  echo "PROVENANCE $PROV_LINE node=v22.0.0 bun=1.4.4"
  for ((i = 1; i <= n; i++)); do
    echo "PROBE case-$i canUseToolCalls=[Bash] verdict=ok costUsd=0.1000 bashAttempted=true gateCalls=1 $PROV_LINE"
  done
  echo "PROBE remote-refs-unchanged=$refs $PROV_LINE"
  [[ "$total" == "-" ]] || echo "TOTAL costUsd=$total"
  echo "$result"
}
PASS_RESULT="RESULT: PASS ($PROV_LINE, cases-run=8)"

new_scn() { SD="$T/scn.$1"; rm -rf "$SD"; mkdir -p "$SD"; }
put() { # n out-text rc
  printf '%s\n' "$2" >"$SD/out.$1"
  printf '%s\n' "$3" >"$SD/rc.$1"
}

run_runner() { # uses $SD; sets RC
  rm -f "$T/gho" "$T/summary" "$T/probe.out"
  PROBE_CMD="bash $T/bin/probe-stub.sh" PROBE_OUT_FILE="$T/probe.out" GITHUB_OUTPUT="$T/gho" GITHUB_STEP_SUMMARY="$T/summary" \
    STUB_DIR="$SD" ANTHROPIC_API_KEY="${RUN_KEY-$FAKE_KEY}" GH_TOKEN="${RUN_GH_TOKEN-}" bash "${RUNNER_UNDER_TEST:-$RUNNER}" run >"$T/stdout" 2>"$T/stderr"
  RC=$?
}
gho() { sed -n "s/^$1=//p" "$T/gho" 2>/dev/null | tail -1; }
invocations() { cat "$SD/count" 2>/dev/null || echo 0; }

echo "== Guard 3: classify() — pass only for a complete passing matrix =="

new_scn pass; put last "$(gen_out 8 true 0.8000 "$PASS_RESULT")" 0
run_runner
eq "baseline: complete matrix is pass" "pass" "$(gho outcome)"
eq "baseline: reason is pass" "pass" "$(gho reason)"
eq "baseline: runner exits 0" "0" "$RC"
eq "baseline: cost is the measured total" "0.8000" "$(gho cost)"
eq "baseline: provenance is exposed" "$PROV_LINE" "$(gho provenance)"
eq "baseline: probe invoked exactly once" "1" "$(invocations)"
eq "baseline: probe sees NODE_ENV=test and no inherited budget" "unset|test" "$(head -1 "$SD/env.log")"

new_scn r1; put last "$(gen_out 8 true 0.8 "$PASS_RESULT")" 1
run_runner
eq "row1: RESULT PASS but exit 1 is not pass" "blind" "$(gho outcome)"
eq "row1: reason is contract-drift" "contract-drift" "$(gho reason)"
check "row1: runner exits non-zero" test "$RC" -ne 0

new_scn r2; put last "$(gen_out 8 true 0.8 "")" 0
run_runner
eq "row2: exit 0 with no RESULT line is blind" "blind" "$(gho outcome)"
eq "row2: reason is crash" "crash" "$(gho reason)"
check "row2: runner exits non-zero" test "$RC" -ne 0
eq "row2: no rerun for a crash" "1" "$(invocations)"

new_scn r3; put last "$(gen_out 8 true 0.8 "RESULT: PASS ($PROV_LINE, cases-run=7)")" 0
run_runner
eq "row3: cases-run=7 is not pass" "blind" "$(gho outcome)"

new_scn r4; put last "$(gen_out 5 true 0.5 "$PASS_RESULT")" 0
run_runner
eq "row4: only 5 case lines is not pass" "blind" "$(gho outcome)"

new_scn r5; put last "$(gen_out 8 false 0.8 "$PASS_RESULT")" 0
run_runner
eq "row5: remote-refs-unchanged=false is not pass" "blind" "$(gho outcome)"

new_scn r6; put last "$(gen_out 3 true 1.2 "RESULT: CANT-RUN:budget-exceeded ($PROV_LINE, cases-run=3)")" 3
run_runner
eq "row6: budget-exceeded is blind" "blind" "$(gho outcome)"
eq "row6: reason is budget-exceeded" "budget-exceeded" "$(gho reason)"
eq "row6: probe invoked exactly once (no budget retry)" "1" "$(invocations)"

new_scn r6b; put last "RESULT: CANT-RUN:no-anthropic-key" 3
run_runner
eq "row6b: no-anthropic-key is blind" "blind" "$(gho outcome)"
eq "row6b: reason is no-anthropic-key" "no-anthropic-key" "$(gho reason)"
eq "row6b: no rerun without a key" "1" "$(invocations)"

new_scn r7; put last "$(gen_out 8 true 0.8 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "row7: two CANT-RUN passes end blind" "blind" "$(gho outcome)"
eq "row7: reason is the enum value" "model-did-not-attempt-bash" "$(gho reason)"
eq "row7: probe invoked exactly twice" "2" "$(invocations)"
check "row7: runner exits non-zero" test "$RC" -ne 0

new_scn r8; put last "RESULT: DIAGNOSTIC ($PROV_LINE, cases-run=1)" 4
run_runner
eq "row8: exit 4 / DIAGNOSTIC is blind" "blind" "$(gho outcome)"
eq "row8: probe invoked once" "1" "$(invocations)"

new_scn r8d; put last "RESULT: DIAGNOSTIC ($PROV_LINE, cases-run=1)" 0
run_runner
eq "row8d: DIAGNOSTIC at exit 0 is blind" "blind" "$(gho outcome)"
eq "row8d: DIAGNOSTIC at a non-4 exit is contract drift, not diagnostic" "contract-drift" "$(gho reason)"
eq "row8d: no rerun" "1" "$(invocations)"
new_scn r8e; put last "RESULT: DIAGNOSTIC ($PROV_LINE, cases-run=1)" 3
run_runner
eq "row8e: DIAGNOSTIC at exit 3 is contract drift" "contract-drift" "$(gho reason)"

for rc_bad in 0 1 4; do
  new_scn r6rc$rc_bad; put last "$(gen_out 8 true 0.8 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" "$rc_bad"
  run_runner
  eq "CANT-RUN at exit $rc_bad (not 3) is blind" "blind" "$(gho outcome)"
  eq "CANT-RUN at exit $rc_bad (not 3) is contract drift, not the claimed reason" "contract-drift" "$(gho reason)"
  eq "CANT-RUN at exit $rc_bad (not 3) is not retried" "1" "$(invocations)"
done

new_scn r8b; put last "$(gen_out 8 true 0.8 "RESULT: FAIL ($PROV_LINE, cases-run=8)")" 1
run_runner
eq "FAIL + exit 1 is fail" "fail" "$(gho outcome)"
eq "FAIL reason is probe-fail" "probe-fail" "$(gho reason)"
eq "FAIL is not retried" "1" "$(invocations)"
check "FAIL: runner exits non-zero" test "$RC" -ne 0

new_scn r8c; put last "$(gen_out 8 true 0.8 "RESULT: FAIL ($PROV_LINE, cases-run=8)")" 0
run_runner
eq "RESULT FAIL but exit 0 is not fail and not pass" "blind" "$(gho outcome)"

echo "== Guard 3: RESULT PASS on top of a non-ok case verdict is contract drift (D3d) =="
for badv in MODEL-DID-NOT-TRY FAIL SANDBOX-NOT-ENGAGED UNCONTROLLED CANT-RUN:budget-exceeded; do
  new_scn pv_$badv; put last "$(gen_out 8 true 0.8 "$PASS_RESULT" | sed "s/^PROBE case-3 \(.*\)verdict=ok/PROBE case-3 \1verdict=$badv/")" 0
  run_runner
  check "verdict row: the mutated case line carries verdict=$badv" grep -q "verdict=$badv" "$T/probe.out"
  eq "verdict row: RESULT PASS with one case verdict=$badv is blind" "blind" "$(gho outcome)"
  eq "verdict row: ... and the reason is contract-drift" "contract-drift" "$(gho reason)"
  eq "verdict row: ... and it is not retried" "1" "$(invocations)"
done
new_scn pv_ctl; put last "$(gen_out 8 true 0.8 "$PASS_RESULT")" 0
run_runner
eq "verdict control: the same matrix with every verdict=ok is pass" "pass" "$(gho outcome)"

echo "== Guard 3: the rerun spends the REMAINING share of the single \$4 cap =="

new_scn r9; put 1 "$(gen_out 8 true 2.80 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
put 2 "$(gen_out 8 true 0.40 "$PASS_RESULT")" 0
run_runner
eq "row9: second invocation receives the remainder" "1.20|test" "$(sed -n 2p "$SD/env.log")"
eq "row9: rerun pass is pass" "pass" "$(gho outcome)"
eq "row9: reported cost is the sum of both passes" "3.2000" "$(gho cost)"
eq "row9: probe invoked exactly twice" "2" "$(invocations)"

new_scn r9b; put last "$(gen_out 8 true 3.80 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "row9b: remainder under \$1.00 means no rerun" "1" "$(invocations)"
eq "row9b: outcome is blind" "blind" "$(gho outcome)"

new_scn r9c; put 1 "$(gen_out 8 true 3.00 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
put 2 "$(gen_out 8 true 0.40 "$PASS_RESULT")" 0
run_runner
eq "row9c: remainder of exactly \$1.00 is still rerun" "1.00|test" "$(sed -n 2p "$SD/env.log")"
eq "row9c: ... and the probe ran twice" "2" "$(invocations)"

new_scn r9g; put 1 "$(gen_out 8 true 1.00 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
put 2 "$(gen_out 8 true - "$PASS_RESULT")" 0
run_runner
eq "row9g: the rerun passed" "pass" "$(gho outcome)"
eq "row9g: pass 2 printed no TOTAL, so the total is unknown and never a partial sum" "unknown" "$(gho cost)"
check "row9g: the summary records attempts: 2" grep -qF -- '- attempts: 2' "$T/summary"
new_scn r9h; put last "$(gen_out 8 true '0.8000 capBookedCases=2' "$PASS_RESULT")" 0
run_runner
eq "row9h: a TOTAL line that also carries capBookedCases still parses to its cost" "0.8000" "$(gho cost)"
check "row9h: a single attempt records attempts: 1" grep -qF -- '- attempts: 1' "$T/summary"

new_scn r9d; put last "$(gen_out 8 true 3.01 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "row9d: a remainder of \$0.99 (just under the \$1.00 floor) is not rerun" "1" "$(invocations)"
check "row9d: the log says why" grep -q 'not rerunning' "$T/stdout"

new_scn r9e; put last "$(gen_out 8 true - "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "row9e: pass-1 spend unknown (no TOTAL line) => no rerun (fail closed)" "1" "$(invocations)"
eq "row9e: ... only one budget env line was recorded, so pass 2 never saw a budget" "1" "$(wc -l <"$SD/env.log" | tr -d ' ')"
eq "row9e: outcome is blind" "blind" "$(gho outcome)"
eq "row9e: reason is the CANT-RUN reason" "model-did-not-attempt-bash" "$(gho reason)"
eq "row9e: cost is reported unknown" "unknown" "$(gho cost)"
check "row9e: the log names the unknown spend" grep -q 'spend is unknown' "$T/stdout"

new_scn r9f; put last "$(gen_out 8 true 'not-a-number' "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "row9f: an unparseable TOTAL is also unknown spend => no rerun" "1" "$(invocations)"

echo "== Guard 3: every retriable CANT-RUN reason is rerun once, on the remainder; the rest are not =="
for rr in sandbox-not-engaged grant-not-live grant-control-not-established case-count-below-floor model-did-not-attempt-bash; do
  new_scn retry_$rr; put last "$(gen_out 8 true 0.50 "RESULT: CANT-RUN:$rr ($PROV_LINE, cases-run=8)")" 3
  run_runner
  eq "retry $rr: probe invoked exactly twice" "2" "$(invocations)"
  eq "retry $rr: pass 2 received the remainder" "3.50|test" "$(sed -n 2p "$SD/env.log")"
  eq "retry $rr: the reason survives both passes" "$rr" "$(gho reason)"
  eq "retry $rr: cost is the sum of both passes" "1.0000" "$(gho cost)"
done
new_scn retry_enum; put last "$(gen_out 8 true 0.50 "RESULT: CANT-RUN:something-the-probe-invented ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "retry out-of-enum: probe invoked exactly twice (default is retriable)" "2" "$(invocations)"
eq "retry out-of-enum: the reason defaults to cant-run" "cant-run" "$(gho reason)"
for nr in budget-exceeded no-anthropic-key; do
  new_scn noretry_$nr; put last "$(gen_out 8 true 0.50 "RESULT: CANT-RUN:$nr ($PROV_LINE, cases-run=8)")" 3
  run_runner
  eq "no retry $nr: probe invoked exactly once" "1" "$(invocations)"
done

echo "== Guard 3: untrusted values never reach \$GITHUB_OUTPUT raw (row 10) =="

new_scn r10; put last "$(gen_out 8 true 'abc;rm -rf /' 'RESULT: CANT-RUN:evil"$(touch /tmp/pwn)" (x)')" 3
run_runner
eq "row10: out-of-enum reason falls back to cant-run" "cant-run" "$(gho reason)"
eq "row10: non-numeric cost becomes unknown" "unknown" "$(gho cost)"
check "row10: every \$GITHUB_OUTPUT line is a known key=value" bash -c "! grep -qvE '^(outcome|reason|cost|provenance)=[A-Za-z0-9._ =:/+-]*\$' '$T/gho'"
check "row10: no raw probe text reached \$GITHUB_OUTPUT" bash -c "! grep -qE 'evil|rm -rf|touch' '$T/gho'"

new_scn r10b; put last "$(gen_out 8 true 0.8 "$PASS_RESULT" | sed 's/^PROVENANCE .*/PROVENANCE sdk=1 cli=$(id)\n## owned/')" 0
run_runner
eq "row10b: a malformed provenance never reaches the output raw" "unknown" "$(gho provenance)"

echo "== Guard 3: must-PASS non-canonical shapes (H2) =="

new_scn h2a; put last "$(gen_out 9 true 0.9 "RESULT: PASS ($PROV_LINE, cases-run=9)" | sed 's/^PROBE case-9 /PROBE brand-new-case /')" 0
run_runner
eq "H2: 9 case lines, an unknown extra case and cases-run=9 is pass" "pass" "$(gho outcome)"

new_scn h2b; put 1 "$(gen_out 8 true 0.5 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
put 2 "$(gen_out 8 true 0.5 "$PASS_RESULT")" 0
run_runner
eq "H2: fail first pass, pass second is pass" "pass" "$(gho outcome)"
eq "H2: and the probe ran twice" "2" "$(invocations)"

echo "== Guard 3: redaction and user-visible strings =="

new_scn red; put last "$(gen_out 8 true 0.8 "$PASS_RESULT"; echo "leak: $FAKE_KEY and sk-""$(printf 'x%.0s' {1..30})")" 0
run_runner
check "redaction: the planted key is not in the artifact file" bash -c "! grep -qF '$FAKE_KEY' '$T/probe.out'"
check "redaction: the planted key is not in the summary" bash -c "! grep -qF '$FAKE_KEY' '$T/summary'"
check "redaction: the planted key is not in stdout/stderr" bash -c "! grep -qF '$FAKE_KEY' '$T/stdout' '$T/stderr'"
check "redaction: a generic sk- token is redacted too" bash -c "! grep -qE 'sk-x{20}' '$T/probe.out'"
check "redaction: the artifact still holds the probe lines" grep -q '^RESULT: PASS' "$T/probe.out"
check "summary carries the host-only residual" grep -qi "$HOST_ONLY_LITERAL" "$T/summary"
check "summary carries 'production arrival not observed'" grep -qi "$NOT_OBSERVED_LITERAL" "$T/summary"
check "summary never says verified in production" bash -c "! grep -qiF '$FORBIDDEN_LITERAL' '$T/summary' '$T/stdout' '$T/stderr'"

echo "== Guard 3: redaction retains the risk-shaped benign text and masks exact values (D3e) =="
JWT_FIX="eyJ""hbGciOiJIUzI1NiJ9.eyJ""zdWIiOiJwcm9iZSJ9.c2lnbmF0dXJlLXRva2Vu"
HEX64="$(printf 'a%.0s' {1..64})"
KEEP_PATH="/home/runner/work/soleur/soleur/apps/web-platform/scripts/dev-probe-destroy-ask.ts"
KEEP_DIGEST="sha256:$HEX64"
KEEP_HOSTPORT="probe.invalid:443"
KEEP_DOTFILE="libkeyring.so.1"
KEEP_WORD="ask-the-user-for-confirmation-before-deleting-things"
KEEP_WORD2="risk-ant-colony-survey-results-for-the-workspace"
new_scn redkeep; put last "$(gen_out 8 true 0.8 "$PASS_RESULT"
  echo "path: $KEEP_PATH"; echo "digest: $KEEP_DIGEST"; echo "endpoint: $KEEP_HOSTPORT"; echo "lib: $KEEP_DOTFILE"
  echo "prose: $KEEP_WORD"; echo "prose2: $KEEP_WORD2"
  echo "hdr: Authorization: Bearer opaquebearertoken123"; echo "jwt: $JWT_FIX"
  echo "bare: sk-""$(printf 'y%.0s' {1..30})"; echo "kv: key=sk-""$(printf 'z%.0s' {1..30})"; echo "ant: sk-ant-""api03-ZZZZZZZZZZZZZZZZZZ"
  echo "glued: tokenX""sk-ant-""api03-GGGGGGGGGGGGGGGGGG"; printf '%s\n' 'literal-nl: before\nsk-ant-''api03-NNNNNNNNNNNNNNNNNN'; echo "paren: (sk-ant-""oat01-PPPPPPPPPPPPPPPPPP)"
  echo "twice: sk-ant-""api03-AAAAAAAAAAAAAAAAAA and sk-ant-""api03-BBBBBBBBBBBBBBBBBB"
  echo "json: {\"authorization\":\"Bearer jsonbearertoken123456789\"}"; echo "lower: bearer lowerbearertoken123456789"; echo "upper: BEARER upperbearertoken123456789"
  echo "bear2: Bearer one111111111111111111 then Bearer two222222222222222222"
  echo "ghp: ghp_""$(printf 'h%.0s' {1..30})"; echo "gho: gho_""$(printf 'o%.0s' {1..30})"; echo "pat: github_pat_""$(printf 'p%.0s' {1..30})"
  echo "jwt2: $JWT_FIX and $JWT_FIX")" 0
run_runner
for keep in "$KEEP_PATH" "$KEEP_DIGEST" "$KEEP_HOSTPORT" "$KEEP_DOTFILE" "$KEEP_WORD" "$KEEP_WORD2"; do
  check "redaction keeps benign text: $keep" grep -qF -- "$keep" "$T/probe.out"
done
check "redaction masks the Authorization header value" bash -c "! grep -qF 'opaquebearertoken123' '$T/probe.out'"
check "redaction keeps the Authorization header name" grep -qF 'Authorization: Bearer <redacted>' "$T/probe.out"
check "redaction masks a JWT" bash -c "! grep -qF 'eyJ' '$T/probe.out'"
check "redaction masks a bare sk- token at the start of a value" bash -c "! grep -qE 'sk-y{20}' '$T/probe.out'"
check "redaction masks an sk- token after a non-alphanumeric boundary" bash -c "! grep -qE 'sk-z{20}' '$T/probe.out'"
check "redaction masks an sk-ant- token" bash -c "! grep -qF 'ZZZZZZZZ' '$T/probe.out'"
for tok in GGGGGGGGGG NNNNNNNNNN PPPPPPPPPP AAAAAAAAAA BBBBBBBBBB jsonbearertoken lowerbearertoken upperbearertoken one111111111 two222222222 hhhhhhhhhh oooooooooo pppppppppp; do
  check "redaction masks every occurrence shape: $tok" bash -c "! grep -qF -- '$tok' '$T/probe.out'"
done
eq "redaction masks both JWTs on one line (the /g flag)" "0" "$(grep -c 'eyJ' "$T/probe.out")"
eq "retention: every other probe line is untouched (case lines still 8)" "8" "$(grep -c '^PROBE case-' "$T/probe.out")"

OPAQUE_KEY='opq/key.with+meta*chars[1]\&x|y'
OPAQUE_GH='ghtok$(id)-with"quote&\1'
new_scn redexact; put last "$(gen_out 8 true 0.8 "$PASS_RESULT"; echo "leak1: $OPAQUE_KEY"; echo "leak2: $OPAQUE_GH twice $OPAQUE_GH"; echo "short: abc123")" 0
RUN_KEY="$OPAQUE_KEY" RUN_GH_TOKEN="$OPAQUE_GH" run_runner
check "exact value: the ANTHROPIC_API_KEY value (regex metacharacters included) is masked in the artifact" bash -c "! grep -qF -- \"\$1\" '$T/probe.out'" _ "$OPAQUE_KEY"
check "exact value: the GH_TOKEN value is masked in the artifact, both occurrences" bash -c "! grep -qF -- \"\$1\" '$T/probe.out'" _ "$OPAQUE_GH"
check "exact value: ... and in the summary" bash -c "! grep -qF -- \"\$1\" '$T/summary'" _ "$OPAQUE_GH"
check "exact value: ... and in stdout/stderr" bash -c "! grep -qF -- \"\$1\" '$T/stdout' '$T/stderr'" _ "$OPAQUE_KEY"
check "exact value: the masked line keeps its label" grep -qF 'leak2: <redacted> twice <redacted>' "$T/probe.out"
new_scn redshort; put last "$(gen_out 8 true 0.8 "$PASS_RESULT"; echo "note: abc123 and abc1234")" 0
RUN_KEY="abc123" RUN_GH_TOKEN="abc1234" run_runner
check "exact value: a credential value under 8 characters is not literal-masked (it would mangle ordinary text)" grep -qF 'note: abc123 and abc1234' "$T/probe.out"
new_scn redunset; put last "$(gen_out 8 true 0.8 "$PASS_RESULT"; echo "note: plain text stays")" 0
RUN_KEY="" RUN_GH_TOKEN="" run_runner
check "exact value: with no credential set nothing is masked and the run still passes" grep -qF 'note: plain text stays' "$T/probe.out"
eq "exact value: ... outcome pass" "pass" "$(gho outcome)"

new_scn sumfail; put last "$(gen_out 8 true 0.8 "RESULT: FAIL ($PROV_LINE, cases-run=8)")" 1
run_runner
check "fail summary carries the host-only residual" grep -qi "$HOST_ONLY_LITERAL" "$T/summary"
check "fail summary carries 'production arrival not observed'" grep -qi "$NOT_OBSERVED_LITERAL" "$T/summary"

echo "== Guard 3: constants mirror the probe (floor and cap) =="

probe_floor="$(sed -n 's/^const MIN_DEFAULT_CASES = \([0-9][0-9]*\);.*/\1/p' "$PROBE_SRC")"
runner_floor="$(sed -n 's/^MIN_CASES=\([0-9][0-9]*\).*/\1/p' "$RUNNER" | head -1)"
check "probe MIN_DEFAULT_CASES was found" test -n "$probe_floor"
eq "runner case floor equals the probe's MIN_DEFAULT_CASES" "$probe_floor" "$runner_floor"
budget_const="$(sed -n 's/^export const RUN_BUDGET_USD = \([0-9][0-9]*\);.*/\1/p' "$BUDGET_SRC")"
runner_budget="$(sed -n 's/^RUN_BUDGET_USD=\([0-9][0-9]*\).*/\1/p' "$RUNNER" | head -1)"
check "probe-budget.ts RUN_BUDGET_USD was found" test -n "$budget_const"
eq "runner RUN_BUDGET_USD equals probe-budget.ts" "$budget_const" "$runner_budget"

echo "== Guard 3 harness H1: a runner that always says pass must make the suite RED =="
sed '/^classify() {/a\  C_OUTCOME=pass; C_REASON=pass; C_RETRY=no; C_COST=0; C_PROV=unknown; return 0' "$RUNNER" >"$T/mutant-runner.sh"
check "H1: the mutant differs from the runner" bash -c "! cmp -s '$RUNNER' '$T/mutant-runner.sh'"
new_scn h1; put last "$(gen_out 8 true 0.8 "")" 0
RUNNER_UNDER_TEST="$T/mutant-runner.sh" run_runner
mutant_outcome="$(gho outcome)"
check "H1: the always-pass mutant is detected (row 2 sees pass instead of blind)" test "$mutant_outcome" = "pass"
new_scn h1real; put last "$(gen_out 8 true 0.8 "")" 0
run_runner
eq "H1: the real runner is not fooled by the same stub" "blind" "$(gho outcome)"

# ---------------------------------------------------------------------------------------------------------------------------------
# should-run: tiny REAL git repos (the diff, the fetch of the baseline and the lockfile reads are the behaviour under test)
# ---------------------------------------------------------------------------------------------------------------------------------
echo "== should-run =="

cat >"$T/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Stub gh: records every call, serves fixtures, and REFUSES (exit 64, argv logged to <stub-dir>/../gh-refused.log) any argv that is not
# exactly one of the invocations the runner is modelled to send. A runner that drifts to a new flag, a new endpoint or a different
# argument order is therefore red even if the drifted call would have worked against real gh.
d="${GH_STUB_DIR:?}"
mkdir -p "$d"
refused="$(dirname "$d")/gh-refused.log"
printf '%s\n' "$*" >>"$d/calls.log"
n=$(wc -l <"$d/calls.log")
refuse() { printf '%s\n' "$*" >>"$refused"; echo "stub gh: refused argv: $*" >&2; exit 64; }
REPO_FIXTURE="acme/widgets"
LBL="ci/real-sdk-ask-probe"
VIEW_JQ='(.comments | last | .body // "") | startswith("<!-- real-sdk-ask-probe:passed -->")'
T_REG_S="[ci/real-sdk-ask-probe] real-SDK ask probe regression"
T_BLIND_S="[ci/real-sdk-ask-probe] real-SDK ask probe blind"
for a in "$@"; do
  case "$a" in --body|-b|--body=*) refuse "$@" ;; esac
done
bodyfile=""
prev=""
for a in "$@"; do
  [ "$prev" = "--body-file" ] && bodyfile="$a"
  prev="$a"
done
[ -n "$bodyfile" ] && cp "$bodyfile" "$d/body.$n"
case "$1" in
  api)
    [ "$#" -eq 2 ] || refuse "$@"
    path="$2"
    if [[ "$path" =~ ^repos/[^/]+/[^/]+/actions/workflows/[^/]+/runs\? ]]; then
      case "$path" in *"branch=main"*) : ;; *) refuse "$@" ;; esac
      case "$path" in *"status=completed"*) : ;; *) refuse "$@" ;; esac
      case "$path" in *"per_page="*) : ;; *) refuse "$@" ;; esac
      [ -f "$d/api.fail" ] && exit 1
      cat "$d/runs.json"; exit 0
    elif [[ "$path" =~ ^repos/[^/]+/[^/]+/actions/runs/([0-9]+)/jobs(\?per_page=[0-9]+)?$ ]]; then
      id="${BASH_REMATCH[1]}"
      [ -f "$d/jobs.fail" ] && exit 1
      [ -f "$d/jobs.fail.$id" ] && exit 1
      if [ -f "$d/jobs.$id.json" ]; then cat "$d/jobs.$id.json"; else cat "$d/jobs.default.json"; fi
      exit 0
    fi
    refuse "$@" ;;
  issue)
    case "${2-}" in
      list)
        [ "$*" = "issue list --repo $REPO_FIXTURE --state open --label $LBL --limit 200 --json number,title" ] || refuse "$@"
        [ -f "$d/list.fail" ] && exit 1
        cat "$d/issues.json"; exit 0 ;;
      view)
        # issue view <N> --repo R --json comments --jq <exact expression>
        [ "$#" -eq 9 ] && [[ "$3" =~ ^[0-9]+$ ]] && [ "$4 $5 $6 $7 $8" = "--repo $REPO_FIXTURE --json comments --jq" ] && [ "$9" = "$VIEW_JQ" ] || refuse "$@"
        [ -f "$d/view.fail" ] && exit 1
        # The real expression runs over a fixture, so the marker semantics are exercised and not assumed.
        src="$d/comments.$3.json"; [ -f "$src" ] || src="$d/comments.default.json"
        jq -r "$9" <"$src"; exit $? ;;
      comment)
        # issue comment <N> --repo R --body-file <file>
        [ "$#" -eq 7 ] && [[ "$3" =~ ^[0-9]+$ ]] && [ "$4 $5 $6" = "--repo $REPO_FIXTURE --body-file" ] && [ -n "$7" ] || refuse "$@"
        exit 0 ;;
      close)
        # issue close <N> --repo R --reason completed
        [ "$#" -eq 7 ] && [[ "$3" =~ ^[0-9]+$ ]] && [ "$4 $5 $6 $7" = "--repo $REPO_FIXTURE --reason completed" ] || refuse "$@"
        exit 0 ;;
      create)
        # issue create --repo R --title <one of the two exact titles> --body-file F --label type/security --label domain/engineering --label <p1|p2> --label LBL
        [ "$#" -eq 16 ] || refuse "$@"
        [ "$3 $4 $5" = "--repo $REPO_FIXTURE --title" ] || refuse "$@"
        { [ "$6" = "$T_REG_S" ] && [ "${14}" = "priority/p1-high" ]; } || { [ "$6" = "$T_BLIND_S" ] && [ "${14}" = "priority/p2-medium" ]; } || refuse "$@"
        [ "$7" = "--body-file" ] && [ -n "$8" ] || refuse "$@"
        [ "$9 ${10} ${11} ${12} ${13} ${15} ${16}" = "--label type/security --label domain/engineering --label --label $LBL" ] || refuse "$@"
        echo "https://github.com/acme/widgets/issues/99"; exit 0 ;;
      *) refuse "$@" ;;
    esac ;;
  label)
    # label create <name> --repo R --color C --description D (the exact argv; "$*" flattens the description's spaces)
    [ "$*" = "label create $LBL --repo $REPO_FIXTURE --color D93F0B --description Scheduled real-SDK ask probe findings (ADR-284)" ] || refuse "$@"
    exit 0 ;;
  *) refuse "$@" ;;
esac
GHSTUB
chmod +x "$T/bin/gh"

lock_json() { # agent-sdk claude-code other
  printf '{"name":"web-platform","packages":{"node_modules/@anthropic-ai/claude-agent-sdk":{"version":"%s"},"node_modules/@anthropic-ai/claude-code":{"version":"%s"},"node_modules/left-pad":{"version":"%s"}}}\n' "$1" "$2" "$3"
}
repo_init() { # name -> $REPO
  REPO="$T/repo.$1"; rm -rf "$REPO"; mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" remote add origin "$REPO"
  mkdir -p "$REPO/apps/web-platform/server" "$REPO/docs"
  echo "readme" >"$REPO/README.md"
  echo "x" >"$REPO/docs/a.md"
  echo "x" >"$REPO/apps/web-platform/server/permission-callback.ts"
  lock_json 0.3.284 2.1.284 1.0.0 >"$REPO/apps/web-platform/package-lock.json"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "A"
}
repo_commit_lock() { # agent code other msg
  lock_json "$1" "$2" "$3" >"$REPO/apps/web-platform/package-lock.json"
  git -C "$REPO" commit -q -a -m "$4"
}
repo_commit_file() { # path msg
  echo "changed $RANDOM" >>"$REPO/$1"
  git -C "$REPO" commit -q -a -m "$2"
}
sha() { git -C "$REPO" rev-parse "$1"; }
ZERO="0000000000000000000000000000000000000000"

# runs_json <sha:conclusion[:event]>... -- ids are assigned 1001, 1002, ... in order (newest first), event defaults to push.
runs_json() {
  local first=1 e s rest concl ev id=1000
  printf '{"workflow_runs":['
  for e in "$@"; do
    id=$((id + 1)); s="${e%%:*}"; rest="${e#*:}"; concl="${rest%%:*}"; ev=push
    [[ "$rest" == *:* ]] && ev="${rest#*:}"
    [[ $first -eq 1 ]] || printf ','
    first=0
    printf '{"id":%s,"head_sha":"%s","event":"%s","conclusion":%s,"status":"completed"}' "$id" "$s" "$ev" "$( [[ "$concl" == null ]] && echo null || echo "\"$concl\"" )"
  done
  printf ']}\n'
}
# jobs_json <measured-step-conclusion|none> [job-name] : the jobs payload of one run. The step is the workflow's "Record that the probe measured"
# (it succeeds only when the probe reached pass or fail). `none` omits it (a skipped, billing-skip or blind run).
PSN="Record that the probe measured"
jobs_json() {
  local c="$1" jn="${2:-probe}"
  if [[ "$c" == none ]]; then
    printf '{"jobs":[{"name":"%s","steps":[{"name":"Set up job","conclusion":"success"},{"name":"Complete job","conclusion":"success"}]}]}\n' "$jn"
  else
    printf '{"jobs":[{"name":"%s","steps":[{"name":"Set up job","conclusion":"success"},{"name":"%s","conclusion":"%s"},{"name":"Complete job","conclusion":"success"}]}]}\n' "$jn" "$PSN" "$c"
  fi
}

run_should() { # event before head ; env: GD (gh stub dir). sets SR (run= value) and RC
  rm -f "$T/gho"
  (cd "$REPO" && PATH="$T/bin:$PATH" GH_STUB_DIR="$GD" GH_TOKEN=fake-token GITHUB_REPOSITORY=acme/widgets GITHUB_EVENT_NAME="$1" \
    PUSH_BEFORE_SHA="$2" GITHUB_SHA="$3" GITHUB_OUTPUT="$T/gho" bash "$RUNNER" should-run >"$T/sr.out" 2>"$T/sr.err")
  RC=$?
  SR="$(sed -n 's/^run=//p' "$T/gho" 2>/dev/null | tail -1)"
  SO="$(sed -n 's/^outcome=//p' "$T/gho" 2>/dev/null | tail -1)"
}
gd_new() { GD="$T/gh.$1"; rm -rf "$GD"; mkdir -p "$GD"; jobs_json success >"$GD/jobs.default.json"; printf '{"comments":[]}\n' >"$GD/comments.default.json"; }

# non-push events always run
repo_init ev; A=$(sha HEAD); repo_commit_file docs/a.md B; gd_new ev; runs_json "$A:success" >"$GD/runs.json"
for ev in schedule workflow_dispatch pull_request; do
  run_should "$ev" "$A" "$(sha HEAD)"
  eq "non-push event $ev -> run=true" "true" "$SR"
done
check "non-push events make no gh call" test ! -s "$GD/calls.log"

# all-zero before
run_should push "$ZERO" "$(sha HEAD)"
eq "all-zero before -> run=true" "true" "$SR"

# allowlisted code file changed
repo_init code; A=$(sha HEAD); repo_commit_file apps/web-platform/server/permission-callback.ts B; gd_new code; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "allowlisted code file changed -> run=true" "true" "$SR"
check "should-run asked the Actions API for the baseline" grep -q '^api repos/acme/widgets/actions/workflows/' "$GD/calls.log"

# lockfile-only, SDK did not move (another dep moved)
repo_init lk1; A=$(sha HEAD); repo_commit_lock 0.3.284 2.1.284 1.0.1 B; gd_new lk1; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "lockfile-only, SDK versions equal -> run=false" "false" "$SR"
eq "should-run exits 0 when skipping" "0" "$RC"

# lockfile-only, SDK moved
repo_init lk2; A=$(sha HEAD); repo_commit_lock 0.3.290 2.1.284 1.0.0 B; gd_new lk2; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "lockfile-only, agent SDK moved -> run=true" "true" "$SR"
repo_init lk2b; A=$(sha HEAD); repo_commit_lock 0.3.284 2.1.299 1.0.0 B; gd_new lk2b; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "lockfile-only, claude-code moved -> run=true" "true" "$SR"

# lockfile unreadable
repo_init lk3; A=$(sha HEAD); echo '{not json' >"$REPO/apps/web-platform/package-lock.json"; git -C "$REPO" commit -q -a -m B; gd_new lk3; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "unreadable head lockfile -> run=true" "true" "$SR"

# multi-commit range (grouped landing): code changed in the FIRST commit, lock-only in the last
repo_init multi; A=$(sha HEAD); repo_commit_file apps/web-platform/server/permission-callback.ts B; repo_commit_lock 0.3.284 2.1.284 1.0.2 C; gd_new multi; runs_json "$A:success" >"$GD/runs.json"
run_should push "$(sha HEAD~1)" "$(sha HEAD)"
eq "multi-commit range is diffed from the baseline, not just the last commit -> run=true" "true" "$SR"

# evicted push: SDK moved in B (its run was cancelled), C is lock-only non-SDK
repo_init evict; A=$(sha HEAD); repo_commit_lock 0.3.290 2.1.284 1.0.0 B; repo_commit_lock 0.3.290 2.1.284 1.0.1 C; gd_new evict
runs_json "$(sha HEAD~1):cancelled" "$A:success" >"$GD/runs.json"
run_should push "$(sha HEAD~1)" "$(sha HEAD)"
eq "evicted (cancelled) run does not hide an SDK move from a later lockfile-only push -> run=true" "true" "$SR"
# control: had B's run completed, the baseline is B and the same push is a legitimate skip
runs_json "$(sha HEAD~1):success" "$A:success" >"$GD/runs.json"
run_should push "$(sha HEAD~1)" "$(sha HEAD)"
eq "control: baseline = last completed run (B) -> run=false" "false" "$SR"

# in-progress runs (null conclusion) are not baselines either
runs_json "$(sha HEAD~1):null" "$A:success" >"$GD/runs.json"
run_should push "$(sha HEAD~1)" "$(sha HEAD)"
eq "a run with no conclusion is not a baseline -> run=true" "true" "$SR"

# baseline cannot be fetched
repo_init nofetch; A=$(sha HEAD); repo_commit_lock 0.3.284 2.1.284 1.0.1 B; gd_new nofetch
runs_json "1111111111111111111111111111111111111111:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "unfetchable baseline -> run=true" "true" "$SR"

# gh api fails / no completed run
repo_init apifail; A=$(sha HEAD); repo_commit_lock 0.3.284 2.1.284 1.0.1 B; gd_new apifail; runs_json "$A:success" >"$GD/runs.json"; : >"$GD/api.fail"
run_should push "$A" "$(sha HEAD)"
eq "baseline lookup error -> run=true" "true" "$SR"
gd_new norun; printf '{"workflow_runs":[]}\n' >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "no completed run yet -> run=true" "true" "$SR"

# only a non-allowlisted file plus a lock-only non-SDK change
repo_init docs; A=$(sha HEAD); repo_commit_file docs/a.md B; repo_commit_lock 0.3.284 2.1.284 1.0.1 C; gd_new docs; runs_json "$A:success" >"$GD/runs.json"
run_should push "$(sha HEAD~1)" "$(sha HEAD)"
eq "non-allowlisted file + non-SDK lock change -> run=false" "false" "$SR"

# plugin hooks glob
repo_init hooks; A=$(sha HEAD); mkdir -p "$REPO/plugins/soleur/hooks"; echo h >"$REPO/plugins/soleur/hooks/h.sh"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m B; gd_new hooks; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "a new file under plugins/soleur/hooks/ -> run=true" "true" "$SR"

echo "== should-run: not-run output (D1) =="
repo_init nr; A=$(sha HEAD); repo_commit_lock 0.3.284 2.1.284 1.0.1 B; gd_new nr; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "run=false also emits outcome=not-run" "not-run" "$SO"
eq "run=false: exactly two output lines (run, outcome)" "2" "$(wc -l <"$T/gho" | tr -d ' ')"
repo_init nr2; A=$(sha HEAD); repo_commit_lock 0.3.290 2.1.284 1.0.0 B; gd_new nr2; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "run=true emits no outcome line" "" "$SO"
eq "run=true: exactly one output line" "1" "$(wc -l <"$T/gho" | tr -d ' ')"
run_should schedule "$A" "$(sha HEAD)"
eq "a non-push event emits no outcome line" "" "$SO"

echo "== should-run: the baseline is the newest run that MEASURED (D2) =="
# A -> B (the agent SDK moves) -> C (lock-only, non-SDK). The push under test is B..C; the question is which run is the baseline.
mk_skip_repo() { repo_init "$1"; A=$(sha HEAD); repo_commit_lock 0.3.290 2.1.284 1.0.0 B; B=$(sha HEAD); repo_commit_lock 0.3.290 2.1.284 1.0.1 C; C=$(sha HEAD); gd_new "$1"; }
# R(B) newest, R(A) older. B's run did not execute the probe step (billing skip / run=false): not a baseline, so the SDK move in B is still unmeasured.
mk_skip_repo bs; runs_json "$B:success" "$A:success" >"$GD/runs.json"; jobs_json none >"$GD/jobs.1001.json"
run_should push "$B" "$C"
eq "a run whose probe step was skipped is not a baseline -> falls back to the older measuring run -> run=true" "true" "$SR"
check "the jobs endpoint was asked for the newest candidate first" grep -q '^api repos/acme/widgets/actions/runs/1001/jobs' "$GD/calls.log"
check "... and then for the next candidate" grep -q '^api repos/acme/widgets/actions/runs/1002/jobs' "$GD/calls.log"
jobs_json success >"$GD/jobs.1001.json"; : >"$GD/calls.log"
run_should push "$B" "$C"
eq "control: B's probe step succeeded -> B is the baseline -> lock-only non-SDK -> run=false" "false" "$SR"
jobs_json failure >"$GD/jobs.1001.json"
run_should push "$B" "$C"
eq "a measured step that did not succeed is not a measurement (a blind run: CANT-RUN, crash, timeout, budget stop) -> run=true" "true" "$SR"
jobs_json cancelled >"$GD/jobs.1001.json"
run_should push "$B" "$C"
eq "a probe step that was cancelled is not a measurement -> run=true" "true" "$SR"
jobs_json skipped >"$GD/jobs.1001.json"
run_should push "$B" "$C"
eq "a probe step with conclusion skipped is not a measurement -> run=true" "true" "$SR"
jobs_json success other-job >"$GD/jobs.1001.json"
run_should push "$B" "$C"
eq "the probe step in a job NOT named probe does not count -> run=true" "true" "$SR"
printf '{"jobs":[{"name":"probe","steps":[{"name":"Run the probe","conclusion":"success"}]}]}\n' >"$GD/jobs.1001.json"
run_should push "$B" "$C"
eq "a differently named step does not count -> run=true" "true" "$SR"
printf '{"jobs":[]}\n' >"$GD/jobs.1001.json"; printf '{"jobs":[]}\n' >"$GD/jobs.1002.json"
run_should push "$B" "$C"
eq "no jobs at all -> no baseline -> run=true" "true" "$SR"
echo 'not json' >"$GD/jobs.1001.json"; rm -f "$GD/jobs.1002.json"
run_should push "$B" "$C"
eq "an unparseable jobs payload -> run=true (fail toward running)" "true" "$SR"
# the first candidate errors; the NEXT one (B, measuring) would make this a legitimate skip, so only fail-toward-running yields run=true
runs_json "0000000000000000000000000000000000000002:success" "$B:success" >"$GD/runs.json"; jobs_json none >"$GD/jobs.1001.json"; : >"$GD/jobs.fail.1001"
run_should push "$B" "$C"
eq "a jobs API error on the first candidate -> run=true, even though the next candidate would qualify and skip" "true" "$SR"
rm -f "$GD/jobs.fail.1001"
run_should push "$B" "$C"
eq "control: the same list without the API error -> the next candidate (B) is the baseline -> run=false" "false" "$SR"
runs_json "$B:success" "$A:success" >"$GD/runs.json"

# event filter: a pull_request-event run is never a baseline
mk_skip_repo ev2; runs_json "$B:success:pull_request" "$A:success" >"$GD/runs.json"
run_should push "$B" "$C"
eq "a pull_request-event run is skipped as a baseline -> baseline A -> SDK moved in B -> run=true" "true" "$SR"
check "... and its jobs were never queried" bash -c "! grep -q 'runs/1001/jobs' '$GD/calls.log'"
# the run for this very head commit is never its own baseline
mk_skip_repo selfb; runs_json "$C:success" "$B:success" >"$GD/runs.json"
run_should push "$B" "$C"
eq "a run of the head sha itself is not a baseline (B is) -> run=false" "false" "$SR"

# candidate cap: 10 candidates are scanned, the 11th is never reached
mk_skip_repo cap
fake=0000000000000000000000000000000000000001
list=(); for i in $(seq 1 10); do list+=("$fake:success"); done
runs_json "${list[@]}" "$B:success" >"$GD/runs.json"
for i in $(seq 1 10); do jobs_json none >"$GD/jobs.$((1000 + i)).json"; done
run_should push "$B" "$C"
eq "ten non-measuring candidates exhaust the scan; the 11th is not consulted -> run=true" "true" "$SR"
check "... and exactly ten jobs lookups were made" test "$(grep -c '^api repos/acme/widgets/actions/runs/[0-9]*/jobs' "$GD/calls.log")" -eq 10
list=(); for i in $(seq 1 9); do list+=("$fake:success"); done
runs_json "${list[@]}" "$B:success" >"$GD/runs.json"; : >"$GD/calls.log"; jobs_json success >"$GD/jobs.1010.json"
run_should push "$B" "$C"
eq "control: the 10th candidate measures -> baseline B -> run=false" "false" "$SR"

# only skipped runs exist
mk_skip_repo allskip; runs_json "$B:success" "$A:success" >"$GD/runs.json"; jobs_json none >"$GD/jobs.default.json"
run_should push "$B" "$C"
eq "every candidate skipped -> no baseline -> run=true" "true" "$SR"

# --no-renames: an allowlisted file moved out of the allowlist must still count as changed
repo_init ren; A=$(sha HEAD)
mkdir -p "$REPO/docs/moved"; git -C "$REPO" mv apps/web-platform/server/permission-callback.ts docs/moved/permission-callback.ts
lock_json 0.3.284 2.1.284 1.0.5 >"$REPO/apps/web-platform/package-lock.json"; git -C "$REPO" commit -q -a -m rename
gd_new ren; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "an allowlisted file renamed out of the allowlist (plus a non-SDK lock change) -> run=true" "true" "$SR"

# both lockfile versions empty for an SDK package
repo_init noempty; A=$(sha HEAD)
printf '{"packages":{"node_modules/left-pad":{"version":"1.0.0"}}}\n' >"$REPO/apps/web-platform/package-lock.json"; git -C "$REPO" commit -q -a -m nolk1
A=$(sha HEAD); printf '{"packages":{"node_modules/left-pad":{"version":"1.0.1"}}}\n' >"$REPO/apps/web-platform/package-lock.json"; git -C "$REPO" commit -q -a -m nolk2
gd_new noempty; runs_json "$A:success" >"$GD/runs.json"
run_should push "$A" "$(sha HEAD)"
eq "SDK versions empty in BOTH lockfiles (equal but unknown) -> run=true, not a false skip" "true" "$SR"

echo "== should-run: parity with the SDK-bump gate and the allowlist members (D8b) =="
runner_pkgs="$(sed -n 's/^SDK_PACKAGES=(\([^)]*\)).*/\1/p' "$RUNNER" | head -1)"
gate_pkgs="$(sed -n 's/^SDK_PACKAGES=(\([^)]*\)).*/\1/p' "$SCRIPT_DIR/sdk-bump-sandbox-gate.sh" | head -1)"
check "the SDK-bump gate's SDK_PACKAGES list was found" test -n "$gate_pkgs"
eq "runner SDK_PACKAGES equals sdk-bump-sandbox-gate.sh's" "$gate_pkgs" "$runner_pkgs"

# derive the allowlist from the runner itself; never restate it
allow_members=()
while IFS= read -r m; do allow_members+=("$m"); done < <(
  awk '/^in_run_allowlist\(\)/{f=1} f&&/\) return [01] ;;$/{sub(/\) return [01] ;;$/,""); gsub(/^[ \t]+/,""); n=split($0,a,"|"); for(i=1;i<=n;i++) print a[i]} f&&/^}/{exit}' "$RUNNER")
check "the allowlist derivation found at least 12 members (floor: an empty parse must not vacuously pass)" test "${#allow_members[@]}" -ge 12
repo_init mem; A=$(sha HEAD); gd_new mem; runs_json "$A:success" >"$GD/runs.json"
mi=0
for m in "${allow_members[@]}"; do
  mi=$((mi + 1)); f="${m/\*/probe-member.sh}"
  git -C "$REPO" checkout -q -f -B "mem$mi" "$A"
  mkdir -p "$REPO/$(dirname "$f")"; echo "member $mi" >>"$REPO/$f"
  lock_json 0.3.284 2.1.284 "1.0.$((mi + 10))" >"$REPO/apps/web-platform/package-lock.json"
  git -C "$REPO" add -A; git -C "$REPO" commit -q -m "member $mi"
  run_should push "$A" "$(sha HEAD)"
  eq "mixed push: allowlist member $f + a non-SDK lock change -> run=true" "true" "$SR"
done
git -C "$REPO" checkout -q -f -B memctl "$A"
echo "x" >>"$REPO/docs/a.md"; lock_json 0.3.284 2.1.284 1.0.99 >"$REPO/apps/web-platform/package-lock.json"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m ctl
run_should push "$A" "$(sha HEAD)"
eq "mixed-push control: a non-allowlisted file + the same non-SDK lock change -> run=false" "false" "$SR"

# ---------------------------------------------------------------------------------------------------------------------------------
echo "== Guard 4: file-issue =="

T_REG="[ci/real-sdk-ask-probe] real-SDK ask probe regression"
T_BLIND="[ci/real-sdk-ask-probe] real-SDK ask probe blind"
ADR_LITERAL="ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md"
PM_LITERAL="2026-10-11-hosted-bash-ask-bypassed-by-sdk-auto-allow-postmortem.md"

# run_filer <outcome> <reason> <cost> [job-result] [provenance]; env ISSUES_JSON
run_filer() {
  gd_new filer; printf '%s' "${ISSUES_JSON:-[]}" >"$GD/issues.json"
  [ -n "${COMMENTS_FIXTURE:-}" ] && printf '%s\n' "$COMMENTS_FIXTURE" >"$GD/comments.default.json"
  [ -n "${VIEW_FAIL:-}" ] && : >"$GD/view.fail"
  PATH="$T/bin:$PATH" GH_STUB_DIR="$GD" GH_TOKEN=fake-token GITHUB_REPOSITORY=acme/widgets GITHUB_EVENT_NAME="${FILER_EVENT:-schedule}" \
    GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=4242 PROBE_OUTCOME="$1" PROBE_REASON="$2" PROBE_COST="$3" PROBE_JOB_RESULT="${4-}" \
    PROBE_PROVENANCE="${5-$PROV_LINE}" bash "${RUNNER_UNDER_TEST:-$RUNNER}" file-issue >"$T/f.out" 2>"$T/f.err"
  FRC=$?
}
calls() { awk -v v="$1" 'index($0, v) == 1 { n++ } END { print n + 0 }' "$GD/calls.log" 2>/dev/null || echo 0; }
all_calls() { wc -l <"$GD/calls.log" 2>/dev/null || echo 0; }
writes() { awk '/^issue (create|comment|close)/ { n++ } END { print n + 0 }' "$GD/calls.log" 2>/dev/null || echo 0; }
created_body() { cat "$GD"/body.* 2>/dev/null; }
issues() { # "num:title" ...
  local first=1 e
  printf '['
  for e in "$@"; do
    [[ $first -eq 1 ]] || printf ','
    first=0
    printf '{"number":%s,"title":"%s"}' "${e%%:*}" "${e#*:}"
  done
  printf ']'
}

# fail, nothing open -> create the regression issue (p1) with the full label set
ISSUES_JSON="[]" run_filer fail probe-fail 0.8000
eq "fail: one issue created" "1" "$(calls 'issue create')"
check "fail: floor — the stub recorded calls (H1)" test "$(all_calls)" -ge 2
check "fail: title is the exact regression title" grep -qF -- "--title $T_REG" "$GD/calls.log"
for lab in type/security domain/engineering priority/p1-high ci/real-sdk-ask-probe; do
  check "fail: carries label $lab" grep -qF -- "--label $lab" "$GD/calls.log"
done
check "fail: the label is created idempotently" grep -q '^label create ci/real-sdk-ask-probe' "$GD/calls.log"
check "fail: body goes through --body-file" grep -q -- '--body-file' "$GD/calls.log"
body="$(created_body)"
check "body names the host-only residual" bash -c "grep -qi '$HOST_ONLY_LITERAL' <<<\"\$1\"" _ "$body"
check "body names 'production arrival not observed'" bash -c "grep -qi '$NOT_OBSERVED_LITERAL' <<<\"\$1\"" _ "$body"
check "body links the ADR-284 C9 result" bash -c "grep -qF '$ADR_LITERAL' <<<\"\$1\"" _ "$body"
check "body links the 2026-10-11 post-mortem" bash -c "grep -qF '$PM_LITERAL' <<<\"\$1\"" _ "$body"
check "body links the run" bash -c "grep -qF 'https://github.com/acme/widgets/actions/runs/4242' <<<\"\$1\"" _ "$body"
check "body carries the SDK/CLI provenance" bash -c "grep -qF '$PROV_LINE' <<<\"\$1\"" _ "$body"
check "body never says verified in production" bash -c "! grep -qiF '$FORBIDDEN_LITERAL' <<<\"\$1\"" _ "$body"
eq "fail: exits 0 after filing" "0" "$FRC"

# row 1: a decoy whose title merely CONTAINS the real title is not adopted
ISSUES_JSON="$(issues "7:$T_REG (old copy)" "8:Re: $T_REG")" run_filer fail probe-fail 0.8
eq "row1: decoys are not adopted -> a new issue is created" "1" "$(calls 'issue create')"
eq "row1: nothing is commented on a decoy" "0" "$(calls 'issue comment')"

# row 3 / H2: an exact-title open issue is commented on, never duplicated
ISSUES_JSON="$(issues "7:$T_REG (old copy)" "12:$T_REG")" run_filer fail probe-fail 0.8
eq "row3: exact-title issue exists -> no second issue" "0" "$(calls 'issue create')"
eq "row3: one comment" "1" "$(calls 'issue comment')"
check "row3: the comment targets issue 12 (not the decoy)" grep -q '^issue comment 12 ' "$GD/calls.log"

# row 4: blind is p2, never p1
ISSUES_JSON="[]" run_filer blind cant-run 1.0
check "row4: blind title is exact" grep -qF -- "--title $T_BLIND" "$GD/calls.log"
check "row4: blind carries priority/p2-medium" grep -qF -- "--label priority/p2-medium" "$GD/calls.log"
check "row4: blind is not labelled p1" bash -c "! grep -qF 'priority/p1-high' '$GD/calls.log'"
body="$(created_body)"
check "blind body names the host-only residual" bash -c "grep -qi '$HOST_ONLY_LITERAL' <<<\"\$1\"" _ "$body"
check "blind body names 'production arrival not observed'" bash -c "grep -qi '$NOT_OBSERVED_LITERAL' <<<\"\$1\"" _ "$body"

# row 2: pass never closes the regression issue; the blind issue self-closes
ISSUES_JSON="$(issues "20:$T_REG" "21:$T_BLIND")" run_filer pass pass 0.8
check "row2: the blind issue is closed" grep -q '^issue close 21 ' "$GD/calls.log"
check "row2: the regression issue is NEVER closed" bash -c "! grep -q '^issue close 20' '$GD/calls.log'"
check "row2: the regression issue gets a 'subsequently passed' note" grep -q '^issue comment 20 ' "$GD/calls.log"
check "row2: the note says subsequently passed" bash -c "cat '$GD'/body.* | grep -qi 'subsequently passed'"
eq "row2: exactly one close" "1" "$(calls 'issue close')"
eq "row2: nothing created on a pass" "0" "$(calls 'issue create')"

# pass with nothing open writes nothing
ISSUES_JSON="[]" run_filer pass pass 0.8
eq "pass with no open issue performs no write" "0" "$(writes)"

# row 5: empty outcome (and a green probe job) -> no writes, non-zero
ISSUES_JSON="[]" run_filer "" "" "" success
eq "row5: empty outcome performs no gh write" "0" "$(writes)"
check "row5: empty outcome exits non-zero" test "$FRC" -ne 0

# row 6: skipped performs no gh call at all
ISSUES_JSON="$(issues "20:$T_REG" "21:$T_BLIND")" run_filer skipped none unknown
eq "row6: skipped performs no write" "0" "$(writes)"
check "row6: skipped exits 0" test "$FRC" -eq 0

# row 7: empty outcome + failed/cancelled probe job -> blind / no-outcome
for jr in failure cancelled; do
  ISSUES_JSON="[]" run_filer "" "" "" "$jr"
  eq "row7: empty outcome + job $jr files one blind issue" "1" "$(calls 'issue create')"
  check "row7: ($jr) the issue is the blind class" grep -qF -- "--title $T_BLIND" "$GD/calls.log"
  check "row7: ($jr) the body says no-outcome" bash -c "cat '$GD'/body.* | grep -qF 'no-outcome'"
done

# row 8: an injected reason never reaches the body
ISSUES_JSON="[]" run_filer blind $'x\n## owned' $'1.0\n## owned2'
check "row8: the injected heading is absent from the body" bash -c "! cat '$GD'/body.* | grep -q 'owned'"
check "row8: an issue was still filed" test "$(calls 'issue create')" -eq 1

# row 9: duplicate open blind issues
ISSUES_JSON="$(issues "5:$T_BLIND" "3:$T_BLIND" "20:$T_REG")" run_filer blind cant-run 1.0
eq "row9: no third blind issue" "0" "$(calls 'issue create')"
check "row9: comments on the OLDEST (lowest number)" grep -q '^issue comment 3 ' "$GD/calls.log"
eq "row9: exactly one comment" "1" "$(calls 'issue comment')"
ISSUES_JSON="$(issues "5:$T_BLIND" "3:$T_BLIND" "20:$T_REG")" run_filer pass pass 0.8
check "row9: a pass closes blind #3" grep -q '^issue close 3 ' "$GD/calls.log"
check "row9: a pass closes blind #5" grep -q '^issue close 5 ' "$GD/calls.log"
check "row9: a pass never closes the regression issue" bash -c "! grep -q '^issue close 20' '$GD/calls.log'"

# duplicate regression issues: comment on the oldest, create nothing
ISSUES_JSON="$(issues "30:$T_REG" "14:$T_REG")" run_filer fail probe-fail 0.8
check "duplicate regression: comments on the oldest (14)" grep -q '^issue comment 14 ' "$GD/calls.log"
eq "duplicate regression: nothing created" "0" "$(calls 'issue create')"

# list failure: no write, non-zero
ISSUES_JSON="[]" run_filer fail probe-fail 0.8
gd_new listfail; : >"$GD/list.fail"; printf '[]' >"$GD/issues.json"
PATH="$T/bin:$PATH" GH_STUB_DIR="$GD" GH_TOKEN=fake-token GITHUB_REPOSITORY=acme/widgets GITHUB_EVENT_NAME=schedule PROBE_OUTCOME=fail PROBE_REASON=probe-fail PROBE_COST=1 \
  bash "$RUNNER" file-issue >/dev/null 2>&1
FRC=$?
eq "list failure: no write" "0" "$(writes)"
check "list failure: exits non-zero" test "$FRC" -ne 0

# an unknown outcome value performs no write
ISSUES_JSON="[]" run_filer bogus x 1
eq "unknown outcome: no write" "0" "$(writes)"
check "unknown outcome: exits non-zero" test "$FRC" -ne 0

# pull_request events never file
FILER_EVENT=pull_request ISSUES_JSON="[]" run_filer fail probe-fail 0.8
eq "pull_request: the filer refuses to write" "0" "$(writes)"

echo "== Guard 4: not-run is a no-op like skipped (D1) =="
ISSUES_JSON="$(issues "20:$T_REG" "21:$T_BLIND")" run_filer not-run none unknown
eq "not-run: no write" "0" "$(writes)"
eq "not-run: no gh call at all" "0" "$(all_calls)"
check "not-run: exits 0 (a run=false push must not turn the filer red)" test "$FRC" -eq 0
check "not-run: prints that it files nothing" grep -q 'files nothing' "$T/f.out"
ISSUES_JSON="[]" run_filer not-run "" "" skipped
check "not-run with an empty reason and a skipped job result: still exit 0" test "$FRC" -eq 0
ISSUES_JSON="[]" run_filer skipped none unknown
check "skipped still prints that it files nothing" grep -q 'files nothing' "$T/f.out"
ISSUES_JSON="[]" run_filer not_run x 1
check "a near-miss spelling (not_run) is an unknown outcome and exits non-zero" test "$FRC" -ne 0

echo "== Guard 4: issue bodies (D3f) =="
FOOTER_LITERAL='Re-run: gh workflow run scheduled-real-sdk-ask-probe.yml (after merge) | Stop: soleur:cron-delete or disable the workflow | Tracking: #10111 | reason values: see norm_reason in apps/web-platform/scripts/real-sdk-ask-probe.sh | If you remove the ci/real-sdk-ask-probe label from an open issue the filer will open a duplicate'
MARKER_LITERAL='<!-- real-sdk-ask-probe:passed -->'
body_for() { # <comment|close-less> issue-number -> the body file of the 'issue comment <N>' call
  local ln; ln="$(grep -n "^issue comment $1 " "$GD/calls.log" | head -1 | cut -d: -f1)"
  [ -n "$ln" ] && cat "$GD/body.$ln"
}
footer_on_every_body() { # asserts the LAST line of every captured body is the footer; prints the number of bodies
  local f n=0 bad=0
  for f in "$GD"/body.*; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    [ "$(tail -n 1 "$f")" = "$FOOTER_LITERAL" ] || bad=$((bad + 1))
  done
  [ "$n" -ge 1 ] && [ "$bad" -eq 0 ]
}
ISSUES_JSON="[]" run_filer fail probe-fail 0.8
check "new regression body ends with the footer" footer_on_every_body
ISSUES_JSON="[]" run_filer blind cant-run 1.0
check "new blind body ends with the footer" footer_on_every_body
ISSUES_JSON="$(issues "20:$T_REG")" run_filer fail probe-fail 0.8
check "'again' body ends with the footer" footer_on_every_body
ISSUES_JSON="$(issues "20:$T_REG" "21:$T_BLIND")" run_filer pass pass 0.8
check "'passed' bodies end with the footer" footer_on_every_body
eq "passed: both bodies were captured (blind note + regression note)" "2" "$(ls "$GD"/body.* | wc -l | tr -d ' ')"
check "blind passed note says it is being closed" bash -c "grep -qF 'This issue is being closed: the probe now passes.' <<<\"\$1\"" _ "$(body_for 21)"
check "blind passed note does NOT claim the issue stays open" bash -c "! grep -qi 'stays OPEN' <<<\"\$1\"" _ "$(body_for 21)"
check "regression passed note keeps 'stays OPEN'" bash -c "grep -qF 'stays OPEN' <<<\"\$1\"" _ "$(body_for 20)"
check "regression passed note does not say it is being closed" bash -c "! grep -qF 'is being closed' <<<\"\$1\"" _ "$(body_for 20)"
eq "regression passed note starts with the marker (first line)" "$MARKER_LITERAL" "$(body_for 20 | head -n 1)"
eq "blind passed note carries no marker" "0" "$(body_for 21 | grep -cF "$MARKER_LITERAL")"
check "the filer listed the comments of #20 with the exact expression" grep -qF 'issue view 20 --repo acme/widgets --json comments --jq (.comments | last | .body // "") | startswith("<!-- real-sdk-ask-probe:passed -->")' "$GD/calls.log"
check "the filer never listed the comments of the blind issue (only regression notes are deduped)" bash -c "! grep -q '^issue view 21 ' '$GD/calls.log'"

echo "== Guard 4: no second 'subsequently passed' note while the newest comment is one (D3g) =="
COMMENTS_FIXTURE='{"comments":[{"body":"first note"},{"body":"<!-- real-sdk-ask-probe:passed -->\n\nA later run ... subsequently passed."}]}' \
  ISSUES_JSON="$(issues "20:$T_REG")" run_filer pass pass 0.8
eq "the newest comment is the passed note -> no second note" "0" "$(calls 'issue comment')"
eq "... and the filer still exits 0" "0" "$FRC"
check "... and says why" grep -q 'already the passed note' "$T/f.out"
COMMENTS_FIXTURE='{"comments":[{"body":"<!-- real-sdk-ask-probe:passed -->\n\nsubsequently passed."},{"body":"Another occurrence of this probe outcome."}]}' \
  ISSUES_JSON="$(issues "20:$T_REG")" run_filer pass pass 0.8
eq "a newer regression comment after the passed note re-arms it -> the note is posted again" "1" "$(calls 'issue comment')"
COMMENTS_FIXTURE='{"comments":[{"body":"a human quoted <!-- real-sdk-ask-probe:passed --> in the middle of a sentence"},{"body":" <!-- real-sdk-ask-probe:passed --> leading space"}]}' \
  ISSUES_JSON="$(issues "20:$T_REG")" run_filer pass pass 0.8
eq "control: the marker NOT at the start of a comment does not count -> the note is posted" "1" "$(calls 'issue comment')"
COMMENTS_FIXTURE='{"comments":[]}' ISSUES_JSON="$(issues "20:$T_REG" "30:$T_REG")" run_filer pass pass 0.8
eq "two open regression issues without a note each get exactly one" "2" "$(calls 'issue comment')"
VIEW_FAIL=1 ISSUES_JSON="$(issues "20:$T_REG" "21:$T_BLIND")" run_filer pass pass 0.8
eq "a comment-listing error posts no regression note (fail closed against spam)" "0" "$(calls 'issue comment 20')"
check "... exits non-zero so the failure is visible" test "$FRC" -ne 0
check "... but the blind issue is still closed" grep -q '^issue close 21 ' "$GD/calls.log"
ISSUES_JSON="$(issues "20:$T_REG")" run_filer fail probe-fail 0.8
eq "fail on an open regression issue still comments (no marker dedupe for 'again')" "1" "$(calls 'issue comment')"
eq "... and does not read comments" "0" "$(calls 'issue view')"

echo "== Guard 4 harness H1: a filer that always creates a second issue must make the suite RED =="
# substring-match mutant: swap the jq equality for a contains()
sed 's/\.title == \$t/(.title | contains($t))/' "$RUNNER" >"$T/mutant-filer.sh"
check "H1: the substring mutant differs from the runner" bash -c "! cmp -s '$RUNNER' '$T/mutant-filer.sh'"
ISSUES_JSON="$(issues "7:$T_REG (old copy)")" RUNNER_UNDER_TEST="$T/mutant-filer.sh" run_filer fail probe-fail 0.8
check "H1: the substring mutant adopts the decoy (row 1 would catch it)" test "$(calls 'issue create')" -eq 0

echo "== gh stub strictness (D9): nothing the runner sent was refused, and the stub does refuse what it should =="
check "the stub refused no argv during the whole suite" test ! -s "$T/gh-refused.log"
st_run() { # argv... ; runs the stub in an isolated dir whose refusal log is its own
  local r; rm -rf "$T/selftest"; mkdir -p "$T/selftest/gh"; printf '[]' >"$T/selftest/gh/issues.json"; printf '{"workflow_runs":[]}' >"$T/selftest/gh/runs.json"
  PATH="$T/bin:$PATH" GH_STUB_DIR="$T/selftest/gh" "$T/bin/gh" "$@" >/dev/null 2>&1; r=$?
  ST_RC=$r; ST_LOGGED="$(cat "$T/selftest/gh-refused.log" 2>/dev/null)"
}
st_run issue list --repo acme/widgets --state open --label ci/real-sdk-ask-probe --limit 200 --json number,title
eq "stub control: the modelled issue list is served (exit 0)" "0" "$ST_RC"
eq "stub control: ... and nothing is logged as refused" "" "$ST_LOGGED"
st_run issue list --repo acme/widgets --state open --limit 200 --json number,title
eq "stub: issue list without the label filter is refused (64)" "64" "$ST_RC"
check "stub: ... and the argv is logged" test -n "$ST_LOGGED"
st_run issue list --repo acme/widgets --state all --label ci/real-sdk-ask-probe --limit 200 --json number,title
eq "stub: issue list with --state all is refused" "64" "$ST_RC"
st_run api "repos/acme/widgets/actions/workflows/w.yml/runs?branch=dev&status=completed&per_page=30"
eq "stub: runs list not on branch=main is refused" "64" "$ST_RC"
st_run api "repos/acme/widgets/actions/workflows/w.yml/runs?branch=main&per_page=30"
eq "stub: runs list without status=completed is refused" "64" "$ST_RC"
st_run api "repos/acme/widgets/actions/workflows/w.yml/runs?branch=main&status=completed"
eq "stub: runs list without per_page is refused" "64" "$ST_RC"
st_run api "repos/acme/widgets/actions/workflows/w.yml/runs?branch=main&status=completed&per_page=30"
eq "stub control: the modelled runs list is served" "0" "$ST_RC"
st_run api "repos/acme/widgets/actions/runs/12/jobs?per_page=100"
eq "stub control: the modelled jobs endpoint is served" "0" "$ST_RC" 
st_run api "repos/acme/widgets/actions/runs/12/logs"
eq "stub: an unmodelled api path is refused" "64" "$ST_RC"
st_run issue close 5 --repo acme/widgets
eq "stub: issue close without --reason completed is refused" "64" "$ST_RC"
st_run issue close 5 --repo acme/widgets --reason "not planned"
eq "stub: issue close with another reason is refused" "64" "$ST_RC"
st_run issue close 5 --repo acme/widgets --reason completed
eq "stub control: the modelled issue close is served" "0" "$ST_RC"
st_run issue comment 5 --repo acme/widgets --body hi
eq "stub: an inline --body is refused" "64" "$ST_RC"
st_run issue view 5 --repo acme/widgets --json comments --jq '.comments | length'
eq "stub: issue view with another jq expression is refused" "64" "$ST_RC"
st_run issue view 5 --repo acme/widgets --json body --jq '(.comments | last | .body // "") | startswith("<!-- real-sdk-ask-probe:passed -->")'
eq "stub: issue view of another json field is refused" "64" "$ST_RC"
st_run issue create --repo acme/widgets --title "[ci/real-sdk-ask-probe] something else" --body-file /dev/null --label type/security --label domain/engineering --label priority/p1-high --label ci/real-sdk-ask-probe
eq "stub: issue create with an unmodelled title is refused" "64" "$ST_RC"
st_run issue edit 5 --repo acme/widgets
eq "stub: an unmodelled issue verb is refused" "64" "$ST_RC"
st_run pr list
eq "stub: an unmodelled command is refused" "64" "$ST_RC"

echo
echo "real-sdk-ask-probe.test.sh: $PASS passed, $FAIL failed"
# Anti-vacuity floor: a LOWER BOUND on the assertions that ran (the measured count at the last edit). Reported with printf + exit, not through
# eq/check, so it does not route through the helpers it backstops. Raise it with a new row.
MIN_ASSERTIONS=351
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: anti-vacuity floor: only %s assertions ran, floor is %s\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
