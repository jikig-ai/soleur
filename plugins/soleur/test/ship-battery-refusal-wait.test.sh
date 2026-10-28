#!/usr/bin/env bash
# Suite for plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh (P4d, #10924).
#
# The script decides when a refused local battery may be recorded as "CI is the gate".
# Both directions are pinned: every must-NOT-defer input has its own row (infra surface,
# --full, selection refusals, mixed evidence, unreadable capacity), because a gate with only
# must-defer rows passes when it is made unconditionally permissive.
#
# Fixtures are SYNTHESIZED: scratch git repos, a stub `scripts/test-all.sh --capacity`, and
# PATH stubs for `date +%s` / `sleep` that share a fake clock file. The refusal text is
# rendered from the LIVE runner source (not hand-typed) so a reworded refusal reds the suite.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ONE owning trap, registered before the first allocation and before test-helpers.sh is
# sourced (ADR-129 rule (c); #8659).
FIXTURE_ROOTS=()
cleanup_fixture_roots() {
  local d
  for d in "${FIXTURE_ROOTS[@]:-}"; do
    [[ -n "$d" && "$d" == /* && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap cleanup_fixture_roots EXIT INT TERM

# shellcheck source=./test-helpers.sh
source "$HERE/test-helpers.sh"
# test-helpers.sh turns on errexit. This suite deliberately runs commands whose non-zero status
# IS the datum (the script under test exits 42/12/11/10/2), so verdicts are read from `$?`.
set +e

SCRIPT="$HERE/../skills/ship/scripts/battery-refusal-wait.sh"
REAL_SCRIPT="$SCRIPT"
SKILL_MD="$HERE/../skills/ship/SKILL.md"
REF_MD="$HERE/../skills/ship/references/battery-refusal-wait.md"
LIVE_RUNNER="$HERE/../../../scripts/test-all.sh"

new_root() { # <out-var> ; assigns, never prints (a $(...) call would register in a subshell)
  local __d
  __d="$(mktemp -d -t battery-refusal-wait-XXXXXX)" || return 1
  FIXTURE_ROOTS+=("$__d")
  printf -v "$1" '%s' "$__d"
}

# --- instrument self-test -------------------------------------------------------------------
_p0="$PASS"; _f0="$FAIL"
assert_eq "instrument" "instrument" "instrument self-test: the PASS arm records"
assert_eq "a" "b" "instrument self-test: the FAIL arm records (EXPECTED - subtracted below)"
if (( PASS <= _p0 || FAIL <= _f0 )); then
  printf 'FATAL: instrument self-test did not move both counters (PASS %s->%s, FAIL %s->%s).\n' \
    "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 1
fi
FAIL=$(( FAIL - 1 ))

if [[ ! -r "$SCRIPT" ]]; then
  printf 'FATAL: script under test not readable at %s\n' "$SCRIPT" >&2
  exit 1
fi

# --- PATH stubs: a fake clock shared by `date +%s` and `sleep` ------------------------------
new_root STUBROOT
STUBS="$STUBROOT/bin"; mkdir -p "$STUBS"
BASE=1000000
cat > "$STUBS/date" <<'STUB'
#!/usr/bin/env bash
# argv-strict: the script may only ask for epoch seconds.
[[ "$*" == "+%s" ]] || { echo "date stub: unexpected argv: $*" >&2; exit 64; }
cat "$(dirname "${BASH_SOURCE[0]}")/clock"
STUB
cat > "$STUBS/sleep" <<'STUB'
#!/usr/bin/env bash
# argv-strict: exactly one positive integer. Advances the fake clock; logs the call.
d="$(dirname "${BASH_SOURCE[0]}")"
[[ $# -eq 1 && "$1" =~ ^[1-9][0-9]*$ ]] || { echo "sleep stub: unexpected argv: $*" >&2; exit 64; }
echo "$1" >> "$d/sleeplog"
echo $(( $(cat "$d/clock") + $1 )) > "$d/clock"
n="$(wc -l < "$d/sleeplog")"
# Deterministic kill switches: an operator-armed mid-wait kill, and a runaway-loop cap so a
# mutant that never terminates is bounded without wall-clock time.
if [[ -f "$d/die_after" && "$n" -ge "$(cat "$d/die_after")" ]]; then kill -KILL "$PPID"; exit 0; fi
if (( n > 400 )); then kill -KILL "$PPID"; exit 0; fi
STUB
chmod +x "$STUBS/date" "$STUBS/sleep"

clock_at() { printf '%s\n' "$1" > "$STUBS/clock"; : > "$STUBS/sleeplog"; rm -f "$STUBS/die_after"; }
slept_total() { awk '{s+=$1} END {print s+0}' "$STUBS/sleeplog"; }

# --- scratch repo with a stub capacity runner ------------------------------------------------
# A bare origin, a clone on main (carrying scripts/test-all.sh stub + an infra file so a rename
# SOURCE can be fixtured), and a feature branch with one non-infra change.
build_repo() { # <out-var-work> <root>
  local root="$2" origin work
  origin="$root/origin.git"; work="$root/work"
  (
    git_fixture_env "$root" || exit 1
    git init --quiet --bare "$origin"
    git clone --quiet "$origin" "$work"
  ) >/dev/null 2>&1 || return 1
  (
    cd "$work" || exit 1
    git_fixture_env "$work" || exit 1
    mkdir -p scripts apps/web-platform/infra plugins/soleur
    cat > scripts/test-all.sh <<'STUB'
#!/usr/bin/env bash
# stub capacity runner: argv-strict, replays CAP_DIR/q one line per call (last line repeats).
[[ "$*" == "--capacity" ]] || { echo "test-all stub: unexpected argv: $*" >&2; exit 64; }
n="$(cat "$CAP_DIR/n" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "$CAP_DIR/n"
line="$(sed -n "${n}p" "$CAP_DIR/q")"; [[ -n "$line" ]] || line="$(tail -n 1 "$CAP_DIR/q")"
case "$line" in
  HANG) exec tail -f /dev/null ;;
  FAIL) exit 1 ;;
esac
printf '%s\n' "$line"
STUB
    printf 'resource "x" "y" {}\n' > apps/web-platform/infra/main.tf
    printf 'seed\n' > README.md
    git add -A
    git commit --quiet -m seed
    git branch -M main
    git push --quiet -u origin main
    git checkout --quiet -b feat-fixture
    printf 'change\n' > plugins/soleur/thing.md
    git add -A
    git commit --quiet -m "feature change"
  ) >/dev/null 2>&1 || return 1
  printf -v "$1" '%s' "$work"
}
in_repo() { local work="$1"; shift; ( cd "$work" || exit 1; git_fixture_env "$work" || exit 1; "$@" ) >/dev/null 2>&1; }

new_root R0
build_repo W0 "$R0" || { echo "FATAL: fixture build failed" >&2; exit 1; }
new_root CAPROOT; CAPD="$CAPROOT"; : > "$CAPD/q"
CAP_OK_IDLE='[contention] CAPACITY_OK measured_runs=0 measured_suites=0 sibling_threshold=1 tmp_avail_mb=3619 tmp_floor_mb=1024 memavail_mb=9000'
CAP_BUSY='[contention] BANNER CAPACITY_CONTENDED reason=sibling_runs measured_runs=2 measured_suites=1 sibling_threshold=1'
CAP_LOWTMP='[contention] BANNER CAPACITY_CONTENDED reason=low_tmp measured_runs=0 measured_suites=0 tmp_avail_mb=10 tmp_floor_mb=1024'
CAP_UNKNOWN='[contention] BANNER CAPACITY_UNKNOWN reason=unparseable_df measured_runs=? measured_suites=?'
cap() { printf '%s\n' "$@" > "$CAPD/q"; rm -f "$CAPD/n"; }

# --- logs, rendered from the LIVE runner's own refusal source ---------------------------------
# Pull the real echo line and substitute its two variables; a reworded refusal makes the
# extraction come back empty and the suite fails loudly instead of classifying hand-typed text.
render_refusal() { # <siblings> <TEST_GROUP>
  local line
  line="$(grep -F 'refusing a full-gate run — ${TC_SIBLING_RUN_COUNT} sibling' "$LIVE_RUNNER" | head -1)" || true
  line="${line#*echo \"}"; line="${line%\" >&2}"
  line="${line//\$\{TC_SIBLING_RUN_COUNT\}/$1}"; line="${line//\$TEST_GROUP/$2}"
  printf '%s\n' "$line"
}
SIB1="$(render_refusal 1 all)"; SIB2="$(render_refusal 2 all)"
SUBAGENT_LINE="ERROR: refusing a full-gate run — SOLEUR_SUBAGENT=1 is set (TEST_GROUP=all)."
new_root LOGROOT
LOG_SIB1="$LOGROOT/sib1.log"; printf '%s\n' "$SIB1" > "$LOG_SIB1"
LOG_SIB2="$LOGROOT/sib2.log"; printf '%s\n' "$SIB2" > "$LOG_SIB2"
LOG_CRLF="$LOGROOT/crlf.log"; printf '%s\r\n' "$SIB1" > "$LOG_CRLF"
LOG_LONG="$LOGROOT/long.log"; { for _i in $(seq 1 5000); do echo "[contention] preamble line $_i"; done; printf '%s\n' "$SIB1"; } > "$LOG_LONG"
LOG_DEGRADED="$LOGROOT/degraded.log"; { echo 'AFFECTED_FALLBACK reason=runner-changed'; printf '%s\n' "$SIB1"; echo 'AFFECTED_GATE_REFUSED reason=runner-refused'; } > "$LOG_DEGRADED"
LOG_SUBAGENT="$LOGROOT/subagent.log"; printf '%s\n' "$SUBAGENT_LINE" > "$LOG_SUBAGENT"
LOG_SEL="$LOGROOT/sel.log"; printf 'AFFECTED_GATE_REFUSED reason=below-floor\nAFFECTED_UNRESOLVED reason=below-floor\n' > "$LOG_SEL"
LOG_MIX_UNRES="$LOGROOT/mix1.log"; { printf '%s\n' "$SIB1"; echo 'AFFECTED_UNRESOLVED reason=zero-selected'; } > "$LOG_MIX_UNRES"
LOG_MIX_FAIL="$LOGROOT/mix2.log"; { printf '%s\n' "$SIB1"; echo '[FAIL] some-suite'; } > "$LOG_MIX_FAIL"
LOG_MIX_KILLED="$LOGROOT/mix3.log"; { printf '%s\n' "$SIB1"; echo '[KILLED] some-suite (exit=137)'; } > "$LOG_MIX_KILLED"
LOG_MIX_SUBAGENT="$LOGROOT/mix4.log"; { printf '%s\n' "$SIB1"; printf '%s\n' "$SUBAGENT_LINE"; } > "$LOG_MIX_SUBAGENT"
LOG_MIX_GATE="$LOGROOT/mix5.log"; { printf '%s\n' "$SIB1"; echo 'AFFECTED_GATE_REFUSED reason=no-stack'; } > "$LOG_MIX_GATE"
LOG_EMPTY="$LOGROOT/empty.log"; : > "$LOG_EMPTY"
LOG_TEXT="$LOGROOT/text.log"; printf 'something entirely unrelated\n' > "$LOG_TEXT"
STATE="$LOGROOT/state"

assert_eq "1" "$([[ "$SIB1" == *"1 sibling full-gate run(s) already in flight"* ]] && echo 1 || echo 0)" \
  "the refusal fixture was rendered from the live runner (non-empty, carries the sibling clause)"

# --- runner ---------------------------------------------------------------------------------
# run_wait <work> <args...>: sets OUT, RC, V (verdict word), W (waited_s).
run_wait() {
  local work="$1"; shift
  OUT="$( cd "$work" && git_fixture_env "$work" >/dev/null 2>&1; PATH="$STUBS:$PATH" CAP_DIR="$CAPD" timeout 25 bash "$SCRIPT" "$@" 2>&1 )"
  RC=$?
  V="$(sed -n 's/.*verdict=\([A-Z_]*\).*/\1/p' <<<"$OUT" | tail -1)"
  W="$(sed -n 's/.*waited_s=\([0-9]*\).*/\1/p' <<<"$OUT" | tail -1)"
}
# Standard wait invocation on W0 with a small budget.
wait_small() { # <log> [extra args]
  local log="$1"; shift
  run_wait "$W0" --log "$log" --state "$STATE" --budget-s 3 --interval-s 1 "$@"
}
start_arm() { clock_at "$BASE"; : > "$STATE"; }

# --- A. classifier (--classify-only) --------------------------------------------------------
classify() { run_wait "$W0" --classify-only "$1"; printf '%s' "$OUT"; }
assert_eq "class=contention" "$(classify "$LOG_SIB1")" "A1 a real sibling refusal (1 sibling) is contention"
assert_eq "class=contention" "$(classify "$LOG_SIB2")" "A2 a 2-sibling refusal is contention"
assert_eq "class=contention" "$(classify "$LOG_CRLF")" "A3 CRLF line endings are stripped (H2)"
assert_eq "class=contention" "$(classify "$LOG_LONG")" "A4 the refusal after 5000 preamble lines is found (H2)"
assert_eq "class=contention" "$(classify "$LOG_DEGRADED")" "A5 a degraded-affected log (AFFECTED_FALLBACK + runner-refused) is contention (H2)"
assert_eq "class=not-waitable" "$(classify "$LOG_SUBAGENT")" "A6 SOLEUR_SUBAGENT text only is NOT waitable (G1)"
assert_eq "class=not-waitable" "$(classify "$LOG_SEL")" "A7 a selection refusal is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_MIX_UNRES")" "A8 sibling text + AFFECTED_UNRESOLVED below it is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_MIX_FAIL")" "A9 sibling text + a trailing [FAIL] is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_MIX_KILLED")" "A10 sibling text + [KILLED] is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_MIX_SUBAGENT")" "A11 sibling text + SOLEUR_SUBAGENT text is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_MIX_GATE")" "A12 sibling text + a non-runner-refused gate refusal is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_EMPTY")" "A13 an empty log is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOGROOT/missing.log")" "A14 a missing log is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_TEXT")" "A15 unrelated text is NOT waitable"
assert_eq "class=not-waitable" "$(classify /dev/null)" "A16 the discoverability command (/dev/null) prints class=not-waitable"

# --- B. wait loop ----------------------------------------------------------------------------
start_arm; cap "$CAP_BUSY"
wait_small "$LOG_SIB1"
assert_eq "42/CI_IS_THE_GATE/3" "$RC/$V/$W" "B1 contended for the whole budget, clean diff -> CI_IS_THE_GATE exit 42, waited_s=3"
assert_eq "1" "$([[ "$OUT" == *"WAITING elapsed_s=0 budget_s=3 capacity=contended"* ]] && echo 1 || echo 0)" "B2 a WAITING liveness line is printed per poll"

start_arm; cap "$CAP_BUSY" "$CAP_BUSY" "$CAP_OK_IDLE"
wait_small "$LOG_SIB1"
assert_eq "10/RETRY" "$RC/$V" "B3 CAPACITY_OK measured_runs=0 on the third poll -> RETRY exit 10"
assert_eq "2" "$(grep -c 'WAITING' <<<"$OUT")" "B4 exactly two WAITING lines precede the RETRY"

start_arm; cap "$CAP_LOWTMP"
wait_small "$LOG_SIB1"
assert_eq "42" "$RC" "B5 CAPACITY_CONTENDED with measured_runs=0 (low_tmp) keeps waiting, it is not idle"

start_arm; cap "$CAP_BUSY" "$CAP_UNKNOWN"
wait_small "$LOG_SIB1"
assert_eq "42/CI_IS_THE_GATE" "$RC/$V" "B6 a valid reading earlier then CAPACITY_UNKNOWN (measured_runs=?) keeps waiting and still defers"

start_arm; cap "$CAP_UNKNOWN"
wait_small "$LOG_SIB1"
assert_eq "11/NOT_WAITABLE" "$RC/$V" "B7 capacity never readable (UNKNOWN only) -> NOT_WAITABLE, a stop not a deferral"
assert_eq "1" "$([[ "$OUT" == *"reason=capacity-unreadable"* ]] && echo 1 || echo 0)" "B8 the reason names capacity-unreadable"

start_arm; cap FAIL
wait_small "$LOG_SIB1"
assert_eq "11" "$RC" "B9 a failing capacity call for the whole budget -> exit 11"

start_arm; cap HANG
wait_small "$LOG_SIB1"
assert_eq "11" "$RC" "B10 a hung capacity call is bounded by timeout and ends as capacity-unreadable (exit 11)"

# budget boundary: elapsed = budget-1 still waits; = budget defers
start_arm; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 100
assert_eq "3" "$(slept_total)" "B11 a long interval is clamped to the remaining budget (never sleeps past the deadline)"

# shared budget across two invocations, killed mid-wait
start_arm; cap "$CAP_BUSY"; printf '2\n' > "$STUBS/die_after"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1
assert_eq "$BASE" "$(tr -d '[:space:]' < "$STATE")" "B12 the episode epoch is written before the first poll (survives a kill)"
printf '%s\n' "$(( BASE + 2 ))" > "$STUBS/clock"; : > "$STUBS/sleeplog"; rm -f "$STUBS/die_after"; rm -f "$CAPD/n"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1
assert_eq "42/6/4" "$RC/$W/$(slept_total)" "B13 the second invocation shares the first one's budget (waited_s=6 total, slept 4 more)"

# state: pre-seeded epoch
clock_at "$BASE"; cap "$CAP_BUSY"; printf '%s\n' "$(( BASE - 1000 ))" > "$STATE"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 1800 --interval-s 60
assert_eq "42/1800/800" "$RC/$W/$(slept_total)" "B14 a seeded epoch 1000 s old leaves 800 s of the 1800 s budget"

clock_at "$BASE"; : > "$STATE"; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1
assert_eq "42" "$RC" "B15 an empty state file starts a fresh episode"

clock_at "$BASE"; printf 'garbage\n' > "$STATE"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1
assert_eq "2" "$RC" "B16 a non-integer epoch exits 2"
clock_at "$BASE"; printf '%s\n' "$(( BASE + 500 ))" > "$STATE"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1
assert_eq "2" "$RC" "B17 a future epoch exits 2"

# not-waitable logs never wait
start_arm; cap "$CAP_BUSY"
wait_small "$LOG_SEL"
assert_eq "11/NOT_WAITABLE/0" "$RC/$V/$(slept_total)" "B18 a selection-refusal log exits 11 immediately, without sleeping"
start_arm; cap "$CAP_BUSY"
wait_small "$LOG_SUBAGENT"
assert_eq "11/0" "$RC/$(slept_total)" "B19 a SOLEUR_SUBAGENT-only log exits 11 and never waits (G1)"
start_arm; wait_small "$LOGROOT/missing.log"
assert_eq "11" "$RC" "B20 a missing log exits 11"
start_arm; wait_small "$LOG_MIX_UNRES"
assert_eq "11" "$RC" "B21 mixed evidence exits 11"

# --- C. infra carve-out, --full ---------------------------------------------------------------
infra_arm() { # <name> <mutating-shell-snippet> -> sets IW
  local root; new_root root
  build_repo IW "$root" || { echo "FATAL: fixture build failed" >&2; exit 1; }
  ( cd "$IW" && git_fixture_env "$IW" && bash -c "$2" ) >/dev/null 2>&1
}
infra_row() { # <label> <snippet>
  infra_arm "$1" "$2"
  start_arm; cap "$CAP_BUSY"
  run_wait "$IW" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1
  assert_eq "12/QUEUE_IN_LOCK" "$RC/$V" "C $1 -> QUEUE_IN_LOCK exit 12, never 42"
}
infra_row "committed edit under apps/web-platform/infra/" 'printf x >> apps/web-platform/infra/main.tf && git commit -qam infra'
infra_row "committed edit to .github/workflows/apply-web-platform-infra.yml" 'mkdir -p .github/workflows && printf x > .github/workflows/apply-web-platform-infra.yml && git add -A && git commit -qm wf'
infra_row "uncommitted working-tree edit under infra" 'printf x >> apps/web-platform/infra/main.tf'
infra_row "untracked new file under infra" 'printf x > apps/web-platform/infra/new.tf'
infra_row "rename of a file OUT of infra (the SOURCE is the infra path)" 'mkdir -p docs && git mv apps/web-platform/infra/main.tf docs/moved.tf && git commit -qm rename'
infra_row "git cannot resolve origin/main...HEAD (diff-unresolved)" 'git update-ref -d refs/remotes/origin/main'
INFRA_LAST_OUT="$OUT"
assert_eq "1" "$([[ "$INFRA_LAST_OUT" == *"reason=diff-unresolved"* ]] && echo 1 || echo 0)" "C7 an unresolved diff names diff-unresolved"

start_arm; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --full
assert_eq "12/QUEUE_IN_LOCK" "$RC/$V" "C8 --full + contention never defers (exit 12)"
start_arm; cap "$CAP_BUSY" "$CAP_OK_IDLE"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --full
assert_eq "10" "$RC" "C9 --full still gets RETRY when capacity frees up inside the budget"

# --- D. arguments ----------------------------------------------------------------------------
start_arm; cap "$CAP_BUSY"
for bad in "--budget-s abc" "--budget-s -5" "--budget-s 0" "--interval-s x" "--bogus" "--budget-s"; do
  # shellcheck disable=SC2086
  run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" $bad
  assert_eq "2" "$RC" "D arg rejected with exit 2: $bad"
done
run_wait "$W0" --state "$STATE"
assert_eq "2" "$RC" "D --log is required (exit 2)"
start_arm; cap "$CAP_BUSY"
BATTERY_REFUSAL_WAIT_BUDGET_S=1 SHIP_BATTERY_WAIT_BUDGET_S=1 run_wait "$W0" --log "$LOG_SIB1" --state "$STATE"
assert_eq "42/1800/$(( 1800 ))" "$RC/$W/$(slept_total)" "D1 defaults are 1800 s budget / 60 s interval via flags only (env vars are ignored)"
assert_eq "1" "$([[ "$(head -1 "$STUBS/sleeplog")" == "60" ]] && echo 1 || echo 0)" "D2 the default interval is 60 s"

# --- E. no other status continues (recipe branch) ----------------------------------------------
if [[ -r "$REF_MD" ]]; then
  CASE_BLOCK="$(awk '/case "\$wait_rc" in/{f=1} f{print} /^[[:space:]]*esac/{if(f) exit}' "$REF_MD")"
else
  CASE_BLOCK=""
fi
assert_eq "1" "$([[ -n "$CASE_BLOCK" ]] && echo 1 || echo 0)" "E0 the reference recipe carries a case on wait_rc"
for st in 1 2 11 127 130 137 0; do
  got="$(wait_rc=$st bash -c "$CASE_BLOCK" 2>&1)"
  assert_eq "0" "$(grep -c 'CONTINUE_CI_IS_THE_GATE' <<<"$got")" "E status $st never continues"
done
got="$(wait_rc=42 bash -c "$CASE_BLOCK" 2>&1)"
assert_eq "1" "$(grep -c 'CONTINUE_CI_IS_THE_GATE' <<<"$got")" "E 42 is the one status that continues"
got="$(wait_rc=10 bash -c "$CASE_BLOCK" 2>&1)"
assert_eq "1" "$(grep -c 'RELAUNCH' <<<"$got")" "E 10 relaunches the battery"
got="$(wait_rc=12 bash -c "$CASE_BLOCK" 2>&1)"
assert_eq "1" "$(grep -c 'QUEUE_IN_LOCK' <<<"$got")" "E 12 selects the queue-in-lock path"

# --- F. parity + wiring ----------------------------------------------------------------------
assert_eq "1" "$(grep -cF 'sibling full-gate run(s) already in flight' "$LIVE_RUNNER" | awk '{print ($1>=1)}')" "F1 the live runner carries the sibling-refusal clause"
for lit in 'apps/web-platform/infra/' '.github/workflows/apply-web-platform-infra.yml'; do
  assert_eq "1" "$(grep -cF -- "'$lit'" "$LIVE_RUNNER" | awk '{print ($1>=1)}')" "F infra literal in the live runner: $lit"
  assert_eq "1" "$(grep -cF -- "$lit" "$REAL_SCRIPT" | awk '{print ($1>=1)}')" "F infra literal mirrored in the script: $lit"
done
assert_eq "1" "$(grep -cF 'battery-refusal-wait.sh' "$SKILL_MD" | awk '{print ($1>=1)}')" "F3 SKILL.md names the script"
assert_eq "1" "$(grep -cF '](./references/battery-refusal-wait.md)' "$SKILL_MD" | awk '{print ($1>=1)}')" "F4 SKILL.md links the reference"
assert_eq "0" "$(grep -c 'go back to waiting' "$SKILL_MD")" "F5 the unbounded 'go back to waiting' prescription is gone"
assert_eq "1" "$(grep -cF 'SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=39600' "$SKILL_MD" | awk '{print ($1>=1)}')" "F6 the queue-in-lock command (target of exit 12) is kept"
assert_eq "1" "$(grep -cE 'rc=4. is REFUSED' "$SKILL_MD" | awk '{print ($1>=1)}')" "F7 the rc=4 REFUSED sentence is intact"
PR_LINE="$(grep -F 'Local battery refused (sibling contention)' "$REF_MD" 2>/dev/null | head -1)"
assert_eq "1" "$([[ "$PR_LINE" == *'CI "test" is the authoritative gate; local run NOT executed.'* ]] && echo 1 || echo 0)" "F8 the reference carries the fixed PR Test plan line"
assert_eq "0" "$(grep -ciE 'passed|verified' <<<"$PR_LINE")" "F9 the PR Test plan line never says passed or verified"
assert_eq "1" "$(grep -c 'wait_rc' "$REF_MD" 2>/dev/null | awk '{print ($1>=1)}')" "F10 the recipe names the script status wait_rc, not rc"

# --- G. mutation battery (mutants of a COPY; the real script is never touched) -----------------
new_root MROOT
mutate() { # <id> <count> <old1> <new1> [<old2> <new2>] -> sets SCRIPT to the mutant or returns 1
  local id="$1" cnt="$2" m
  m="$MROOT/mut-$id.sh"
  cp "$REAL_SCRIPT" "$m"
  if ! OLD1="$3" NEW1="$4" OLD2="${5:-}" NEW2="${6:-}" CNT="$cnt" python3 -c '
import os, sys
p = sys.argv[1]; s = open(p).read()
for o, n in ((os.environ["OLD1"], os.environ["NEW1"]), (os.environ["OLD2"], os.environ["NEW2"])):
    if not o: continue
    if s.count(o) != int(os.environ["CNT"]): sys.exit(1)
    s = s.replace(o, n)
open(p, "w").write(s)' "$m"; then
    assert_eq "landed" "did-not-land" "G $id: the mutation lands the expected number of times"; return 1
  fi
  if cmp -s "$m" "$REAL_SCRIPT"; then assert_eq "differs" "identical" "G $id: the mutant differs from the original"; return 1; fi
  SCRIPT="$m"; return 0
}
restore() { SCRIPT="$REAL_SCRIPT"; }
# <id> <label> <real-result> <scenario-fn>; the scenario echoes a compact result. A mutant is
# KILLED when it differs from the real script's result.
mrow() {
  local id="$1" label="$2" want="$3" fn="$4" got
  "$fn"; got="$RES"
  if [[ "$got" != "$want" ]]; then assert_eq "red" "red" "G $id: $label goes RED against the mutant (got $got, real $want)"
  else assert_eq "red" "still-green:$got" "G $id: $label goes RED against the mutant"; fi
  restore
}
res() { RES="$RC/$V/$W/$(slept_total)"; }
scn_defer()  { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SIB1"; res; }
scn_lowtmp() { start_arm; cap "$CAP_LOWTMP"; wait_small "$LOG_SIB1"; res; }
scn_unread() { start_arm; cap FAIL; wait_small "$LOG_SIB1"; res; }
scn_mixu()   { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_MIX_UNRES"; res; }
scn_mixf()   { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_MIX_FAIL"; res; }
scn_sel()    { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SEL"; res; }
scn_sub()    { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SUBAGENT"; res; }
scn_full()   { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SIB1" --full; res; }
scn_garbage(){ clock_at "$BASE"; printf 'garbage\n' > "$STATE"; cap "$CAP_BUSY"; wait_small "$LOG_SIB1"; res; }
scn_shared() { clock_at "$BASE"; cap "$CAP_BUSY"; printf '%s\n' "$(( BASE - 1000 ))" > "$STATE"
               run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 1800 --interval-s 60; res; }
scn_boundary() { start_arm; cap "$CAP_BUSY"; run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1; res; }
scn_midkill() { start_arm; cap "$CAP_BUSY"; printf '2\n' > "$STUBS/die_after"
                run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1
                printf '%s\n' "$(( BASE + 2 ))" > "$STUBS/clock"; : > "$STUBS/sleeplog"; rm -f "$STUBS/die_after"; rm -f "$CAPD/n"
                run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1; res; }
scn_infra_wf() { infra_arm x 'mkdir -p .github/workflows && printf x > .github/workflows/apply-web-platform-infra.yml && git add -A && git commit -qm wf'
                 start_arm; cap "$CAP_BUSY"; run_wait "$IW" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1; res; }
scn_infra_rn() { infra_arm x 'mkdir -p docs && git mv apps/web-platform/infra/main.tf docs/moved.tf && git commit -qm rename'
                 start_arm; cap "$CAP_BUSY"; run_wait "$IW" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1; res; }
scn_infra_unres() { infra_arm x 'git update-ref -d refs/remotes/origin/main'
                 start_arm; cap "$CAP_BUSY"; run_wait "$IW" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1; res; }
scn_infra_pf() { infra_arm x 'printf x >> apps/web-platform/infra/main.tf && git commit -qam infra'
                 start_arm; cap "$CAP_BUSY"; run_wait "$IW" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1; res; }

# Scenarios run in THIS shell (never a $(...) subshell, which would drop FIXTURE_ROOTS
# registrations) and leave their result in RES.
real() { "$2"; printf -v "$1" '%s' "$RES"; }
real REAL_DEFER scn_defer; real REAL_LOWTMP scn_lowtmp; real REAL_UNREAD scn_unread
real REAL_MIXU scn_mixu; real REAL_MIXF scn_mixf; real REAL_SEL scn_sel; real REAL_SUB scn_sub
real REAL_FULL scn_full; real REAL_GARB scn_garbage; real REAL_SHARED scn_shared; real REAL_BOUND scn_boundary
real REAL_MID scn_midkill; real REAL_WF scn_infra_wf; real REAL_RN scn_infra_rn; real REAL_UN scn_infra_unres
assert_eq "42/CI_IS_THE_GATE/3/3" "$REAL_DEFER" "G0 the unmutated control defers as designed (a red control voids every row)"
assert_eq "12/QUEUE_IN_LOCK/3/3" "$REAL_WF" "G0b the unmutated control keeps the workflow-file diff out of the deferral"

# 1 classifier shape edited so the real sibling text no longer matches
mutate M1 1 $'already in flight\'' $'already in flightX\'' && mrow M1 "the sibling-refusal log defers" "$REAL_DEFER" scn_defer
# 2 chokepoint returns 42 regardless of infra / --full
mutate M2a 1 'verdict QUEUE_IN_LOCK "$RC_QUEUE" infra-diff' 'verdict CI_IS_THE_GATE "$RC_CI" infra-diff' && mrow M2a "the infra workflow-file diff" "$REAL_WF" scn_infra_wf
mutate M2b 1 'verdict QUEUE_IN_LOCK "$RC_QUEUE" full-requested' 'verdict CI_IS_THE_GATE "$RC_CI" full-requested' && mrow M2b "--full" "$REAL_FULL" scn_full
mutate M2c 1 'verdict QUEUE_IN_LOCK "$RC_QUEUE" diff-unresolved' 'verdict CI_IS_THE_GATE "$RC_CI" diff-unresolved' && mrow M2c "the unresolved-diff row" "$REAL_UN" scn_infra_unres
# 3 second non-contention line after a compliant first
mutate M3a 1 'AFFECTED_UNRESOLVED' 'AFFECTED_UNRESOLVEDX' && mrow M3a "AFFECTED_UNRESOLVED under the sibling text" "$REAL_MIXU" scn_mixu
mutate M3b 1 '\[FAIL\]' '\[FAILX\]' && mrow M3b "a trailing [FAIL]" "$REAL_MIXF" scn_mixf
# 4 budget comparison flipped / epoch ignored
mutate M4a 1 '(( elapsed >= BUDGET_S ))' '(( elapsed > BUDGET_S ))' && mrow M4a "the budget boundary" "$REAL_BOUND" scn_boundary
mutate M4b 1 'elapsed=$(( now - EPOCH ))' 'elapsed=$(( now - CALL_START ))' && mrow M4b "the shared budget" "$REAL_SHARED" scn_shared
# 5 dispatch: the whole body replaced
mutate M5a 1 '# DISPATCH-ANCHOR' 'exit 42' && mrow M5a "the selection-refusal row (expects 11)" "$REAL_SEL" scn_sel
mutate M5b 1 '# DISPATCH-ANCHOR' 'exit 10' && mrow M5b "the garbage-state row (expects 2)" "$REAL_GARB" scn_garbage
# 6 capacity parse loosened / never-readable folded into deferral
mutate M6a 1 'if [[ "$out" == *CAPACITY_OK* && "$ok_line" =~' 'if [[ "$out" =~' && mrow M6a "CONTENDED-with-zero keeps waiting" "$REAL_LOWTMP" scn_lowtmp
mutate M6b 1 'verdict NOT_WAITABLE "$RC_NOT_WAITABLE" capacity-unreadable' 'verdict CI_IS_THE_GATE "$RC_CI" capacity-unreadable' && mrow M6b "never-readable capacity" "$REAL_UNREAD" scn_unread
# 7 REORDER: the epoch write moves from before the first poll to after the loop
mutate M7 1 'init_episode  # EPISODE-INIT' '' 'infra="$(infra_state)"' 'init_episode; infra="$(infra_state)"' && mrow M7 "kill mid-wait then re-invoke" "$REAL_MID" scn_midkill
# 8 infra literal drift / rename-source forms dropped
mutate M8a 1 '.github/workflows/apply-web-platform-infra.yml' '.github/workflows/apply-web-platform-infra.ymlx' && mrow M8a "the workflow-file row" "$REAL_WF" scn_infra_wf
mutate M8b 2 'diff --name-status -M' 'diff --name-only' && mrow M8b "the rename-source row" "$REAL_RN" scn_infra_rn
# 9 the declared-env SUBAGENT refusal becomes waitable (shape widened AND exclusion removed)
mutate M9 1 "'refusing a full-gate run .* [0-9]+ sibling full-gate run\(s\) already in flight'" "'refusing a full-gate run'" 'SOLEUR_SUBAGENT=1 is set' 'SOLEUR_SUBAGENT=1 is setX' && mrow M9 "the SUBAGENT-only row" "$REAL_SUB" scn_sub
restore

# H1: a suite whose success is `fail == 0` exits 0 on "0 passed, 0 failed". The floor is the guard.
H1_OUT="$( PASS=3 FAIL=0; print_results 99 >/dev/null 2>&1; echo $? )"
assert_eq "1" "$([[ "$H1_OUT" != "0" ]] && echo 1 || echo 0)" "H1 print_results with a floor above the pass count exits non-zero"
assert_eq "1" "$(tail -3 "${BASH_SOURCE[0]}" | grep -cE '^print_results [0-9]+$')" "H1b this suite ends with a numeric PASS floor"

# The floor counts the instrument self-test's two rows plus every row above. Set EQUAL to the
# current count, not below it: slack is budget for a silently deleted row.
print_results 101
