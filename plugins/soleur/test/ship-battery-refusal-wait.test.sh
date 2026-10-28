#!/usr/bin/env bash
# Suite for plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh (P4d, #10924).
#
# The script decides when a refused local battery may be recorded as "CI is the gate".
# Both directions are pinned: every must-NOT-defer input has its own row (infra surface,
# --full, selection refusals, mixed evidence, unreadable capacity, bad state), because a gate
# with only must-defer rows passes when it is made unconditionally permissive.
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
    [[ -n "$d" && -d "$d" ]] || continue
    assert_fixture_dir "$d"
    rm -rf "$d"
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
REAL_REF_MD="$REF_MD"
LIVE_RUNNER="$HERE/../../../scripts/test-all.sh"
REAL_GIT="$(command -v git)"
REAL_SLEEP="$(command -v sleep)"

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

# --- PATH stubs: a fake clock shared by `date +%s` and `sleep`; a failing-git shim -------------
new_root STUBROOT
STUBS="$STUBROOT/bin"; mkdir -p "$STUBS"
BASE=1800000000
assert_fixture_dir "$STUBS"
cat > "$STUBS/date" <<'STUB'
#!/usr/bin/env bash
# argv-strict: the script may only ask for epoch seconds.
[[ "$*" == "+%s" ]] || { echo "date stub: unexpected argv: $*" >&2; exit 64; }
cat "$(dirname "${BASH_SOURCE[0]}")/clock"
STUB
assert_fixture_dir "$STUBS"
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
assert_fixture_dir "$STUBS"
cat > "$STUBS/git" <<'STUB'
#!/usr/bin/env bash
# Delegates to the real git; fails (128) any invocation whose argv contains $FAIL_GIT_MATCH.
if [[ -n "${FAIL_GIT_MATCH:-}" && "$*" == *"$FAIL_GIT_MATCH"* ]]; then exit 128; fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$STUBS/date" "$STUBS/sleep" "$STUBS/git"

clock_at() { assert_fixture_dir "$STUBS"; printf '%s\n' "$1" > "$STUBS/clock"; : > "$STUBS/sleeplog"; rm -f "$STUBS/die_after"; }
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
# Tokens: HANG (block), STUBBORN (block, ignoring TERM), FAIL (exit 1), STDERR:<text>, MULTI:<text with \n escapes>,
# IDLEFAIL:<text> (print, exit 1).
[[ "$*" == "--capacity" ]] || { echo "test-all stub: unexpected argv: $*" >&2; exit 64; }
n="$(cat "$CAP_DIR/n" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "$CAP_DIR/n"
line="$(sed -n "${n}p" "$CAP_DIR/q")"; [[ -n "$line" ]] || line="$(tail -n 1 "$CAP_DIR/q")"
case "$line" in
  HANG) exec tail -f /dev/null ;;
  STUBBORN) trap '' TERM; exec tail -f /dev/null ;;
  STDERR:*) printf '%s\n' "${line#STDERR:}" >&2; exit 0 ;;
  FAIL) exit 1 ;;
  MULTI:*) printf '%b\n' "${line#MULTI:}"; exit 0 ;;
  IDLEFAIL:*) printf '%s\n' "${line#IDLEFAIL:}"; exit 1 ;;
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

new_root R0
build_repo W0 "$R0" || { echo "FATAL: fixture build failed" >&2; exit 1; }
new_root CAPROOT; CAPD="$CAPROOT"; assert_fixture_dir "$CAPD"; : > "$CAPD/q"
CAP_OK_IDLE='[contention] CAPACITY_OK measured_runs=0 measured_suites=0 sibling_threshold=1 tmp_avail_mb=3619 tmp_floor_mb=1024 memavail_mb=9000'
CAP_OK_BUSY='[contention] CAPACITY_OK measured_runs=1 measured_suites=0 sibling_threshold=2 tmp_avail_mb=3619 tmp_floor_mb=1024 memavail_mb=9000'
CAP_BUSY='[contention] BANNER CAPACITY_CONTENDED reason=sibling_runs measured_runs=2 measured_suites=1 sibling_threshold=1'
CAP_LOWTMP='[contention] BANNER CAPACITY_CONTENDED reason=low_tmp measured_runs=0 measured_suites=0 tmp_avail_mb=10 tmp_floor_mb=1024'
CAP_UNKNOWN='[contention] BANNER CAPACITY_UNKNOWN reason=unparseable_df measured_runs=? measured_suites=?'
cap() { assert_fixture_dir "$CAPD"; printf '%s\n' "$@" > "$CAPD/q"; rm -f "$CAPD/n"; }

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
SIB1="$(render_refusal 1 all)"; SIB2="$(render_refusal 2 all)"; SIB0="$(render_refusal 0 all)"
SUBAGENT_LINE="ERROR: refusing a full-gate run — SOLEUR_SUBAGENT=1 is set (TEST_GROUP=all)."
new_root LOGROOT
assert_fixture_dir "$LOGROOT"
LOG_SIB1="$LOGROOT/sib1.log"; printf '%s\n' "$SIB1" > "$LOG_SIB1"
assert_fixture_dir "$LOGROOT"
LOG_SIB2="$LOGROOT/sib2.log"; printf '%s\n' "$SIB2" > "$LOG_SIB2"
assert_fixture_dir "$LOGROOT"
LOG_CRLF="$LOGROOT/crlf.log"; printf '%s\r\n' "$SIB1" > "$LOG_CRLF"
assert_fixture_dir "$LOGROOT"
LOG_LONG="$LOGROOT/long.log"; { for _i in $(seq 1 5000); do echo "[contention] preamble line $_i"; done; printf '%s\n' "$SIB1"; } > "$LOG_LONG"
assert_fixture_dir "$LOGROOT"
LOG_DEGRADED="$LOGROOT/degraded.log"; { echo 'AFFECTED_FALLBACK reason=runner-changed'; printf '%s\n' "$SIB1"; echo 'AFFECTED_GATE_REFUSED reason=runner-refused'; } > "$LOG_DEGRADED"
# Shaped like a real affected-tests.sh refusal log (tab-delimited fallback line, the runner's
# refusal passed through, the gate's own refusal and summary lines); synthesized, not captured.
LOG_AFFREAL="$LOGROOT/affreal.log"
{ printf 'AFFECTED_FALLBACK\treason=runner-changed\n'; echo '[contention] siblings: 1 other worktree(s) running test-all.sh'
  printf '%s\n' "$SIB1"; echo 'AFFECTED_GATE_REFUSED reason=runner-refused'
  echo 'AFFECTED_GATE ran=- of=- skipped=- mode=full reason=runner-refused stack=runner ci=.github/workflows/ci.yml'; } > "$LOG_AFFREAL"
assert_fixture_dir "$LOGROOT"
LOG_SUBAGENT="$LOGROOT/subagent.log"; printf '%s\n' "$SUBAGENT_LINE" > "$LOG_SUBAGENT"
assert_fixture_dir "$LOGROOT"
LOG_SEL="$LOGROOT/sel.log"; printf 'AFFECTED_GATE_REFUSED reason=below-floor\nAFFECTED_UNRESOLVED reason=below-floor\n' > "$LOG_SEL"
assert_fixture_dir "$LOGROOT"
LOG_MIX_UNRES="$LOGROOT/mix1.log"; { printf '%s\n' "$SIB1"; echo 'AFFECTED_UNRESOLVED reason=zero-selected'; } > "$LOG_MIX_UNRES"
assert_fixture_dir "$LOGROOT"
LOG_MIX_FAIL="$LOGROOT/mix2.log"; { printf '%s\n' "$SIB1"; echo '[FAIL] some-suite'; } > "$LOG_MIX_FAIL"
assert_fixture_dir "$LOGROOT"
LOG_MIX_KILLED="$LOGROOT/mix3.log"; { printf '%s\n' "$SIB1"; echo '[KILLED] some-suite (exit=137)'; } > "$LOG_MIX_KILLED"
assert_fixture_dir "$LOGROOT"
LOG_MIX_SUBAGENT="$LOGROOT/mix4.log"; { printf '%s\n' "$SIB1"; printf '%s\n' "$SUBAGENT_LINE"; } > "$LOG_MIX_SUBAGENT"
assert_fixture_dir "$LOGROOT"
LOG_MIX_GATE="$LOGROOT/mix5.log"; { printf '%s\n' "$SIB1"; echo 'AFFECTED_GATE_REFUSED reason=no-stack'; } > "$LOG_MIX_GATE"
assert_fixture_dir "$LOGROOT"
LOG_MISE="$LOGROOT/mise.log"; { printf '%s\n' "$SIB1"; echo 'mise ERROR no version is set for shim: bun'; } > "$LOG_MISE"
assert_fixture_dir "$LOGROOT"
LOG_MIDLINE="$LOGROOT/midline.log"; printf 'test output: %s\n' "$SIB1" > "$LOG_MIDLINE"
assert_fixture_dir "$LOGROOT"
LOG_ZERO="$LOGROOT/zero.log"; printf '%s\n' "$SIB0" > "$LOG_ZERO"
assert_fixture_dir "$LOGROOT"
LOG_EMPTY="$LOGROOT/empty.log"; : > "$LOG_EMPTY"
assert_fixture_dir "$LOGROOT"
LOG_TEXT="$LOGROOT/text.log"; printf 'something entirely unrelated\n' > "$LOG_TEXT"
fb_log() { assert_fixture_dir "$LOGROOT"; printf 'AFFECTED_FALLBACK\treason=%s\n%s\n' "$1" "$SIB1" > "$LOGROOT/fb-$1.log"; printf '%s' "$LOGROOT/fb-$1.log"; }
LOG_FB_FORCE="$(fb_log force-all)"; LOG_FB_INDEX="$(fb_log index-missing)"; LOG_FB_ENUM="$(fb_log enumerate-unavailable)"
LOG_FB_RUNNER="$(fb_log runner-changed)"; LOG_FB_UNDEC="$(fb_log undecidable-diff)"; LOG_FB_UNKNOWN="$(fb_log brand-new-reason)"
LOG_CNF="$LOGROOT/cnf.log"; { printf '%s\n' "$SIB1"; echo 'bash: bun: command not found'; } > "$LOG_CNF"
LOG_RR_FOO="$LOGROOT/rrfoo.log"; { printf '%s\n' "$SIB1"; echo 'AFFECTED_GATE_REFUSED reason=runner-refused-foo'; } > "$LOG_RR_FOO"
fb_raw() { assert_fixture_dir "$LOGROOT"; printf '%s\n%s\n' "$2" "$SIB1" > "$LOGROOT/fbraw-$1.log"; printf '%s' "$LOGROOT/fbraw-$1.log"; }
LOG_FB_EMPTY="$(fb_raw empty "$(printf 'AFFECTED_FALLBACK\treason=')")"
LOG_FB_GLUED="$(fb_raw glued "$(printf 'AFFECTED_FALLBACK\treason=runner-changed2')")"
LOG_FB_NOREASON="$(fb_raw noreason "$(printf 'AFFECTED_FALLBACK\tsomething-else')")"
LOG_FB_QUOTED="$(fb_raw quoted "$(printf 'AFFECTED_FALLBACK\treason="force-all"')")"
assert_fixture_dir "$LOGROOT"
LOG_FB_TWO_A="$LOGROOT/fbtwoa.log"; { printf 'AFFECTED_FALLBACK\treason=runner-changed\nAFFECTED_FALLBACK\treason=index-missing\n%s\n' "$SIB1"; } > "$LOG_FB_TWO_A"
assert_fixture_dir "$LOGROOT"
LOG_FB_TWO_B="$LOGROOT/fbtwob.log"; { printf 'AFFECTED_FALLBACK\treason=index-missing\nAFFECTED_FALLBACK\treason=runner-changed\n%s\n' "$SIB1"; } > "$LOG_FB_TWO_B"
STATE="$LOGROOT/state"

assert_eq "1" "$([[ "$SIB1" == *"1 sibling full-gate run(s) already in flight"* ]] && echo 1 || echo 0)" \
  "the refusal fixture was rendered from the live runner (non-empty, carries the sibling clause)"

# --- runner ---------------------------------------------------------------------------------
# run_wait <work> <args...>: sets OUT, RC, V (verdict word), W (waited_s). RUN_CWD overrides the cwd.
run_wait() {
  local work="$1"; shift
  OUT="$( cd "${RUN_CWD:-$work}" && git_fixture_env "$work" >/dev/null 2>&1; PATH="$STUBS:$PATH" REAL_GIT="$REAL_GIT" FAIL_GIT_MATCH="${FAIL_GIT_MATCH:-}" CAP_DIR="$CAPD" timeout 25 bash "$SCRIPT" "$@" 2>&1 )"
  RC=$?
  V="$(sed -n 's/.*verdict=\([A-Z_]*\).*/\1/p' <<<"$OUT" | tail -1)"
  W="$(sed -n 's/.*waited_s=\([0-9]*\).*/\1/p' <<<"$OUT" | tail -1)"
}
# Standard wait invocation on W0 with a small budget.
wait_small() { # <log> [extra args]
  local log="$1"; shift
  run_wait "$W0" --log "$log" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5 "$@"
}
start_arm() { assert_fixture_dir "$STATE"; clock_at "$BASE"; : > "$STATE"; }

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
assert_eq "class=contention" "$(classify "$LOG_AFFREAL")" "A17 a log shaped like a real affected-tests.sh refusal (tab fallback line, gate lines) is contention"
assert_eq "class=not-waitable" "$(classify "$LOG_MIDLINE")" "A18 the sentence in the middle of a line is NOT a runner refusal (anchored)"
assert_eq "class=not-waitable" "$(classify "$LOG_ZERO")" "A19 '0 sibling' is NOT a refusal (the runner refuses only for N > 0)"
assert_eq "class=not-waitable" "$(classify "$LOG_MISE")" "A20 sibling text + a toolchain fault is NOT waitable"
assert_eq "class=contention-force-all" "$(classify "$LOG_FB_FORCE")" "A21 AFFECTED_FALLBACK reason=force-all is contention that behaves like --full"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_INDEX")" "A22 AFFECTED_FALLBACK reason=index-missing (a broken index) is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_ENUM")" "A23 AFFECTED_FALLBACK reason=enumerate-unavailable is NOT waitable"
assert_eq "class=contention" "$(classify "$LOG_FB_RUNNER")" "A24 AFFECTED_FALLBACK reason=runner-changed stays waitable"
assert_eq "class=contention" "$(classify "$LOG_FB_UNDEC")" "A25 AFFECTED_FALLBACK reason=undecidable-diff stays waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_UNKNOWN")" "A26 an unknown AFFECTED_FALLBACK reason fails closed"
assert_eq "class=not-waitable" "$(classify "$LOG_CNF")" "A27 sibling text + 'command not found' (a toolchain fault) is NOT waitable"
assert_eq "class=not-waitable" "$(classify "$LOG_RR_FOO")" "A28 'reason=runner-refused-foo' is not the runner-refused exemption (anchored)"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_EMPTY")" "A29 AFFECTED_FALLBACK with an empty reason stops"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_GLUED")" "A30 AFFECTED_FALLBACK reason=runner-changed2 (a known name with a suffix) stops"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_NOREASON")" "A31 an AFFECTED_FALLBACK line with no reason= stops"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_QUOTED")" "A32 a quoted AFFECTED_FALLBACK reason stops"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_TWO_A")" "A33 runner-changed then index-missing: every fallback line is judged (the second stops)"
assert_eq "class=not-waitable" "$(classify "$LOG_FB_TWO_B")" "A34 index-missing then runner-changed: every fallback line is judged (the first stops)"

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
assert_eq "42/CI_IS_THE_GATE" "$RC/$V" "B6 a valid reading earlier then CAPACITY_UNKNOWN keeps waiting and still defers (sticky, CTO fork 5)"

start_arm; cap "$CAP_UNKNOWN"
wait_small "$LOG_SIB1"
assert_eq "11/NOT_WAITABLE" "$RC/$V" "B7 capacity never readable (UNKNOWN only) -> NOT_WAITABLE, a stop not a deferral"
assert_eq "1" "$([[ "$OUT" == *"reason=capacity-unreadable"* ]] && echo 1 || echo 0)" "B8 the reason names capacity-unreadable"

start_arm; cap FAIL
wait_small "$LOG_SIB1"
assert_eq "11" "$RC" "B9 a failing capacity call for the whole budget -> exit 11"

start_arm; cap HANG
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 1
assert_eq "11" "$RC" "B10 a hung capacity call is bounded by the probe timeout and ends as capacity-unreadable (exit 11)"

start_arm; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 100 --probe-timeout-s 5
assert_eq "3" "$(slept_total)" "B11 a long interval is clamped to the remaining budget (never sleeps past the deadline)"

# shared budget across two invocations, killed mid-wait
assert_fixture_dir "$STUBS"
start_arm; cap "$CAP_BUSY"; printf '2\n' > "$STUBS/die_after"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1 --probe-timeout-s 5
assert_eq "$BASE" "$(tr -d '[:space:]' < "$STATE")" "B12 the episode epoch is written before the first poll (survives a kill)"
assert_fixture_dir "$STUBS"
printf '%s\n' "$(( BASE + 2 ))" > "$STUBS/clock"; : > "$STUBS/sleeplog"; rm -f "$STUBS/die_after"; rm -f "$CAPD/n"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1 --probe-timeout-s 5
assert_eq "42/6/4" "$RC/$W/$(slept_total)" "B13 the second invocation shares the first one's budget (waited_s=6 total, slept 4 more)"

# state: pre-seeded epoch
assert_fixture_dir "$STATE"
clock_at "$BASE"; cap "$CAP_BUSY"; printf '%s\n' "$(( BASE - 1000 ))" > "$STATE"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 1800 --interval-s 60 --probe-timeout-s 5
assert_eq "42/1800/800" "$RC/$W/$(slept_total)" "B14 a seeded epoch 1000 s old leaves 800 s of the 1800 s budget"

assert_fixture_dir "$STATE"
clock_at "$BASE"; : > "$STATE"; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5
assert_eq "42" "$RC" "B15 an empty state file starts a fresh episode"

state_row() { # <label> <state-content> <reason-fragment> ; expects exit 2 with an ERROR verdict line naming the reason
  assert_fixture_dir "$STATE"
  clock_at "$BASE"; cap "$CAP_BUSY"; printf '%s\n' "$2" > "$STATE"
  run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5
  assert_eq "2/ERROR/1" "$RC/$V/$([[ "$OUT" == *"reason=$3"* ]] && echo 1 || echo 0)" "B state file rejected with exit 2 (reason $3): $1"
}
state_row "non-integer" "garbage" "state-file-holds-a-malformed-epoch"
state_row "future epoch" "$(( BASE + 500 ))" "state-file-holds-a-future-epoch"
state_row "zero (would spend the whole budget)" "0" "state-file-holds-a-malformed-epoch"
state_row "octal-looking leading zero" "010" "state-file-holds-a-malformed-epoch"
state_row "64-bit wrap (20 digits)" "18446744073709551617" "state-file-holds-a-malformed-epoch"
state_row "too short (7 digits)" "1000000" "state-file-holds-a-malformed-epoch"
state_row "stale epoch (older than 6 h)" "$(( BASE - 30000 ))" "state-file-is-stale-create-a-fresh-one"
state_row "stale by exactly one second past the bound" "$(( BASE - 21601 ))" "state-file-is-stale-create-a-fresh-one"
clock_at "$BASE"; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$LOGROOT" --budget-s 3 --interval-s 1 --probe-timeout-s 5
assert_eq "2/ERROR/1" "$RC/$V/$([[ "$OUT" == *"reason=state-file-missing-or-not-a-file"* ]] && echo 1 || echo 0)" "B state path that is a directory is rejected with exit 2 (reason state-file-missing-or-not-a-file)"
assert_fixture_dir "$STATE"
clock_at "abc"; : > "$STATE"; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5
assert_eq "2/ERROR/1" "$RC/$V/$([[ "$OUT" == *"reason=cannot-read-the-clock"* ]] && echo 1 || echo 0)" "B a non-numeric clock is rejected with exit 2 (reason cannot-read-the-clock)"
# an epoch exactly at the bound is still accepted (the budget is spent at once, so it defers)
clock_at "$BASE"; cap "$CAP_BUSY"; printf '%s\n' "$(( BASE - 21600 ))" > "$STATE"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5
assert_eq "42" "$RC" "B a state epoch exactly 21600 s old is still accepted"

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

# capacity parsing
start_arm; cap "$CAP_OK_BUSY"
wait_small "$LOG_SIB1"
assert_eq "42" "$RC" "B22 CAPACITY_OK with measured_runs=1 (busy) is a valid reading and keeps waiting"
start_arm; cap '[contention] CAPACITY_OK measured_runs=05 measured_suites=0'
wait_small "$LOG_SIB1"
assert_eq "42" "$RC" "B23 measured_runs=05 is not idle"
start_arm; cap 'MULTI:[contention] CAPACITY_OK measured_runs=1\n[contention] CAPACITY_OK measured_runs=0'
wait_small "$LOG_SIB1"
assert_eq "42" "$RC" "B24 only the first capacity banner line is read"
start_arm; cap "IDLEFAIL:$CAP_OK_IDLE"
wait_small "$LOG_SIB1"
assert_eq "11" "$RC" "B25 an idle line from a call that exited non-zero is unreadable, not idle"
start_arm; cap 'MULTI:[contention]   -> pid 5 in /w/CAPACITY_OK measured_runs=0 (running 3s)\n[contention] BANNER CAPACITY_UNKNOWN reason=x measured_runs=?'
wait_small "$LOG_SIB1"
assert_eq "11" "$RC" "B26 a sibling detail row naming the token is not a capacity banner (anchored)"
start_arm; cap 'CAPACITY_OK measured_runs=0 measured_suites=0'
wait_small "$LOG_SIB1"
assert_eq "10" "$RC" "B27 an unprefixed CAPACITY_OK measured_runs=0 line (as the skills print it) is idle"

start_arm; cap "$CAP_BUSY" "$CAP_BUSY" "$CAP_BUSY" "$CAP_OK_IDLE"
wait_small "$LOG_SIB1"
assert_eq "10/RETRY/3" "$RC/$V/$W" "B28 idle on the FINAL poll (elapsed == budget) is RETRY, not a deferral"
start_arm; cap '[contention] CAPACITY_OKAY measured_runs=0'
wait_small "$LOG_SIB1"
assert_eq "11" "$RC" "B29 CAPACITY_OKAY is not the CAPACITY_OK banner (token boundary)"
start_arm; cap "STDERR:$CAP_OK_IDLE"
wait_small "$LOG_SIB1"
assert_eq "10" "$RC" "B30 a capacity banner printed on stderr (as the runner prints its [contention] lines) is read"
start_arm; cap STUBBORN
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 1
assert_eq "11" "$RC" "B31 a probe that ignores TERM is killed by the escalation and ends as capacity-unreadable (exit 11)"
start_arm; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 100000 --interval-s 100000 --probe-timeout-s 5
assert_eq "42/100000" "$RC/$W" "B32 a six-digit budget is accepted"

# --- C. infra carve-out, --full ---------------------------------------------------------------
# Fixtures are built once per shape (the script only reads them) and reused by the mutation rows.
infra_fixture() { # <out-var> <mutating-shell-snippet>
  local root; new_root root
  build_repo "$1" "$root" || { echo "FATAL: fixture build failed" >&2; exit 1; }
  ( cd "${!1}" && git_fixture_env "${!1}" && bash -c "$2" ) >/dev/null 2>&1
}
infra_fixture IW_PREFIX 'printf x >> apps/web-platform/infra/main.tf && git commit -qam infra'
infra_fixture IW_WF 'mkdir -p .github/workflows && printf x > .github/workflows/apply-web-platform-infra.yml && git add -A && git commit -qm wf'
infra_fixture IW_WORKTREE 'printf x >> apps/web-platform/infra/main.tf'
infra_fixture IW_UNTRACKED 'printf x > apps/web-platform/infra/new.tf'
infra_fixture IW_RENAME 'mkdir -p docs && git mv apps/web-platform/infra/main.tf docs/moved.tf && git commit -qm rename'
infra_fixture IW_RENAME_STAGED 'mkdir -p docs && git mv apps/web-platform/infra/main.tf docs/moved.tf'
infra_fixture IW_NOREMOTE 'git update-ref -d refs/remotes/origin/main'
infra_fixture IW_SUBSTR_IN 'mkdir -p docs/apps/web-platform/infra && printf x > docs/apps/web-platform/infra/notes.md && git add -A && git commit -qm sub'
infra_fixture IW_SUBSTR_OUT 'printf x > apps/web-platform/infra-notes.md && git add -A && git commit -qm sub'
infra_fixture IW_EMPTY 'git reset -q --hard origin/main'
infra_fixture IW_CIYML 'mkdir -p .github/workflows && printf x > .github/workflows/ci.yml && git add -A && git commit -qm ci'
infra_fixture IW_NEAR 'mkdir -p docs/web-platform/infra && printf x > docs/web-platform/infra/notes.md && git add -A && git commit -qm near'
infra_fixture IW_IGNORED 'printf "build.log\n" > .gitignore && git add .gitignore && git commit -qm ignore && printf x > apps/web-platform/infra/build.log'
infra_row() { # <label> <fixture-path> <expected-rc/verdict>
  start_arm; cap "$CAP_BUSY"
  run_wait "$2" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5
  assert_eq "$3" "$RC/$V" "C $1"
}
infra_row "committed edit under apps/web-platform/infra/ -> QUEUE_IN_LOCK, never 42" "$IW_PREFIX" "12/QUEUE_IN_LOCK"
infra_row "committed edit to the apply-infra workflow file -> QUEUE_IN_LOCK" "$IW_WF" "12/QUEUE_IN_LOCK"
infra_row "uncommitted working-tree edit under infra -> QUEUE_IN_LOCK" "$IW_WORKTREE" "12/QUEUE_IN_LOCK"
infra_row "untracked new file under infra -> QUEUE_IN_LOCK" "$IW_UNTRACKED" "12/QUEUE_IN_LOCK"
infra_row "committed rename of a file OUT of infra (the SOURCE is the infra path) -> QUEUE_IN_LOCK" "$IW_RENAME" "12/QUEUE_IN_LOCK"
infra_row "staged, uncommitted rename OUT of infra -> QUEUE_IN_LOCK" "$IW_RENAME_STAGED" "12/QUEUE_IN_LOCK"
infra_row "git cannot resolve origin/main...HEAD (diff-unresolved) -> QUEUE_IN_LOCK" "$IW_NOREMOTE" "12/QUEUE_IN_LOCK"
assert_eq "1" "$([[ "$OUT" == *"reason=diff-unresolved"* ]] && echo 1 || echo 0)" "C an unresolved diff names diff-unresolved"
infra_row "the infra path as an inner substring (docs/apps/web-platform/infra/x) is infra, as the runner's substring match says" "$IW_SUBSTR_IN" "12/QUEUE_IN_LOCK"
infra_row "a sibling name that is not the infra prefix (apps/web-platform/infra-notes.md) is clean" "$IW_SUBSTR_OUT" "42/CI_IS_THE_GATE"
infra_row "an empty change set is unresolved, never clean" "$IW_EMPTY" "12/QUEUE_IN_LOCK"
infra_row "another workflow file (ci.yml) is clean: only the apply-infra workflow is a trigger" "$IW_CIYML" "42/CI_IS_THE_GATE"
infra_row "web-platform/infra/ without the apps/ prefix is clean" "$IW_NEAR" "42/CI_IS_THE_GATE"
infra_row "a gitignored file under infra is not a change" "$IW_IGNORED" "42/CI_IS_THE_GATE"
RUN_CWD="$IW_UNTRACKED/apps"; infra_row "an untracked infra file is seen from a subdirectory cwd (repo-root git)" "$IW_UNTRACKED" "12/QUEUE_IN_LOCK"; RUN_CWD=""
for fm in 'diff --name-only HEAD' 'diff --name-status -M HEAD' 'diff --name-status -M origin/main...HEAD' 'ls-files --others'; do
  FAIL_GIT_MATCH="$fm"; infra_row "a failing git read ($fm) fails closed to QUEUE_IN_LOCK" "$W0" "12/QUEUE_IN_LOCK"; FAIL_GIT_MATCH=""
done

start_arm; cap "$CAP_BUSY"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5 --full
assert_eq "12/QUEUE_IN_LOCK" "$RC/$V" "C --full + contention never defers (exit 12)"
start_arm; cap "$CAP_BUSY" "$CAP_OK_IDLE"
run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5 --full
assert_eq "10" "$RC" "C --full still gets RETRY when capacity frees up inside the budget"
start_arm; cap "$CAP_BUSY"
wait_small "$LOG_FB_FORCE"
assert_eq "12/QUEUE_IN_LOCK" "$RC/$V" "C a log carrying AFFECTED_FALLBACK reason=force-all behaves like --full (exit 12)"
start_arm; cap "$CAP_BUSY"
wait_small "$LOG_FB_INDEX"
assert_eq "11/NOT_WAITABLE" "$RC/$V" "C a broken affected index exits 11 without waiting"

# --- D. arguments ----------------------------------------------------------------------------
start_arm; cap "$CAP_BUSY"
for bad in "--budget-s abc" "--budget-s -5" "--budget-s 0" "--budget-s 1234567" "--interval-s x" "--probe-timeout-s 0" "--bogus" "--budget-s" "--state"; do
  # shellcheck disable=SC2086
  run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" $bad
  assert_eq "2" "$RC" "D arg rejected with exit 2: $bad"
done
run_wait "$W0" --state "$STATE"
assert_eq "2" "$RC" "D --log is required (exit 2)"
run_wait "$W0" --state "$STATE" --log
assert_eq "2" "$RC" "D --log with no value is rejected (exit 2)"
run_wait "$W0" --log "$LOG_SIB1" --state relative-state
assert_eq "2" "$RC" "D a relative --state path is rejected (exit 2)"
start_arm; cap "$CAP_BUSY"
BATTERY_REFUSAL_WAIT_BUDGET_S=1 SHIP_BATTERY_WAIT_BUDGET_S=1 run_wait "$W0" --log "$LOG_SIB1" --state "$STATE"
assert_eq "42/1800/1800" "$RC/$W/$(slept_total)" "D1 defaults are 1800 s budget / 60 s interval via flags only (env vars are ignored)"
assert_eq "1" "$([[ "$(head -1 "$STUBS/sleeplog")" == "60" ]] && echo 1 || echo 0)" "D2 the default interval is 60 s"

# --- E. the recipe: its case on wait_rc, and the whole recipe executed against stubs -----------
recipe_block() { # <ref-md> ; the bash fence under '## Recipe'
  awk '/^## Recipe/{r=1} r&&/^```bash/{f=1;next} f&&/^```/{exit} f{print}' "$1"
}
assert_eq "1" "$(grep -c 'case "\$wait_rc" in' "$REF_MD")" "E0a the reference carries exactly one case on wait_rc (no decoy)"
RECIPE="$(recipe_block "$REF_MD")"
CASE_BLOCK="$(awk '/case "\$wait_rc" in/{f=1} f{print} /^[[:space:]]*esac/{if(f) exit}' <<<"$RECIPE")"
assert_eq "1" "$([[ -n "$CASE_BLOCK" ]] && echo 1 || echo 0)" "E0 the recipe fence carries a case on wait_rc"
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

# Execute the recipe: stub plugin root with a scripted affected-tests.sh and wait script.
new_root RECROOT
RPLUG="$RECROOT/plugin"; RSTUB="$RECROOT/bin"; RWORK="$RECROOT/work"
mkdir -p "$RPLUG/scripts" "$RPLUG/skills/ship/scripts" "$RSTUB" "$RWORK" "$RECROOT/tmp"
assert_fixture_dir "$RSTUB"
cat > "$RSTUB/sleep" <<STUB
#!/usr/bin/env bash
exec "$REAL_SLEEP" 0.05
STUB
assert_fixture_dir "$RPLUG"
cat > "$RPLUG/scripts/affected-tests.sh" <<STUB
#!/usr/bin/env bash
# scripted battery: records argv, marks itself running for 0.3 s, prints a log, exits with \$REC/aff.rc (default 4)
echo "\$*" >> "\$REC/aff.argv"
: > "\$REC/aff.running"
"$REAL_SLEEP" 0.3
rm -f "\$REC/aff.running"
echo "stub battery log \$(wc -l < "\$REC/aff.argv" | tr -d ' ')"
exit "\$(cat "\$REC/aff.rc" 2>/dev/null || echo 4)"
STUB
assert_fixture_dir "$RPLUG"
cat > "$RPLUG/skills/ship/scripts/battery-refusal-wait.sh" <<'STUB'
#!/usr/bin/env bash
# scripted wait: validates its argv like the real script (--log <battery log> --state <file> [--full]),
# records whether the battery was still running and what the state file held, then pops the next code
echo "$*" >> "$REC/wait.argv"
[[ "$1" == "--log" && "$3" == "--state" ]] || { echo "wait stub: bad argv: $*" >&2; exit 64; }
log="$2"; state="$4"
[[ -s "$log" && "$(head -n 1 "$log")" == "stub battery log "* ]] || { echo "wait stub: --log is not the battery log" >&2; exit 65; }
[[ -f "$state" ]] || { echo "wait stub: --state is not a file" >&2; exit 66; }
echo "state=$state" >> "$REC/wait.state"
if [[ -e "$REC/aff.running" ]]; then echo "running=1" >> "$REC/wait.state"; else echo "running=0" >> "$REC/wait.state"; fi
# fresh=0: the log still belongs to an EARLIER launch (a stale rc file let the recipe read a verdict that was not this launch's)
if [[ "$(head -n 1 "$log")" == "stub battery log $(wc -l < "$REC/aff.argv" | tr -d ' ')" ]]; then echo "fresh=1" >> "$REC/wait.state"; else echo "fresh=0" >> "$REC/wait.state"; fi
echo "prev=<$(cat "$state")>" >> "$REC/wait.state"
n="$(wc -l < "$REC/wait.argv" | tr -d ' ')"; echo "epoch-$n" > "$state"
code="$(head -n 1 "$REC/wait.codes" 2>/dev/null)"; [[ -n "$code" ]] || code=11
tail -n +2 "$REC/wait.codes" > "$REC/wait.codes.new" 2>/dev/null; mv -f "$REC/wait.codes.new" "$REC/wait.codes" 2>/dev/null
echo "BATTERY_REFUSAL_WAIT verdict=STUB code=$code"
exit "$code"
STUB
chmod +x "$RSTUB/sleep" "$RPLUG/scripts/affected-tests.sh" "$RPLUG/skills/ship/scripts/battery-refusal-wait.sh"
run_recipe() { # <recipe-text> <FULL_BATTERY> <battery-rc> <wait codes...> ; sets REC_OUT
  local recipe="$1" fb="$2" arc="$3"; shift 3
  export REC="$RECROOT/rec"
  assert_fixture_dir "$REC"
  rm -rf "$REC"; mkdir -p "$REC"
  printf '%s\n' "$arc" > "$REC/aff.rc"; : > "$REC/aff.argv"; : > "$REC/wait.argv"; : > "$REC/wait.state"
  assert_fixture_dir "$REC"
  if (( $# )); then printf '%s\n' "$@" > "$REC/wait.codes"; else : > "$REC/wait.codes"; fi
  REC_OUT="$( cd "$RWORK" && TMPDIR="$RECROOT/tmp" PATH="$RSTUB:$PATH" CLAUDE_PLUGIN_ROOT="$RPLUG" FULL_BATTERY="$fb" timeout 60 bash -c "$recipe" 2>&1 )"
}
rec_res() { # a compact result: markers, battery launches, whether --full reached each script
  local m
  m="$(grep -oE 'BATTERY DONE|RELAUNCH|CONTINUE_CI_IS_THE_GATE|QUEUE_IN_LOCK|STOP' <<<"$REC_OUT" | tr '\n' ',')"
  RES="$m aff=$(wc -l < "$REC/aff.argv" | tr -d ' ') afffull=$(grep -c -- '--full' "$REC/aff.argv") waitfull=$(grep -c -- '--full' "$REC/wait.argv") statepaths=$(sort -u "$REC/wait.state" | grep -c '^state=') carry=$(grep -c '^prev=<epoch' "$REC/wait.state") racy=$(grep -c -E '^(running=1|fresh=0)' "$REC/wait.state")"
}
recipe_scn() { run_recipe "$RECIPE_UNDER_TEST" "$1" "$2" "${@:3}"; rec_res; }
RECIPE_UNDER_TEST="$RECIPE"
recipe_scn false 4 42;                      assert_eq "CONTINUE_CI_IS_THE_GATE, aff=1 afffull=0 waitfull=0 statepaths=1 carry=0 racy=0" "$RES" "E1 refused battery + wait 42 -> continue as CI is the gate"
recipe_scn false 4 10 42;                   assert_eq "RELAUNCH,CONTINUE_CI_IS_THE_GATE, aff=2 afffull=0 waitfull=0 statepaths=1 carry=1 racy=0" "$RES" "E2 wait 10 relaunches the battery, then 42 continues"
recipe_scn false 4 11;                      assert_eq "STOP, aff=1 afffull=0 waitfull=0 statepaths=1 carry=0 racy=0" "$RES" "E3 wait 11 stops"
recipe_scn false 4 12;                      assert_eq "QUEUE_IN_LOCK, aff=1 afffull=0 waitfull=0 statepaths=1 carry=0 racy=0" "$RES" "E4 wait 12 selects the queue-in-lock path"
recipe_scn false 4 1;                       assert_eq "STOP, aff=1 afffull=0 waitfull=0 statepaths=1 carry=0 racy=0" "$RES" "E5 a stray wait status 1 stops (the script crashed)"
recipe_scn false 4 10 10 10 10 10;          assert_eq "RELAUNCH,RELAUNCH,RELAUNCH,RELAUNCH,STOP, aff=4 afffull=0 waitfull=0 statepaths=1 carry=3 racy=0" "$RES" "E6 relaunches are capped at 3 (4 launches in all): the 4th request for a relaunch stops the recipe"
recipe_scn true 4 42;                       assert_eq "CONTINUE_CI_IS_THE_GATE, aff=1 afffull=1 waitfull=1 statepaths=1 carry=0 racy=0" "$RES" "E7 FULL_BATTERY=true launches the battery with --full and passes --full to the wait script"
recipe_scn false 0;                         assert_eq "BATTERY DONE, aff=1 afffull=0 waitfull=0 statepaths=0 carry=0 racy=0" "$RES" "E8 a battery that ran (rc 0) never calls the wait script"
recipe_scn false 1;                         assert_eq "BATTERY DONE, aff=1 afffull=0 waitfull=0 statepaths=0 carry=0 racy=0" "$RES" "E9 a red battery (rc 1) never calls the wait script"

# --- F. parity + wiring ----------------------------------------------------------------------
assert_eq "1" "$(grep -cF 'sibling full-gate run(s) already in flight' "$LIVE_RUNNER" | awk '{print ($1>=1)}')" "F1 the live runner carries the sibling-refusal clause"
for lit in 'apps/web-platform/infra/' '.github/workflows/apply-web-platform-infra.yml'; do
  assert_eq "1" "$(grep -cF -- "'$lit'" "$LIVE_RUNNER" | awk '{print ($1>=1)}')" "F infra literal in the live runner: $lit"
  assert_eq "1" "$(grep -cF -- "'$lit'" "$REAL_SCRIPT" | awk '{print ($1>=1)}')" "F infra literal in the script's CODE (quoted, not the header prose): $lit"
done
assert_eq "1" "$(grep -cF 'battery-refusal-wait.sh' "$SKILL_MD" | awk '{print ($1>=1)}')" "F3 SKILL.md names the script"
assert_eq "1" "$(grep -cF '](./references/battery-refusal-wait.md)' "$SKILL_MD" | awk '{print ($1>=1)}')" "F4 SKILL.md links the reference"
assert_eq "0" "$(grep -c 'go back to waiting' "$SKILL_MD")" "F5 the unbounded 'go back to waiting' prescription is gone"
assert_eq "1" "$(grep -cF 'SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=39600 bash scripts/test-all.sh --full' "$SKILL_MD" | awk '{print ($1>=1)}')" "F6 the queue-in-lock command (target of exit 12) is kept"
assert_eq "1" "$(grep -cE 'rc=4. is REFUSED' "$SKILL_MD" | awk '{print ($1>=1)}')" "F7 the rc=4 REFUSED sentence is intact"
PR_LINE="$(grep -F 'Local battery refused (sibling contention)' "$REF_MD" 2>/dev/null | head -1)"
assert_eq "1" "$([[ "$PR_LINE" == *'CI "test" is the authoritative gate; local run NOT executed.'* ]] && echo 1 || echo 0)" "F8 the reference carries the fixed PR Test plan line"
assert_eq "0" "$(grep -ciE 'passed|verified' <<<"$PR_LINE")" "F9 the PR Test plan line never says passed or verified"
assert_eq "1" "$(grep -c 'wait_rc' "$REF_MD" 2>/dev/null | awk '{print ($1>=1)}')" "F10 the recipe names the script status wait_rc, not rc"
POINTER="$(grep -F 'Under contention, launch first' "$SKILL_MD" | head -1)"
assert_eq "1" "$([[ "$POINTER" == *'12 (queue inside the lock) or 11 (stop)'* && "$POINTER" == *'only 42 continues'* && "$POINTER" == *'42 (CI is the gate'* && "$POINTER" == *'10 (capacity idle: relaunch)'* && "$POINTER" == *'persistent: true'* ]] && echo 1 || echo 0)" "F11 the SKILL.md pointer states every exit's action, that only 42 continues, and the Monitor mode"
# The infra trigger SET of the live runner equals the script's (a third runner trigger would otherwise go unnoticed).
RUNNER_LITS="$(awk '/^_infra_in_diff=0/{f=1} f{print} f&&/^fi$/{exit}' "$LIVE_RUNNER" | grep -oE "grep -qF '[^']+'" | sed "s/grep -qF //" | sort | tr '\n' ' ')"
SCRIPT_LITS="$(grep -E "for lit in " "$REAL_SCRIPT" | grep -oE "'[^']+'" | sort | tr '\n' ' ')"
assert_eq "1" "$([[ -n "$RUNNER_LITS" && "$RUNNER_LITS" == "$SCRIPT_LITS" ]] && echo 1 || echo 0)" "F13 the live runner's infra trigger set equals the script's (runner: $RUNNER_LITS)"
assert_eq "1" "$([[ -n "$RECIPE" && "$RECIPE" == *'affected-tests.sh'* && "$RECIPE" != *'test-all.sh'* ]] && echo 1 || echo 0)" "F12 the recipe launches the pinned dispatch (affected-tests.sh), never a bare test-all.sh"

# --- G. mutation battery (mutants of a COPY; the real script is never touched) -----------------
new_root MROOT
mutate() { # <id> <count> <old1> <new1> [<old2> <new2>] -> sets SCRIPT to the mutant or returns 1
  local id="$1" cnt="$2" m
  m="$MROOT/mut-$id.sh"
  assert_fixture_dir "$m"
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
restore() { SCRIPT="$REAL_SCRIPT"; REF_MD="$REAL_REF_MD"; RECIPE_UNDER_TEST="$RECIPE"; }
# verdict_of is the ONE place a mutant is judged; controls below prove it can say both words.
verdict_of() { if [[ "$1" != "$2" ]]; then echo killed; else echo still-green; fi; }
assert_eq "still-green" "$(verdict_of same same)" "G-ctl a mutant that reproduces the real result is judged still-green"
assert_eq "killed" "$(verdict_of mutant real)" "G-ctl a mutant that differs from the real result is judged killed"
# <id> <label> <real-result> <scenario-fn>; the scenario leaves a compact result in RES.
mrow() {
  local id="$1" label="$2" want="$3" fn="$4" got
  "$fn"; got="$RES"
  assert_eq "killed" "$(verdict_of "$got" "$want")" "G $id: $label goes RED against the mutant (got $got, real $want)"
  restore
}
res() { local r; r="$(sed -n 's/.*reason=\([A-Za-z0-9_-]*\).*/\1/p' <<<"$OUT" | tail -1)"; RES="$RC/$V/$W/$(slept_total)/$r"; }
scn_defer()  { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SIB1"; res; }
scn_lowtmp() { start_arm; cap "$CAP_LOWTMP"; wait_small "$LOG_SIB1"; res; }
scn_unread() { start_arm; cap FAIL; wait_small "$LOG_SIB1"; res; }
scn_mixu()   { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_MIX_UNRES"; res; }
scn_mixf()   { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_MIX_FAIL"; res; }
scn_sel()    { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SEL"; res; }
scn_sub()    { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SUBAGENT"; res; }
scn_full()   { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_SIB1" --full; res; }
scn_garbage(){ assert_fixture_dir "$STATE"; clock_at "$BASE"; printf 'garbage\n' > "$STATE"; cap "$CAP_BUSY"; wait_small "$LOG_SIB1"; res; }
scn_stale()  { assert_fixture_dir "$STATE"; clock_at "$BASE"; printf '%s\n' "$(( BASE - 30000 ))" > "$STATE"; cap "$CAP_BUSY"; wait_small "$LOG_SIB1"; res; }
scn_shared() { assert_fixture_dir "$STATE"; clock_at "$BASE"; cap "$CAP_BUSY"; printf '%s\n' "$(( BASE - 1000 ))" > "$STATE"
               run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 1800 --interval-s 60 --probe-timeout-s 5; res; }
scn_boundary() { start_arm; cap "$CAP_BUSY"; run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5; res; }
scn_midkill() { assert_fixture_dir "$STUBS"; start_arm; cap "$CAP_BUSY"; printf '2\n' > "$STUBS/die_after"
                run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1 --probe-timeout-s 5
                assert_fixture_dir "$STUBS"
                printf '%s\n' "$(( BASE + 2 ))" > "$STUBS/clock"; : > "$STUBS/sleeplog"; rm -f "$STUBS/die_after"; rm -f "$CAPD/n"
                run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 6 --interval-s 1 --probe-timeout-s 5; res; }
scn_infra() { start_arm; cap "$CAP_BUSY"; run_wait "$1" --log "$LOG_SIB1" --state "$STATE" --budget-s 3 --interval-s 1 --probe-timeout-s 5; res; }
scn_infra_wf() { scn_infra "$IW_WF"; }
scn_infra_rn() { scn_infra "$IW_RENAME"; }
scn_infra_unres() { scn_infra "$IW_NOREMOTE"; }
scn_infra_empty() { scn_infra "$IW_EMPTY"; }
scn_infra_cwd() { RUN_CWD="$IW_UNTRACKED/apps"; scn_infra "$IW_UNTRACKED"; RUN_CWD=""; }
scn_gitfail() { FAIL_GIT_MATCH="$1"; scn_infra "$W0"; FAIL_GIT_MATCH=""; }
scn_gf_a() { scn_gitfail 'diff --name-only HEAD'; }
scn_gf_b() { scn_gitfail 'diff --name-status -M HEAD'; }
scn_gf_c() { scn_gitfail 'diff --name-status -M origin/main...HEAD'; }
scn_gf_d() { scn_gitfail 'ls-files --others'; }
scn_midline() { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_MIDLINE"; res; }
scn_zero()   { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_ZERO"; res; }
scn_fb_index() { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_FB_INDEX"; res; }
scn_fb_force() { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_FB_FORCE"; res; }
scn_detail() { start_arm; cap 'MULTI:[contention]   -> pid 5 in /w/CAPACITY_OK measured_runs=0 (running 3s)\n[contention] BANNER CAPACITY_UNKNOWN reason=x measured_runs=?'; wait_small "$LOG_SIB1"; res; }
scn_okbusy() { start_arm; cap "$CAP_OK_BUSY"; wait_small "$LOG_SIB1"; res; }
scn_zeropad() { start_arm; cap '[contention] CAPACITY_OK measured_runs=05 measured_suites=0'; wait_small "$LOG_SIB1"; res; }
scn_twoline() { start_arm; cap 'MULTI:[contention] CAPACITY_OK measured_runs=1\n[contention] CAPACITY_OK measured_runs=0'; wait_small "$LOG_SIB1"; res; }
scn_idlefail() { start_arm; cap "IDLEFAIL:$CAP_OK_IDLE"; wait_small "$LOG_SIB1"; res; }
scn_fb_malformed() { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_FB_EMPTY"; res; }
scn_rr_foo() { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_RR_FOO"; res; }
scn_cnf() { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_CNF"; res; }
scn_fb_two() { start_arm; cap "$CAP_BUSY"; wait_small "$LOG_FB_TWO_A"; res; }
scn_idle_final() { start_arm; cap "$CAP_BUSY" "$CAP_BUSY" "$CAP_BUSY" "$CAP_OK_IDLE"; wait_small "$LOG_SIB1"; res; }
scn_okay() { start_arm; cap '[contention] CAPACITY_OKAY measured_runs=0'; wait_small "$LOG_SIB1"; res; }
scn_stderr() { start_arm; cap "STDERR:$CAP_OK_IDLE"; wait_small "$LOG_SIB1"; res; }
scn_stale_edge() { assert_fixture_dir "$STATE"; clock_at "$BASE"; printf '%s\n' "$(( BASE - 21600 ))" > "$STATE"; cap "$CAP_BUSY"; wait_small "$LOG_SIB1"; res; }
scn_big() { start_arm; cap "$CAP_BUSY"; run_wait "$W0" --log "$LOG_SIB1" --state "$STATE" --budget-s 100000 --interval-s 100000 --probe-timeout-s 5; res; }
scn_ciyml() { scn_infra "$IW_CIYML"; }
scn_near() { scn_infra "$IW_NEAR"; }
scn_ignored() { scn_infra "$IW_IGNORED"; }
real() { "$2"; printf -v "$1" '%s' "$RES"; }
real REAL_DEFER scn_defer; real REAL_LOWTMP scn_lowtmp; real REAL_UNREAD scn_unread
real REAL_MIXU scn_mixu; real REAL_MIXF scn_mixf; real REAL_SEL scn_sel; real REAL_SUB scn_sub
real REAL_FULL scn_full; real REAL_GARB scn_garbage; real REAL_STALE scn_stale; real REAL_SHARED scn_shared
real REAL_BOUND scn_boundary; real REAL_MID scn_midkill; real REAL_WF scn_infra_wf; real REAL_RN scn_infra_rn
real REAL_UN scn_infra_unres; real REAL_EMPTY scn_infra_empty; real REAL_CWD scn_infra_cwd
real REAL_GFA scn_gf_a; real REAL_GFB scn_gf_b; real REAL_GFC scn_gf_c; real REAL_GFD scn_gf_d
real REAL_MIDLINE scn_midline; real REAL_ZERO scn_zero; real REAL_FBI scn_fb_index; real REAL_FBF scn_fb_force
real REAL_DETAIL scn_detail; real REAL_OKBUSY scn_okbusy; real REAL_ZEROPAD scn_zeropad; real REAL_TWOLINE scn_twoline
real REAL_IDLEFAIL scn_idlefail
real REAL_FBM scn_fb_malformed; real REAL_RRFOO scn_rr_foo; real REAL_CNF scn_cnf; real REAL_FB2 scn_fb_two
real REAL_IDLEFINAL scn_idle_final; real REAL_OKAY scn_okay; real REAL_STDERR scn_stderr; real REAL_STALEEDGE scn_stale_edge
real REAL_BIG scn_big; real REAL_CIYML scn_ciyml; real REAL_NEAR scn_near; real REAL_IGNORED scn_ignored
assert_eq "1" "$([[ "$REAL_DEFER" == 42/CI_IS_THE_GATE/3/3/* ]] && echo 1 || echo 0)" "G0 the unmutated control defers as designed (a red control voids every row)"
assert_eq "1" "$([[ "$REAL_WF" == 12/QUEUE_IN_LOCK/3/3/* ]] && echo 1 || echo 0)" "G0b the unmutated control keeps the workflow-file diff out of the deferral"

# 1 classifier shape edited so the real sibling text no longer matches
mutate M1 1 $'already in flight\'' $'already in flightX\'' && mrow M1 "the sibling-refusal log defers" "$REAL_DEFER" scn_defer
# 2 chokepoint returns 42 regardless of infra / --full / unresolved
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
mutate M6a 1 'CONTENDED) CAP=contended ;;' 'CONTENDED) if [[ "$line" =~ measured_runs=0([^0-9]|$) ]]; then CAP=idle; else CAP=contended; fi ;;' && mrow M6a "CONTENDED-with-zero keeps waiting" "$REAL_LOWTMP" scn_lowtmp
mutate M6b 1 'verdict NOT_WAITABLE "$RC_NOT_WAITABLE" capacity-unreadable' 'verdict CI_IS_THE_GATE "$RC_CI" capacity-unreadable' && mrow M6b "never-readable capacity" "$REAL_UNREAD" scn_unread
# 7 REORDER: the epoch is taken from this call and the state is written only AFTER the loop
mutate M7 1 'init_episode  # EPISODE-INIT' 'EPOCH="$CALL_START"' 'infra="$(infra_state)"' 'init_episode; infra="$(infra_state)"' && mrow M7 "kill mid-wait then re-invoke" "$REAL_MID" scn_midkill
# 8 infra literal drift / rename-source forms dropped / cwd-relative git / empty-set guard
mutate M8a 1 '.github/workflows/apply-web-platform-infra.yml' '.github/workflows/apply-web-platform-infra.ymlx' && mrow M8a "the workflow-file row" "$REAL_WF" scn_infra_wf
mutate M8b 2 'diff --name-status -M' 'diff --name-only' && mrow M8b "the rename-source row" "$REAL_RN" scn_infra_rn
mutate M8c 1 'git -C "$top" ls-files' 'git ls-files' && mrow M8c "the untracked-file row from a subdirectory" "$REAL_CWD" scn_infra_cwd
mutate M8d 1 '[[ -n "${names//[[:space:]]/}" ]] || { echo unresolved; return 0; }' ':' && mrow M8d "the empty change set" "$REAL_EMPTY" scn_infra_empty
# 8e..h each failing git read must fail closed
mutate M8e 1 'diff --name-only HEAD 2>/dev/null)" || { echo unresolved; return 0; }' 'diff --name-only HEAD 2>/dev/null)" || true' && mrow M8e "a failing HEAD name-only read" "$REAL_GFA" scn_gf_a
mutate M8f 1 'diff --name-status -M HEAD 2>/dev/null)" || { echo unresolved; return 0; }' 'diff --name-status -M HEAD 2>/dev/null)" || true' && mrow M8f "a failing HEAD name-status read" "$REAL_GFB" scn_gf_b
mutate M8g 1 'diff --name-status -M origin/main...HEAD 2>/dev/null)" || { echo unresolved; return 0; }' 'diff --name-status -M origin/main...HEAD 2>/dev/null)" || true' && mrow M8g "a failing range name-status read" "$REAL_GFC" scn_gf_c
mutate M8h 1 'ls-files --others --exclude-standard 2>/dev/null)" || { echo unresolved; return 0; }' 'ls-files --others --exclude-standard 2>/dev/null)" || true' && mrow M8h "a failing untracked-file read" "$REAL_GFD" scn_gf_d
# 9 the declared-env SUBAGENT refusal becomes waitable (shape widened AND exclusion removed)
mutate M9 1 "'^ERROR: refusing a full-gate run .* [1-9][0-9]* sibling full-gate run\(s\) already in flight'" "'refusing a full-gate run'" 'SOLEUR_SUBAGENT=1 is set' 'SOLEUR_SUBAGENT=1 is setX' && mrow M9 "the SUBAGENT-only row" "$REAL_SUB" scn_sub
# 10 state bounds, classifier anchoring, fallback reasons, capacity anchoring
mutate M10 1 '(( CALL_START - cur <= STALE_S ))' 'true' && mrow M10 "the stale-epoch row" "$REAL_STALE" scn_stale
mutate M11 1 "'^ERROR: refusing a full-gate run" "'ERROR: refusing a full-gate run" && mrow M11 "the mid-line sentence row" "$REAL_MIDLINE" scn_midline
mutate M12 1 '[1-9][0-9]* sibling' '[0-9]* sibling' && mrow M12 "the '0 sibling' row" "$REAL_ZERO" scn_zero
mutate M13 1 'index-missing|enumerate-unavailable)' 'never-a-reason)' && mrow M13 "the broken-index row (reason text)" "$REAL_FBI" scn_fb_index
mutate M14 1 'force-all) force=1 ;;' 'force-all) ;;' && mrow M14 "the force-all row" "$REAL_FBF" scn_fb_force
mutate M15 1 "grep -E '^(\\[contention\\]" "grep -E '(\\[contention\\]" '[[ "$line" =~ ^(\[contention\]' '[[ "$line" =~ (\[contention\]' && mrow M15 "the detail-row row" "$REAL_DETAIL" scn_detail
mutate M16 1 'else CAP=ok; fi ;;' 'else CAP=idle; fi ;;' && mrow M16 "the busy CAPACITY_OK row" "$REAL_OKBUSY" scn_okbusy
mutate M17 1 'measured_runs=0([^0-9]|$) ]]; then CAP=idle; else CAP=ok' 'measured_runs=0 ]]; then CAP=idle; else CAP=ok' && mrow M17 "the measured_runs=05 row" "$REAL_ZEROPAD" scn_zeropad
mutate M18 1 "| head -1)" ")" && mrow M18 "the two-banner-line row" "$REAL_TWOLINE" scn_twoline
mutate M19 1 'out="$(timeout -k 1 "$PROBE_TIMEOUT_S" bash "$top/scripts/test-all.sh" --capacity 2>&1)" || return 0' 'out="$(timeout -k 1 "$PROBE_TIMEOUT_S" bash "$top/scripts/test-all.sh" --capacity 2>&1)"' && mrow M19 "the idle-line-then-nonzero-exit row" "$REAL_IDLEFAIL" scn_idlefail
# 11 strict fallback parse, runner-refused anchoring, toolchain alternation, every fallback line judged
mutate M20 1 'r="${BASH_REMATCH[1]}"; else r=""; fi' 'r="${BASH_REMATCH[1]}"; else r="runner-changed"; fi' && mrow M20 "a malformed AFFECTED_FALLBACK line" "$REAL_FBM" scn_fb_malformed
mutate M21 1 "reason=runner-refused([[:space:]]|\$)')" "reason=runner-refused')" && mrow M21 "reason=runner-refused-foo" "$REAL_RRFOO" scn_rr_foo
mutate M22 1 'mise ERROR|command not found' 'mise ERROR' && mrow M22 "the 'command not found' toolchain fault" "$REAL_CNF" scn_cnf
mutate M23 1 "done < <(grep -F 'AFFECTED_FALLBACK' <<<\"\$body\")" "done < <(grep -F 'AFFECTED_FALLBACK' <<<\"\$body\" | head -1)" && mrow M23 "two fallback lines (only the first judged)" "$REAL_FB2" scn_fb_two
# 12 idle on the final poll, token boundary, stderr, stale boundary, six-digit budget
mutate M24 1 'idle) verdict RETRY "$RC_RETRY" capacity-idle ;;' 'idle) if (( elapsed >= BUDGET_S )); then BUDGET_DONE=1; break; fi; verdict RETRY "$RC_RETRY" capacity-idle ;;' && mrow M24 "idle on the final poll" "$REAL_IDLEFINAL" scn_idle_final
mutate M25 1 "CAPACITY_(OK|CONTENDED|UNKNOWN)([[:space:]]|\$)'" "CAPACITY_(OK|CONTENDED|UNKNOWN)'" '|CONTENDED|UNKNOWN)([[:space:]]|$) ]] || return 0' '|CONTENDED|UNKNOWN) ]] || return 0' && mrow M25 "CAPACITY_OKAY" "$REAL_OKAY" scn_okay
mutate M26 1 '--capacity 2>&1)"' '--capacity)"' && mrow M26 "a stderr-only capacity banner" "$REAL_STDERR" scn_stderr
mutate M27 1 '(( CALL_START - cur <= STALE_S ))' '(( CALL_START - cur < STALE_S ))' && mrow M27 "the stale-epoch boundary" "$REAL_STALEEDGE" scn_stale_edge
mutate M28 1 '{0,5}' '{0,4}' && mrow M28 "a six-digit budget" "$REAL_BIG" scn_big
# 13 the infra clean side: widened triggers and --exclude-standard
mutate M29 1 "'.github/workflows/apply-web-platform-infra.yml'" "'.github/workflows/'" && mrow M29 "the ci.yml (clean) row" "$REAL_CIYML" scn_ciyml
mutate M30 1 "'apps/web-platform/infra/'" "'web-platform/infra/'" && mrow M30 "the web-platform/infra/ near miss" "$REAL_NEAR" scn_near
mutate M31 1 'ls-files --others --exclude-standard' 'ls-files --others' && mrow M31 "the gitignored-file row" "$REAL_IGNORED" scn_ignored
restore

# Recipe mutants (of a COPY of the reference): each reverts one thing the glue must do.
recipe_mutant() { # <id> <old> <new> [<old2> <new2>] ; sets RECIPE_UNDER_TEST to the mutated recipe
  local id="$1" old="$2" new="$3" old2="${4:-}" new2="${5:-}"
  local m="$MROOT/ref-$id.md"
  assert_fixture_dir "$m"
  cp "$REAL_REF_MD" "$m"
  if ! OLD="$old" NEW="$new" OLD2="$old2" NEW2="$new2" python3 -c '
import os, sys
p = sys.argv[1]; s = open(p).read()
for o, n in ((os.environ["OLD"], os.environ["NEW"]), (os.environ["OLD2"], os.environ["NEW2"])):
    if not o: continue
    if s.count(o) != 1: sys.exit(1)
    s = s.replace(o, n)
open(p, "w").write(s)' "$m"; then
    assert_eq "landed" "did-not-land" "G $id: the recipe mutation lands exactly once"; return 1
  fi
  RECIPE_UNDER_TEST="$(recipe_block "$m")"
  return 0
}
recipe_scn false 4 42; REAL_R1="$RES"
recipe_scn false 4 10 42; REAL_R2="$RES"
recipe_scn false 4 11; REAL_R3="$RES"
recipe_scn true 4 42; REAL_R7="$RES"
recipe_scn false 4 10 10 10 10 10; REAL_R6="$RES"
mrow_recipe() { # <id> <label> <real> <fb> <aff-rc> <codes...>
  local id="$1" label="$2" want="$3"; shift 3
  recipe_scn "$@"
  assert_eq "killed" "$(verdict_of "$RES" "$want")" "G $id: $label goes RED against the mutant (got $RES, real $want)"
  restore
}
recipe_mutant R1 '; wait_rc=$?' '; wait_rc=42' && mrow_recipe R1 "wait status 11 must stop" "$REAL_R3" false 4 11
recipe_mutant R2 'again=1 ;;' 'again=0 ;;' && mrow_recipe R2 "wait 10 must relaunch" "$REAL_R2" false 4 10 42
recipe_mutant R3 '${FULL:+--full}; wait_rc=$?' '; wait_rc=$?' && mrow_recipe R3 "--full must reach the wait script" "$REAL_R7" true 4 42
recipe_mutant R4 '= 4 ] || {' '= 0 ] || {' && mrow_recipe R4 "only a refused battery (rc 4) calls the wait script" "$REAL_R1" false 4 42
recipe_mutant R5 '"$FULL" >/dev/null' '"" >/dev/null' && mrow_recipe R5 "FULL_BATTERY must launch the battery with --full" "$REAL_R7" true 4 42
recipe_mutant R6 '[ "$relaunches" -le 3 ] ||' '[ "$relaunches" -le 99 ] ||' && mrow_recipe R6 "relaunches are capped" "$REAL_R6" false 4 10 10 10 10 10
# The recipe's state-file creation statement, assembled so this file holds no literal redirect to it.
STATE_INIT="$(printf 'STATE="$d/state"; : %s "$STATE"' '>')"
recipe_mutant R7 'FULL=""; [ "${FULL_BATTERY:-}" = true ] && FULL=--full' 'FULL=""' && mrow_recipe R7 "FULL_BATTERY must map to --full" "$REAL_R7" true 4 42
recipe_mutant R8 '--log "$LOG" --state' '--log "$RCF" --state' && mrow_recipe R8 "the wait script must get the battery log" "$REAL_R1" false 4 42
recipe_mutant R9 '--state "$STATE" ${FULL' '--state "$d/other" ${FULL' && mrow_recipe R9 "the wait script must get the episode state file" "$REAL_R1" false 4 42
recipe_mutant R10 "$STATE_INIT" 'STATE="$d/state"' && mrow_recipe R10 "the state file must exist before the wait script runs" "$REAL_R1" false 4 42
recipe_mutant R11 'launch() { rm -f "$RCF"; ' 'launch() { ' && mrow_recipe R11 "a relaunch must clear the previous rc file" "$REAL_R2" false 4 10 42
recipe_mutant R12 '> "$2" 2>&1; echo $? > "$3"' '> /dev/null 2>&1; echo $? > "$3"' && mrow_recipe R12 "the battery output must reach the log" "$REAL_R1" false 4 42
recipe_mutant R13 "$STATE_INIT" 'STATE="$d/state"' 'launch() { rm -f "$RCF"; ' "launch() { : $(printf '>') \"\$STATE\"; rm -f \"\$RCF\"; " && mrow_recipe R13 "the state (budget) must survive a relaunch" "$REAL_R2" false 4 10 42
restore

# --- H. harness -------------------------------------------------------------------------------
# H1: print_results with a floor above the pass count must exit non-zero. The subshell's status is
# read OUTSIDE it: print_results exits, so an `echo $?` inside would never run.
( PASS=3; FAIL=0; print_results 99 ) >/dev/null 2>&1
H1_RC=$?
assert_eq "1" "$([[ "$H1_RC" -ne 0 ]] && echo 1 || echo 0)" "H1 print_results with a floor above the pass count exits non-zero (rc $H1_RC)"
( PASS=99; FAIL=0; print_results 99 ) >/dev/null 2>&1
H1_RC_OK=$?
assert_eq "0" "$H1_RC_OK" "H1c print_results at its floor exits zero (the control that H1 can say yes)"
# H1b: the floor literal at the end of THIS file equals the number of assertions that run, so a
# deleted row lowers the count below the floor and reds the run, and a new row forces a ratchet.
H1_FLOOR="$(tail -3 "${BASH_SOURCE[0]}" | sed -n 's/^print_results \([0-9][0-9]*\)$/\1/p')"
assert_eq "$(( PASS + FAIL + 1 ))" "$H1_FLOOR" "H1b the numeric PASS floor equals the exact assertion count (ratchet it with every added row)"

# The floor counts the instrument self-test's two rows plus every row above. Set EQUAL to the
# current count, not below it: slack is budget for a silently deleted row.
print_results 215
