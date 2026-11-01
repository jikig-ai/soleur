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
    STUB_DIR="$SD" ANTHROPIC_API_KEY="${FAKE_KEY}" bash "${RUNNER_UNDER_TEST:-$RUNNER}" run >"$T/stdout" 2>"$T/stderr"
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

new_scn r7; put last "$(gen_out 8 true - "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "row7: two CANT-RUN passes end blind" "blind" "$(gho outcome)"
eq "row7: reason is the enum value" "model-did-not-attempt-bash" "$(gho reason)"
eq "row7: probe invoked exactly twice" "2" "$(invocations)"
check "row7: runner exits non-zero" test "$RC" -ne 0

new_scn r8; put last "RESULT: DIAGNOSTIC ($PROV_LINE, cases-run=1)" 4
run_runner
eq "row8: exit 4 / DIAGNOSTIC is blind" "blind" "$(gho outcome)"
eq "row8: probe invoked once" "1" "$(invocations)"

new_scn r8b; put last "$(gen_out 8 true 0.8 "RESULT: FAIL ($PROV_LINE, cases-run=8)")" 1
run_runner
eq "FAIL + exit 1 is fail" "fail" "$(gho outcome)"
eq "FAIL reason is probe-fail" "probe-fail" "$(gho reason)"
eq "FAIL is not retried" "1" "$(invocations)"
check "FAIL: runner exits non-zero" test "$RC" -ne 0

new_scn r8c; put last "$(gen_out 8 true 0.8 "RESULT: FAIL ($PROV_LINE, cases-run=8)")" 0
run_runner
eq "RESULT FAIL but exit 0 is not fail and not pass" "blind" "$(gho outcome)"

echo "== Guard 3: the rerun spends the REMAINING share of the single \$4 cap =="

new_scn r9; put 1 "$(gen_out 8 true 3.20 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
put 2 "$(gen_out 8 true 0.40 "$PASS_RESULT")" 0
run_runner
eq "row9: second invocation receives the remainder" "0.80|test" "$(sed -n 2p "$SD/env.log")"
eq "row9: rerun pass is pass" "pass" "$(gho outcome)"
eq "row9: reported cost is the sum of both passes" "3.6000" "$(gho cost)"
eq "row9: probe invoked exactly twice" "2" "$(invocations)"

new_scn r9b; put last "$(gen_out 8 true 3.80 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
run_runner
eq "row9b: remainder under \$0.50 means no rerun" "1" "$(invocations)"
eq "row9b: outcome is blind" "blind" "$(gho outcome)"

new_scn r9c; put 1 "$(gen_out 8 true 3.50 "RESULT: CANT-RUN:model-did-not-attempt-bash ($PROV_LINE, cases-run=8)")" 3
put 2 "$(gen_out 8 true 0.40 "$PASS_RESULT")" 0
run_runner
eq "row9c: remainder of exactly \$0.50 is still rerun" "0.50|test" "$(sed -n 2p "$SD/env.log")"

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
# Stub gh: records every call, serves fixtures, EXITS 64 on any argv the runner is not meant to send.
d="${GH_STUB_DIR:?}"
mkdir -p "$d"
printf '%s\n' "$*" >>"$d/calls.log"
n=$(wc -l <"$d/calls.log")
has() { case " $* " in *" $HAS "*) return 0 ;; esac; return 1; }
for a in "$@"; do
  case "$a" in --body|-b|--body=*) echo "stub gh: inline --body is forbidden (use --body-file)" >&2; exit 64 ;; esac
done
bodyfile=""
prev=""
for a in "$@"; do
  [ "$prev" = "--body-file" ] && bodyfile="$a"
  prev="$a"
done
[ -n "$bodyfile" ] && cp "$bodyfile" "$d/body.$n"
case "$1 ${2-}" in
  "api repos/"*)
    case "$2" in repos/*/actions/workflows/*/runs\?*) : ;; *) echo "stub gh: unexpected api path $2" >&2; exit 64 ;; esac
    [ -f "$d/api.fail" ] && exit 1
    cat "$d/runs.json"; exit 0 ;;
  "issue list")
    HAS="--repo"; has "$@" || exit 64
    [ -f "$d/list.fail" ] && exit 1
    cat "$d/issues.json"; exit 0 ;;
  "issue create")
    HAS="--repo"; has "$@" || exit 64
    HAS="--title"; has "$@" || exit 64
    HAS="--body-file"; has "$@" || exit 64
    echo "https://github.com/acme/widgets/issues/99"; exit 0 ;;
  "issue comment")
    HAS="--repo"; has "$@" || exit 64
    HAS="--body-file"; has "$@" || exit 64
    exit 0 ;;
  "issue close")
    HAS="--repo"; has "$@" || exit 64
    exit 0 ;;
  "label create")
    exit 0 ;;
  *) echo "stub gh: unexpected argv: $*" >&2; exit 64 ;;
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

# runs_json <sha:conclusion>...
runs_json() {
  local first=1 e
  printf '{"workflow_runs":['
  for e in "$@"; do
    [[ $first -eq 1 ]] || printf ','
    first=0
    printf '{"head_sha":"%s","conclusion":%s,"status":"completed"}' "${e%%:*}" "$( [[ "${e#*:}" == null ]] && echo null || echo "\"${e#*:}\"" )"
  done
  printf ']}\n'
}

run_should() { # event before head ; env: GD (gh stub dir). sets SR (run= value) and RC
  rm -f "$T/gho"
  (cd "$REPO" && PATH="$T/bin:$PATH" GH_STUB_DIR="$GD" GH_TOKEN=fake-token GITHUB_REPOSITORY=acme/widgets GITHUB_EVENT_NAME="$1" \
    PUSH_BEFORE_SHA="$2" GITHUB_SHA="$3" GITHUB_OUTPUT="$T/gho" bash "$RUNNER" should-run >"$T/sr.out" 2>"$T/sr.err")
  RC=$?
  SR="$(sed -n 's/^run=//p' "$T/gho" 2>/dev/null | tail -1)"
}
gd_new() { GD="$T/gh.$1"; rm -rf "$GD"; mkdir -p "$GD"; }

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

# ---------------------------------------------------------------------------------------------------------------------------------
echo "== Guard 4: file-issue =="

T_REG="[ci/real-sdk-ask-probe] real-SDK ask probe regression"
T_BLIND="[ci/real-sdk-ask-probe] real-SDK ask probe blind"
ADR_LITERAL="ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md"
PM_LITERAL="2026-10-11-hosted-bash-ask-bypassed-by-sdk-auto-allow-postmortem.md"

# run_filer <outcome> <reason> <cost> [job-result] [provenance]; env ISSUES_JSON
run_filer() {
  gd_new filer; printf '%s' "${ISSUES_JSON:-[]}" >"$GD/issues.json"
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

echo "== Guard 4 harness H1: a filer that always creates a second issue must make the suite RED =="
# substring-match mutant: swap the jq equality for a contains()
sed 's/\.title == \$t/(.title | contains($t))/' "$RUNNER" >"$T/mutant-filer.sh"
check "H1: the substring mutant differs from the runner" bash -c "! cmp -s '$RUNNER' '$T/mutant-filer.sh'"
ISSUES_JSON="$(issues "7:$T_REG (old copy)")" RUNNER_UNDER_TEST="$T/mutant-filer.sh" run_filer fail probe-fail 0.8
check "H1: the substring mutant adopts the decoy (row 1 would catch it)" test "$(calls 'issue create')" -eq 0

echo
echo "real-sdk-ask-probe.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
