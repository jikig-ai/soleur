#!/usr/bin/env bash
# test-all-pr-battery-gate — ADR-262 Guard 1: the pull_request gate over the five self-test
# mutation batteries (#9323).
#
# PROPERTY. On a `pull_request` CI run a gated battery is declined if and only if the PR's net diff
# (rename sources included) contains none of its subject paths and none of the gate-machinery paths.
# Every other arm — push, merge_group, workflow_dispatch, schedule, an unset event, CI unset,
# --full, SOLEUR_TEST_FORCE_ALL=1, an undeterminable diff — runs it.
#
# HOW IT TESTS. It never touches the live runner (sibling shards are executing it). It copies
# scripts/test-all.sh and scripts/lib into $TMP, replaces run_suite with a recorder that writes
# `RECORDED_SUITE:<label>`, neuters the advisory lock, and drives the copy from a throwaway git
# repository whose `origin/main...HEAD` diff IS the arm's input. Every RUN assertion requires the
# positive recorded line exactly once (an absent `[skip]` also describes an rc=4 or an empty
# selection) and every DECLINE assertion requires the printed `[skip] <label> (relevance)` line.
# Mutants are applied to COPIES with a block-scoped substitution that asserts exactly one landing
# (the five call sites are near-identical, so an unscoped s/// lands on the wrong site), checked with
# `bash -n`, and graded CAUGHT only when the arm named for them fails — a syntax-broken mutant reds
# everything and must not read as caught. The instrument control runs first: the pristine copy must
# go green on every arm before any mutant is read.
#
# SEAM. PR_BATTERY_GATE_RUNNER_SRC points the suite at another runner (RED check against main's).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"   # a direct run inherits /tmp (shared 4 GiB tmpfs); the runner defaults here

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_RUNNER="${PR_BATTERY_GATE_RUNNER_SRC:-$REPO_ROOT/scripts/test-all.sh}"
SRC_LIB="$REPO_ROOT/scripts/lib"
TMP="$(mktemp -d "$TMPDIR/pr-battery-gate.XXXXXXXX")" || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
START_S=$SECONDS

passes=0; fails=0; asserted=0
FAILS_LOG="$TMP/fails.log"; : > "$FAILS_LOG"   # append-only: the final verdict reads THIS, not only the counters
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf '  FAIL: %s\n' "$1"; printf '%s\n' "$1" >> "$FAILS_LOG"; }
harness_die() { printf '[FATAL] %s\n' "$1" >&2; exit 2; }
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

# H1 (negative control for the harness itself): PR_GATE_TEST_SABOTAGE=pass makes pass() a no-op. The
# instrument self-test below must then refuse, so a suite whose verdict helpers do nothing cannot
# exit 0 having asserted nothing.
if [[ "${PR_GATE_TEST_SABOTAGE:-}" == "pass" ]]; then pass() { :; }; fi
if [[ "${PR_GATE_TEST_SABOTAGE:-}" == "fail" ]]; then fail() { :; }; fi

# INSTRUMENT SELF-TEST — drives both helpers once and requires every observable to move.
_st_p=$passes; _st_f=$fails
pass "instrument self-test (pass)" >/dev/null
fail "instrument self-test (fail)" >/dev/null
if (( passes != _st_p + 1 || fails != _st_f + 1 )); then
  printf '[FATAL] instrument self-test: pass()/fail() did not move their counters (passes %d->%d, fails %d->%d)\n' \
    "$_st_p" "$passes" "$_st_f" "$fails" >&2
  exit 1
fi
passes=$_st_p; fails=$_st_f; asserted=0; : > "$FAILS_LOG"

command -v python3 >/dev/null 2>&1 || harness_die "python3 is required (mutation patcher)"
[[ -f "$SRC_RUNNER" ]] || harness_die "runner source not found: $SRC_RUNNER"
[[ -d "$SRC_LIB" ]] || harness_die "lib dir not found: $SRC_LIB"
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$SRC_LIB/test-relevance-paths.sh"   # PR_GATE_MACHINERY_PATHS: the machinery arms derive from it

# --- labels and arrays ------------------------------------------------------------------------
L_REG="tests/scripts/registry-gate-mutation-battery"
L_CF="scripts/cf-tunnel-liveness-gate-mutations"
L_LA="scripts/lint-orphan-test-suites-mutations-a"
L_LB="scripts/lint-orphan-test-suites-mutations-b"
L_TAG="scripts/battery-tag-authorship-mutations"
L_TAA="scripts/test-all-affected"
ALL_LABELS=("$L_REG" "$L_CF" "$L_LA" "$L_LB" "$L_TAG" "$L_TAA")
ARRAYS=(REGISTRY_BATTERY_PATHS CF_TUNNEL_BATTERY_PATHS LINT_ORPHAN_BATTERY_PATHS TAG_AUTHORSHIP_BATTERY_PATHS TEST_ALL_AFFECTED_BATTERY_PATHS)

# one file that belongs to exactly one battery's array (its own battery file)
own_file() {
  case "$1" in
    REGISTRY_BATTERY_PATHS) echo "tests/scripts/test-registry-gate-mutation-battery.sh" ;;
    CF_TUNNEL_BATTERY_PATHS) echo "scripts/cf-tunnel-liveness-gate-mutations.test.sh" ;;
    LINT_ORPHAN_BATTERY_PATHS) echo "scripts/lint-orphan-test-suites.test.sh" ;;
    TAG_AUTHORSHIP_BATTERY_PATHS) echo "scripts/battery-tag-authorship-mutations.test.sh" ;;
    TEST_ALL_AFFECTED_BATTERY_PATHS) echo "scripts/test-all-affected.test.sh" ;;
  esac
}

# --- sandbox runner builder -------------------------------------------------------------------
# build_runner <dir> [recorder=1] — copies the runner + lib into <dir>/scripts, patches the copy.
build_runner() {
  local dir="$1" recorder="${2:-1}"
  assert_fixture_dir "$dir"
  mkdir -p "$dir/scripts" || return 1
  cp "$SRC_RUNNER" "$dir/scripts/test-all.sh" || return 1
  cp -R "$SRC_LIB" "$dir/scripts/lib" || return 1
  # The runner sources the repo-write-boundary lib FAIL-CLOSED; a relocated copy without it exits 2
  # before any arm runs. The `cp -R` above carries it, and this line states the dependency where the
  # relocation-without-the-lib scan in scripts/lib/repo-write-boundary.test.sh can read it.
  cp "$SRC_LIB/repo-write-boundary.sh" "$dir/scripts/lib/" || return 1
  cp "$REPO_ROOT"/scripts/suite-shard-legs*.tsv "$dir/scripts/" || return 1
  python3 - "$dir/scripts/test-all.sh" "$recorder" <<'PY' || return 1
import re, sys
path, recorder = sys.argv[1], sys.argv[2]
s = open(path).read()
def sub_once(hay, old, new, what):
    assert hay.count(old) == 1, f"expected exactly one {what}, found {hay.count(old)}"
    return hay.replace(old, new)
# neuter the advisory lock and the contention preamble: a sibling-run refusal must not depend on
# whatever else is executing on this machine
s = sub_once(s, 'tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 'tc_acquire call')
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
if recorder == "1":
    m = re.search(r'^run_suite\(\) \{.*?^\}', s, re.S | re.M)
    assert m, "could not locate run_suite()"
    # the recorder KEEPS the suites increment: the denominator is part of what is under test
    s = s[:m.start()] + 'run_suite() { suites=$((suites + 1)); echo "RECORDED_SUITE:$1" >> "$SANDBOX_RECORD"; }' + s[m.end():]
open(path, "w").write(s)
PY
}

# mutate <runner-dir> <python-body> — python body sees `s` (runner text) and `lib` (relevance lib text)
# and the helpers sub_once / sub_in_func; it must assert its own landing.
mutate() {
  local dir="$1" body="$2"
  python3 - "$dir/scripts/test-all.sh" "$dir/scripts/lib/test-relevance-paths.sh" "$body" <<'PY'
import re, sys
rp, lp, body = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(rp).read(); lib = open(lp).read()
def sub_once(hay, old, new, what="pattern"):
    assert hay.count(old) == 1, f"mutation did not land exactly once ({what}): found {hay.count(old)}"
    return hay.replace(old, new)
def sub_in_func(hay, fn, old, new):
    m = re.search(r'^' + re.escape(fn) + r'\(\) \{.*?^\}', hay, re.S | re.M)
    assert m, f"function {fn} not found"
    seg = m.group(0)
    assert seg.count(old) == 1, f"mutation did not land exactly once in {fn}: found {seg.count(old)}"
    return hay[:m.start()] + seg.replace(old, new) + hay[m.end():]
exec(body)
open(rp, "w").write(s); open(lp, "w").write(lib)
PY
}

# --- fixture repo -----------------------------------------------------------------------------
GIT_SCRUB=(-u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY
           -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_TEMPLATE_DIR -u GIT_EXEC_PATH)
gitq() { env "${GIT_SCRUB[@]}" git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

BASE="$TMP/base"
build_base() {
  assert_fixture_dir "$BASE"
  mkdir -p "$BASE" || return 1
  (
    cd "$BASE" || exit 1
    gitq init -q -b main . || exit 1
    local a p
    for a in "${ARRAYS[@]}"; do
      # shellcheck disable=SC1087,SC2154  # the array is named by $a; eval is the bash-3.2 indirection (`el` is assigned by it)
      eval "local el=( \"\${${a}[@]}\" )"
      # shellcheck disable=SC2154  # `el` is assigned by the eval above
      for p in "${el[@]}"; do
        case "$p" in
          */*.*|*.sh|*.yml|*.tsv|*.txt|*.md) mkdir -p "$BASE/$(dirname "$p")" && printf 'base\n' > "$BASE/$p" ;;
          *) mkdir -p "$BASE/$p" && printf 'base\n' > "$BASE/$p/placeholder" ;;
        esac
      done
    done
    mkdir -p "$BASE/knowledge-base" "$BASE/docs/scripts"
    printf 'base\n' > "$BASE/README.md"
    printf 'base\n' > "$BASE/knowledge-base/note.md"
    printf 'base\n' > "$BASE/docs/scripts/registry-restore-from-ghcr.sh.md"
    gitq add -A && gitq commit -qm base && gitq update-ref refs/remotes/origin/main HEAD
  ) || return 1
}

# fx_new <name> — a private copy of the base repo, on a `pr` branch
fx_new() {
  local fx="$TMP/fx-$1"
  cp -R "$BASE" "$fx" || return 1
  (cd "$fx" && gitq checkout -q -b pr) || return 1
  printf '%s' "$fx"
}
# fx_apply <fx> <op> <path> — modify | rename | delete | rewrite-rename | stacked
fx_apply() {
  local fx="$1" op="$2" p="$3"
  assert_fixture_dir "$fx"
  (
    cd "$fx" || exit 1
    case "$op" in
      modify) printf 'changed\n' >> "$fx/$p" ;;
      delete) gitq rm -q "$p" ;;
      rename) mkdir -p "$fx/$(dirname "$p")" && gitq mv "$p" "${p%.*}.moved.${p##*.}" ;;
      # below the similarity threshold: rename AND replace the whole content, so git sees delete+add
      rewrite-rename) gitq mv "$p" "${p%.*}.moved.${p##*.}" && printf 'entirely different content %s\n' "$RANDOM$RANDOM" > "$fx/${p%.*}.moved.${p##*.}" ;;
    esac
    gitq add -A && gitq commit -qm "arm: $op $p"
  )
}

# --- arm runner --------------------------------------------------------------------------------
# SCRUB: every inherited variable that changes runner control flow is removed, then each arm sets
# exactly what it needs. `env -u` takes no globs, so the list is computed.
SCRUB=()
while IFS= read -r _v; do SCRUB+=(-u "$_v"); done < <(env | sed -n 's/=.*//p' \
  | grep -E '^(CI|GITHUB_[A-Z_]*|SOLEUR_[A-Z0-9_]*|TEST_[A-Z0-9_]*|SCRIPTS_SHARD|SANDBOX_[A-Z0-9_]*|TC_[A-Z0-9_]*)$' || true)

# run_arm <id> <runner-dir> <fx> <env-assignments...> [-- <runner args...>]
# Writes $TMP/arm-<id>.{out,rec,rc}. Never aborts the suite.
run_arm() {
  local id="$1" rdir="$2" fx="$3"; shift 3
  local -a envs=() args=()
  while (( $# )); do
    if [[ "$1" == "--" ]]; then shift; args=("$@"); break; fi
    envs+=("$1"); shift
  done
  : > "$TMP/arm-$id.rec"
  local -a pathenv=()
  if [[ -d "$TMP/shim-$id" ]]; then pathenv=("PATH=$TMP/shim-$id:$PATH"); fi
  (cd "$fx" && env "${SCRUB[@]}" "${GIT_SCRUB[@]}" TEST_GROUP=all SOLEUR_DISABLE_SESSION_STATE=1 \
      SANDBOX_RECORD="$TMP/arm-$id.rec" TEST_TIMING_LOG="$TMP/arm-$id.timing" \
      ${pathenv[@]+"${pathenv[@]}"} ${envs[@]+"${envs[@]}"} \
      timeout 120 bash "$rdir/scripts/test-all.sh" ${args[@]+"${args[@]}"} > "$TMP/arm-$id.out" 2>&1)
  echo "$?" > "$TMP/arm-$id.rc"
}

RECORD_FLOOR=150   # recorded registrations on a TEST_GROUP=all run (measured 274)
UNIVERSE=()        # the labels the arm's group registers; set by grade_arms
# check_set <id> <expected-run-labels...> — 0 when the arm's run/decline sets match exactly;
# 1 when they do not (a VERDICT: the gate decided differently from the contract);
# 2 when the arm produced no verdict at all (non-zero rc, no terminal marker, too few registrations).
# A mutant is credited as CAUGHT only on 1: a runner that merely CRASHED reds everything and says nothing.
check_set() {
  local id="$1"; shift
  local floor="$RECORD_FLOOR"; (( ${#UNIVERSE[@]} < ${#ALL_LABELS[@]} )) && floor=20
  local out="$TMP/arm-$id.out" rec="$TMP/arm-$id.rec" l want n
  [[ "$(cat "$TMP/arm-$id.rc" 2>/dev/null)" == "0" ]] || { ARM_WHY="rc=$(cat "$TMP/arm-$id.rc" 2>/dev/null)"; return 2; }
  grep -qE '^=== [0-9]+/[0-9]+ suites passed ===$' "$out" || { ARM_WHY="no terminal marker"; return 2; }
  n=$(grep -c '^RECORDED_SUITE:' "$rec") || n=0
  (( n >= floor )) || { ARM_WHY="only $n suites recorded (floor $floor)"; return 2; }
  for l in "${UNIVERSE[@]}"; do
    want=0; local e; for e in "$@"; do [[ "$e" == "$l" ]] && want=1; done
    local c; c=$(grep -cxF "RECORDED_SUITE:$l" "$rec") || c=0
    if (( want == 1 )); then
      (( c == 1 )) || { ARM_WHY="expected $l to RUN once, recorded $c"; return 1; }
    else
      (( c == 0 )) || { ARM_WHY="expected $l to DECLINE, it ran"; return 1; }
      grep -qxF "[skip] $l (relevance)" "$out" || { ARM_WHY="expected a '[skip] $l (relevance)' line"; return 1; }
    fi
  done
  return 0
}

# --- arm table ---------------------------------------------------------------------------------
# Row layout (US-separated): id event ci mods expected [extra-env] [runner-args]
ARM_IDS=()
ARM_SPEC_FILE="$TMP/arms.tsv"; : > "$ARM_SPEC_FILE"
add_arm() { ARM_IDS+=("$1"); printf '%s\n' "$*" | tr ' ' '\037' >> "$ARM_SPEC_FILE"; }
# add_arm <id> <event> <ci> <mods> <expected> [extra-env] [runner-args]   (event "-" = unset, ci "-" = unset)
expect_labels() { case "$1" in ALL) printf '%s\n' "${ALL_LABELS[@]}" ;; NONE) ;; *) printf '%s\n' "$1" | tr '|' '\n' ;; esac; }

PR=pull_request
add_arm docs-only         "$PR" 1 "modify:knowledge-base/note.md" NONE
add_arm docs-readme       "$PR" 1 "modify:README.md" NONE
add_arm registry-only     "$PR" 1 "modify:scripts/registry-pull-path-health.sh" "$L_REG"
add_arm zot-companion     "$PR" 1 "modify:scripts/zot-mirror-diagnosis.sh" "$L_REG"
add_arm substring-overmatch "$PR" 1 "modify:docs/scripts/registry-restore-from-ghcr.sh.md" "$L_REG"
# One arm per member of PR_GATE_MACHINERY_PATHS, derived from the lib rather than retyped here, so a
# sixth member is exercised by existing and one removed from the lib reds its own arm (see the
# per-member mutants below). The lib's own file is the one machinery path every array names itself.
machinery_arm() { printf 'machinery-%s' "${1//\//_}"; }
for _m in "${PR_GATE_MACHINERY_PATHS[@]}" "scripts/lib/test-relevance-paths.sh"; do
  add_arm "$(machinery_arm "$_m")" "$PR" 1 "modify:$_m" ALL
done
MACH_RUNNER_ARM="$(machinery_arm scripts/test-all.sh)"
add_arm own-registry      "$PR" 1 "modify:$(own_file REGISTRY_BATTERY_PATHS)" "$L_REG"
add_arm own-cf            "$PR" 1 "modify:$(own_file CF_TUNNEL_BATTERY_PATHS)" "$L_CF"
add_arm own-lint          "$PR" 1 "modify:$(own_file LINT_ORPHAN_BATTERY_PATHS)" "$L_LA|$L_LB"
add_arm own-tag           "$PR" 1 "modify:$(own_file TAG_AUTHORSHIP_BATTERY_PATHS)" "$L_TAG"
add_arm own-taa           "$PR" 1 "modify:$(own_file TEST_ALL_AFFECTED_BATTERY_PATHS)" "$L_TAA"
add_arm ev-push           push 1 "modify:knowledge-base/note.md" ALL
add_arm ev-merge-group    merge_group 1 "modify:knowledge-base/note.md" ALL
add_arm ev-dispatch       workflow_dispatch 1 "modify:knowledge-base/note.md" ALL
add_arm ev-schedule       schedule 1 "modify:knowledge-base/note.md" ALL
add_arm ev-unset          - 1 "modify:knowledge-base/note.md" ALL
# the PR arm keys on the EXACT event name: near-miss names are not pull_request
add_arm ev-pr-target      pull_request_target 1 "modify:knowledge-base/note.md" ALL
add_arm ev-pr-review      pull_request_review 1 "modify:knowledge-base/note.md" ALL
# CI unset = a local run: the default local mode is the affected gate, which REFUSES (rc=4) a docs-only
# diff that selects nothing, so these arms name an explicit group (TEST_GROUP=<g> bypasses the affected
# axis) and a diff that touches one light battery's own file. The light group registers four of the six.
add_arm local-pr-event    "$PR" - "modify:scripts/test-all-affected.test.sh" "$L_TAA" "TEST_GROUP=scripts"
add_arm local-no-event    - - "modify:scripts/test-all-affected.test.sh" "$L_TAA" "TEST_GROUP=scripts"
add_arm force-all         "$PR" 1 "modify:knowledge-base/note.md" ALL "SOLEUR_TEST_FORCE_ALL=1"
add_arm full-flag         "$PR" 1 "modify:knowledge-base/note.md" ALL "" "--full"
add_arm rename-only       "$PR" 1 "rename:scripts/registry-pull-path-health.sh" "$L_REG"
add_arm delete-only       "$PR" 1 "delete:scripts/registry-pull-path-health.sh" "$L_REG"
add_arm rename-rewrite    "$PR" 1 "rewrite-rename:scripts/registry-pull-path-health.sh" "$L_REG"
add_arm no-origin-ref     "$PR" 1 "modify:knowledge-base/note.md;noref" ALL
add_arm head-diff-fails   "$PR" 1 "modify:knowledge-base/note.md;headfail" ALL
add_arm stacked-pr        "$PR" 1 "stacked:scripts/registry-pull-path-health.sh;modify:knowledge-base/note.md" "$L_REG"

# Arms that need a fixture shape the table cannot express are prepared by this hook.
prepare_arm() {  # <id> <fx> <mods>
  local id="$1" fx="$2" mods="$3" m op p
  local IFS=';'; local -a ml; read -r -a ml <<<"$mods"; IFS=$' \t\n'
  for m in "${ml[@]}"; do
    op="${m%%:*}"; p="${m#*:}"
    case "$op" in
      noref) (cd "$fx" && gitq update-ref -d refs/remotes/origin/main) ;;
      headfail)
        # a git shim that fails ONLY `diff --name-only HEAD` — the one read that sees uncommitted work
        mkdir -p "$TMP/shim-$id"
        local real; real="$(command -v git)"
        printf '#!/bin/sh\ncase "$*" in *"diff --name-only HEAD") exit 128 ;; esac\nexec "%s" "$@"\n' "$real" > "$TMP/shim-$id/git"
        chmod +x "$TMP/shim-$id/git" ;;
      stacked)
        # origin/main stays BEHIND: the PR branch carries an earlier commit that touches the SUT,
        # then a docs-only one — `origin/main...HEAD` over-includes the earlier work (the safe direction)
        fx_apply "$fx" modify "$p" ;;
      modify|delete|rename|rewrite-rename) fx_apply "$fx" "$op" "$p" ;;
      *) harness_die "unknown arm mod '$m' for $id" ;;
    esac
  done
}

# run_arms <runner-dir> <tag> [arm-id...] — runs every arm (or only the named ones), 8 at a time in parallel
run_arms() {
  local rdir="$1" tag="$2"; shift 2
  local -a only=("$@") id n=0
  while IFS=$'\037' read -r id event ci mods expected extra args; do
    if (( ${#only[@]} )); then local keep=0 o; for o in "${only[@]}"; do [[ "$o" == "$id" ]] && keep=1; done; (( keep )) || continue; fi
    local aid="$tag-$id" fx
    fx="$(fx_new "$aid")" || harness_die "fixture build failed for $aid"
    prepare_arm "$aid" "$fx" "$mods"
    local -a e=()
    [[ "$ci" != "-" ]] && e+=("CI=$ci")
    [[ "$event" != "-" ]] && e+=("GITHUB_EVENT_NAME=$event")
    [[ -n "$extra" ]] && e+=("$extra")
    # </dev/null: a backgrounded arm must not inherit the loop's stdin (the arm table)
    if [[ -n "$args" ]]; then run_arm "$aid" "$rdir" "$fx" ${e[@]+"${e[@]}"} -- "$args" </dev/null &
    else run_arm "$aid" "$rdir" "$fx" ${e[@]+"${e[@]}"} </dev/null &
    fi
    n=$((n + 1)); (( n % 8 == 0 )) && wait
  done < "$ARM_SPEC_FILE"
  wait
}

# grade_arms <tag> [id...] — fills GRADE_FAILED (verdict mismatches) and GRADE_INFRA (arms that produced
# no verdict); returns the total count of arms that did not match the contract
grade_arms() {
  local tag="$1"; shift
  local -a only=("$@"); local id event ci mods expected extra args bad=0 crc
  GRADE_FAILED=(); GRADE_INFRA=()
  while IFS=$'\037' read -r id event ci mods expected extra args; do
    if (( ${#only[@]} )); then local keep=0 o; for o in "${only[@]}"; do [[ "$o" == "$id" ]] && keep=1; done; (( keep )) || continue; fi
    ARM_WHY=""
    case "$extra" in
      TEST_GROUP=scripts) UNIVERSE=("$L_LA" "$L_LB" "$L_CF" "$L_TAA") ;;
      TEST_GROUP=scripts-heavy) UNIVERSE=("$L_REG" "$L_TAG") ;;
      *) UNIVERSE=("${ALL_LABELS[@]}") ;;
    esac
    # shellcheck disable=SC2046
    check_set "$tag-$id" $(expect_labels "$expected" | tr '\n' ' '); crc=$?
    if (( crc == 1 )); then GRADE_FAILED+=("$id"); bad=$((bad + 1)); GRADE_WHY["$id"]="$ARM_WHY"
    elif (( crc == 2 )); then GRADE_INFRA+=("$id"); bad=$((bad + 1)); GRADE_WHY["$id"]="$ARM_WHY"
    fi
  done < "$ARM_SPEC_FILE"
  return "$bad"
}
declare -A GRADE_WHY   # associative array: bash >= 4 (this suite runs on the CI runners, not on macOS bash 3.2)

# =================================================================================================
# 0. build the base fixture and the pristine runner, time the control, then read it.
# =================================================================================================
build_base || harness_die "could not build the base fixture repo"
PRISTINE="$TMP/pristine"
build_runner "$PRISTINE" 1 || harness_die "could not build the pristine runner copy"
bash -n "$PRISTINE/scripts/test-all.sh" || harness_die "pristine runner copy does not parse"

CONTROL_START=$SECONDS
run_arms "$PRISTINE" ctl
grade_arms ctl; ctl_bad=$?
CONTROL_S=$((SECONDS - CONTROL_START))
if (( ctl_bad == 0 )); then
  pass "instrument control: the pristine runner is green on all ${#ARM_IDS[@]} arms (${CONTROL_S}s)"
  # one assertion per arm, so the executed-assertion floor counts BODIES (an arm that stopped being
  # read cannot hide behind the single control line above)
  for id in "${ARM_IDS[@]}"; do pass "arm $id: run/decline set matches the contract"; done
else
  for id in ${GRADE_FAILED[@]+"${GRADE_FAILED[@]}"} ${GRADE_INFRA[@]+"${GRADE_INFRA[@]}"}; do fail "instrument control: arm '$id' is RED on the pristine runner — ${GRADE_WHY[$id]:-?}"; done
  printf '[FATAL] the control is red, so no mutant below can be read. Stopping.\n'
  printf 'verdict: %d passed, %d failed\n' "$passes" "$fails"
  exit 1
fi
# Wall-clock is printed, never asserted: ~30 arms run 8 at a time on a shard leg that shares its runner
# with sibling jobs, so a ceiling here would red on load alone (measured 18 s idle, ~100 s loaded).
printf 'control: %d arms in %ds\n' "${#ARM_IDS[@]}" "$CONTROL_S"

# a deliberate decline must say so (and name the lever) on a PR run; a force-all run must not claim declines
if grep -q 'These declines are deliberate' "$TMP/arm-ctl-docs-only.out"; then pass "docs-only PR run: the epilogue says the declines are deliberate and names the lever"
else fail "docs-only PR run: the epilogue does not explain the declines"; fi
if grep -q '\[skip\].*(relevance)' "$TMP/arm-ctl-force-all.out"; then fail "force-all run printed a relevance [skip] line"; else pass "force-all run declines no battery"; fi

# the canary must be SILENT on every pristine arm (it fires only on a regression)
canary_hits=0
for f in "$TMP"/arm-ctl-*.out; do if grep -q 'PR_GATE_CANARY_FAILED' "$f"; then canary_hits=$((canary_hits + 1)); fi; done
if (( canary_hits == 0 )); then pass "the canary is silent on every pristine arm"; else fail "PR_GATE_CANARY_FAILED printed on $canary_hits pristine arm(s)"; fi

# =================================================================================================
# 1. dispatch self-check (row 8): the --pr-gated site set is DERIVED from the runner and compared
#    by SET EQUALITY with the expected arrays; "0 checked" is not green.
# =================================================================================================
derive_sites() {
  sed 's/[[:space:]]*#.*$//' "$1" | grep -oE '_diff_touches --pr-gated +"\$\{[A-Z0-9_]+' | sed 's/.*{//' | LC_ALL=C sort
}
want_sites="$(printf '%s\n' "${ARRAYS[@]}" | LC_ALL=C sort)"
got_sites="$(derive_sites "$PRISTINE/scripts/test-all.sh")"
if [[ -n "$got_sites" && "$got_sites" == "$want_sites" ]]; then
  pass "dispatch: the --pr-gated call sites in the runner are exactly the five expected arrays"
else
  fail "dispatch: --pr-gated sites differ. expected: $(echo $want_sites) / derived: $(echo $got_sites)"
fi
# the runner must carry a skip_suite for each of the six labels (a decline is a counted verdict)
for l in "${ALL_LABELS[@]}"; do
  if grep -qF "skip_suite \"$l\" \"relevance\"" "$PRISTINE/scripts/test-all.sh"; then pass "skip_suite else-arm present for $l"; else fail "no skip_suite arm for $l"; fi
done

# =================================================================================================
# 2. enumerate is never gated (row 10): the stream under CI=1 + pull_request is byte-identical to
#    the event-unset stream on a docs-only fixture.
# =================================================================================================
ENUM="$TMP/enum"
build_runner "$ENUM" 0 || harness_die "could not build the enumerate runner copy"
enum_stream() {  # <runner-dir> <event> <fx>
  local -a e=(CI=1); [[ "$2" != "-" ]] && e+=("GITHUB_EVENT_NAME=$2")
  (cd "$3" && env "${SCRUB[@]}" "${GIT_SCRUB[@]}" TEST_GROUP=all SOLEUR_DISABLE_SESSION_STATE=1 "${e[@]}" \
      timeout 120 bash "$1/scripts/test-all.sh" --enumerate-commands 2>/dev/null)
}
EFX="$(fx_new enum)"; fx_apply "$EFX" modify knowledge-base/note.md
enum_stream "$ENUM" "$PR" "$EFX" > "$TMP/enum-pr.txt"; enum_rc_pr=$?
enum_stream "$ENUM" - "$EFX" > "$TMP/enum-none.txt"; enum_rc_none=$?
enum_n=$(wc -l < "$TMP/enum-pr.txt" | tr -d ' ')
if (( enum_rc_pr == 0 && enum_rc_none == 0 && enum_n >= 100 )) && cmp -s "$TMP/enum-pr.txt" "$TMP/enum-none.txt"; then
  pass "enumerate: --enumerate-commands under CI=1 + pull_request is byte-identical to the event-unset stream ($enum_n records)"
else
  fail "enumerate: stream differs or is empty (rc ${enum_rc_pr}/${enum_rc_none}, $enum_n records)"
fi
for l in "${ALL_LABELS[@]}"; do
  if grep -qF "SUITE_COMMAND_DECLINED	$l" "$TMP/enum-pr.txt"; then fail "enumerate: $l was DECLINED in the enumerate stream"; else pass "enumerate: $l is not declined in the enumerate stream"; fi
done

# =================================================================================================
# 3. mutation matrix. Each mutant is graded CAUGHT only when its NAMED arm fails.
# =================================================================================================
MUT_N=0; MUT_CAUGHT=0
# mutant <name> <python-body> <tag-arms...>  — arms is a list of arm ids; at least one must fail
# and the mutant must still parse and run (a runner that cannot run reds everything and proves nothing).
mutant() {
  local name="$1" body="$2"; shift 2
  local -a arms=("$@")
  local mdir="$TMP/mut-$name"
  MUT_N=$((MUT_N + 1))
  build_runner "$mdir" 1 || { fail "mutant $name: could not build"; return; }
  if ! mutate "$mdir" "$body" 2>"$TMP/mut-$name.err"; then
    fail "mutant $name: the mutation did NOT land — $(tail -1 "$TMP/mut-$name.err")"; return
  fi
  if cmp -s "$mdir/scripts/test-all.sh" "$PRISTINE/scripts/test-all.sh" && cmp -s "$mdir/scripts/lib/test-relevance-paths.sh" "$PRISTINE/scripts/lib/test-relevance-paths.sh"; then
    fail "mutant $name: the mutated copy is byte-identical to the pristine one"; return
  fi
  if ! bash -n "$mdir/scripts/test-all.sh" 2>/dev/null || ! bash -n "$mdir/scripts/lib/test-relevance-paths.sh" 2>/dev/null; then
    fail "mutant $name: the mutant does not parse (a syntax error reds everything and proves nothing)"; return
  fi
  run_arms "$mdir" "m-$name" "${arms[@]}"
  grade_arms "m-$name" "${arms[@]}" || true
  if (( ${#GRADE_INFRA[@]} > 0 )); then
    fail "mutant $name: the mutated runner did not complete on arm(s) ${GRADE_INFRA[*]} (${GRADE_WHY[${GRADE_INFRA[0]}]:-?}) — a crash is not a catch"
  elif (( ${#GRADE_FAILED[@]} > 0 )); then
    MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "mutant $name: CAUGHT by arm(s) ${GRADE_FAILED[*]}"
  else
    fail "mutant $name: SURVIVED — arms ${arms[*]} stayed green"
  fi
}

PRARM_OPEN='      && [[ "${_pr_gate_canary_failed:-0}" != "1" ]]; then
      :
    else'

# row 1: always-decline under the PR arm. The canary rescues it by running everything, so the
# docs-only arm (which expects declines) and an own-file arm (which expects ONLY its battery) both go red.
mutant always-decline 's = sub_in_func(s, "_diff_touches", """'"$PRARM_OPEN"'""", """      && [[ "${_pr_gate_canary_failed:-0}" != "1" ]]; then
      return 1
    else""")' docs-only own-registry
if grep -q 'PR_GATE_CANARY_FAILED' "$TMP"/arm-m-always-decline-own-registry.out 2>/dev/null; then
  pass "mutant always-decline: the canary printed PR_GATE_CANARY_FAILED"; else fail "mutant always-decline: the canary did not print"; fi
# the canary must RESCUE, not merely print: under the always-decline mutant a machinery diff must still run
# every battery (the rescued run-all arm), and with the canary conjunct also dropped it must NOT
build_runner "$TMP/mut-canary-honoured" 1 || harness_die "could not build the canary-rescue runner"
mutate "$TMP/mut-canary-honoured" 's = sub_in_func(s, "_diff_touches", """'"$PRARM_OPEN"'""", """      && [[ "${_pr_gate_canary_failed:-0}" != "1" ]]; then
      return 1
    else""")' || harness_die "the canary-rescue mutation did not land"
run_arms "$TMP/mut-canary-honoured" m-rescue "$MACH_RUNNER_ARM"
grade_arms m-rescue "$MACH_RUNNER_ARM" || true
if (( ${#GRADE_FAILED[@]} == 0 && ${#GRADE_INFRA[@]} == 0 )); then pass "canary rescue: an always-decline predicate still runs every battery on a machinery diff"
else fail "canary rescue: the machinery arm went red under always-decline — the canary printed but did not rescue"; fi
mutant canary-not-honoured 's = sub_in_func(s, "_diff_touches", """'"$PRARM_OPEN"'""", """      && true; then
      return 1
    else""")' "$MACH_RUNNER_ARM"

# row 2: always-run under the PR arm (a vacuous gate that saves nothing)
mutant always-run 's = sub_in_func(s, "_diff_touches", """'"$PRARM_OPEN"'""", """      && [[ "${_pr_gate_canary_failed:-0}" != "1" ]]; then
      return 0
    else""")' docs-only docs-readme

# row 3: fail-safe arm removed — separately for the range ref and for the HEAD ref
mutant failsafe-detect-removed 's = sub_in_func(s, "_diff_touches", """  if [[ "$_diff_detect_ok" == 0 || "$_diff_head_ok" == 0 ]]; then return 0; fi""", """  if [[ "$_diff_head_ok" == 0 ]]; then return 0; fi""")' no-origin-ref
mutant failsafe-head-removed 's = sub_in_func(s, "_diff_touches", """  if [[ "$_diff_detect_ok" == 0 || "$_diff_head_ok" == 0 ]]; then return 0; fi""", """  if [[ "$_diff_detect_ok" == 0 ]]; then return 0; fi""")' head-diff-fails

# row 4: the event test loosened — any non-empty event, and ignored altogether
mutant event-any-nonempty 's = sub_in_func(s, "_diff_touches", """[[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]""", """[[ -n "${GITHUB_EVENT_NAME:-}" ]]""")' ev-push ev-merge-group ev-dispatch ev-schedule
mutant event-prefix-match 's = sub_in_func(s, "_diff_touches", """[[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]""", """[[ "${GITHUB_EVENT_NAME:-}" == pull_request* ]]""")' ev-pr-target ev-pr-review
mutant event-ignored 's = sub_in_func(s, "_diff_touches", """[[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]""", """true""")' ev-push ev-unset

# row 5: the bypass ignores CI (the PR arm becomes reachable with CI unset and no event)
mutant bypass-ignores-ci 's = sub_in_func(s, "_diff_touches", """  if [[ -n "${CI:-}" ]]; then
    # PR ARM""", """  if true; then
    # PR ARM""")' local-no-event

# row 6: the gate-machinery spread removed from ONE array, one mutant per array
for arr in "${ARRAYS[@]}"; do
  mutant "machinery-removed-$arr" 'import re
m = re.search(r"^'"$arr"'=\(.*?^\)", lib, re.S | re.M)
assert m, "array not found"
seg = m.group(0)
assert seg.count("${PR_GATE_MACHINERY_PATHS[@]}") == 1, "spread not exactly once"
lib = lib[:m.start()] + seg.replace("  \"${PR_GATE_MACHINERY_PATHS[@]}\"\n", "") + lib[m.end():]' "$MACH_RUNNER_ARM"
done

# row 6b: ONE member removed from the shared machinery list (every array loses it) — each member's own
# arm must red, so a member nothing exercises (the heavy shard manifest) cannot be dropped silently
for _m in "${PR_GATE_MACHINERY_PATHS[@]}"; do
  mutant "machinery-member-removed-${_m//\//_}" 'import re
m = re.search(r"^PR_GATE_MACHINERY_PATHS=\(.*?^\)", lib, re.S | re.M)
assert m, "machinery array not found"
seg = m.group(0)
lines = [l for l in seg.split("\n") if "\"'"$_m"'\"" in l]
assert len(lines) == 1, "member not exactly once"
lib = lib[:m.start()] + seg.replace(lines[0] + "\n", "") + lib[m.end():]' "$(machinery_arm "$_m")"
done

# row 7: lost opt-in — one call site reverts to bare `_diff_touches`, one mutant per site
for arr in "${ARRAYS[@]}"; do
  mutant "lost-optin-$arr" 's = sub_once(s, "_diff_touches --pr-gated \"${'"$arr"'[@]}\"", "_diff_touches \"${'"$arr"'[@]}\"", "call site")' docs-only
done

# row 8b: a sixth --pr-gated site the arms do not exercise reds the set-equality assertion
SIXTH_DIR="$TMP/mut-sixth-site"; build_runner "$SIXTH_DIR" 1 || harness_die "could not build the sixth-site runner"
mutate "$SIXTH_DIR" 's = sub_once(s, "skip_suite \"scripts/test-all-affected\" \"relevance\" \\\n      \"bash scripts/test-all-affected.test.sh\"\n  fi", "skip_suite \"scripts/test-all-affected\" \"relevance\" \\\n      \"bash scripts/test-all-affected.test.sh\"\n  fi\n  if _diff_touches --pr-gated \"${C4_PRODUCER_PATHS[@]}\"; then :; fi")' || harness_die "the sixth-site mutation did not land"
bash -n "$SIXTH_DIR/scripts/test-all.sh" || harness_die "the sixth-site mutant does not parse"
MUT_N=$((MUT_N + 1))
if [[ "$(derive_sites "$SIXTH_DIR/scripts/test-all.sh")" != "$want_sites" ]]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "mutant sixth-site: the set-equality assertion goes RED on an unexercised --pr-gated site"
else fail "mutant sixth-site: SURVIVED — a sixth --pr-gated site is invisible to the dispatch check"; fi

# row 9: rename-only slips the predicate when the rename-source append is dropped
mutant rename-sources-dropped 's = sub_once(s, "$(git -c core.quotePath=false diff --name-status -M HEAD 2>/dev/null || true)\n$(git -c core.quotePath=false diff --name-status -M origin/main...HEAD 2>/dev/null || true)", "")' rename-only

# row 10: enumerate gated — drop the _ENUMERATE inertness. Graded on the enumerate stream, not on a
# recorded arm: the recorder replaces run_suite, which is what the enumerate path drives.
build_runner "$TMP/mut-enumerate-gated-raw" 0 || harness_die "could not build the enumerate-gated runner"
mutate "$TMP/mut-enumerate-gated-raw" 's = sub_in_func(s, "_diff_touches", "(( _ENUMERATE != 1 )) \\\n       && ", "")' || harness_die "the enumerate-gated mutation did not land"
bash -n "$TMP/mut-enumerate-gated-raw/scripts/test-all.sh" || harness_die "the enumerate-gated mutant does not parse"
MUT_N=$((MUT_N + 1))
enum_stream "$TMP/mut-enumerate-gated-raw" "$PR" "$EFX" > "$TMP/enum-mut.txt" 2>/dev/null
if ! cmp -s "$TMP/enum-mut.txt" "$TMP/enum-none.txt"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "mutant enumerate-gated: the enumerate stream differs from the event-unset stream"
else fail "mutant enumerate-gated: SURVIVED — the stream stayed byte-identical"; fi

# row 11: canary deleted, then always-decline — the machinery diff must still run every battery
mutant canary-deleted-always-decline 'import re
m = re.search(r"^_pr_gate_canary_failed=0\nif .*?^fi\n", s, re.S | re.M)
assert m, "canary block not found"
s = s[:m.start()] + "_pr_gate_canary_failed=0\n" + s[m.end():]
s = sub_in_func(s, "_diff_touches", """'"$PRARM_OPEN"'""", """      && [[ "${_pr_gate_canary_failed:-0}" != "1" ]]; then
      return 1
    else""")' "$MACH_RUNNER_ARM" own-registry

# row 12: per-battery isolation — a typo in ONE array (its own file renamed) stops that battery arming
for arr in "${ARRAYS[@]}"; do
  f="$(own_file "$arr")"
  case "$arr" in
    REGISTRY_BATTERY_PATHS) arm_id=own-registry ;; CF_TUNNEL_BATTERY_PATHS) arm_id=own-cf ;;
    LINT_ORPHAN_BATTERY_PATHS) arm_id=own-lint ;; TAG_AUTHORSHIP_BATTERY_PATHS) arm_id=own-tag ;;
    TEST_ALL_AFFECTED_BATTERY_PATHS) arm_id=own-taa ;;
  esac
  mutant "array-typo-$arr" 'import re
m = re.search(r"^'"$arr"'=\(.*?^\)", lib, re.S | re.M)
assert m, "array not found"
seg = m.group(0)
assert seg.count("\"'"$f"'\"") == 1, "own file not exactly once"
lib = lib[:m.start()] + seg.replace("\"'"$f"'\"", "\"'"${f%.*}"'-TYPO.'"${f##*.}"'\"") + lib[m.end():]' "$arm_id"
done

# =================================================================================================
# 4. H1 — the harness itself. A child run with pass() sabotaged must refuse (rc != 0).
# =================================================================================================
for _sab in pass fail; do
  SAB_OUT="$TMP/sabotage-$_sab.out"
  PR_GATE_TEST_SABOTAGE=$_sab timeout 60 bash "${BASH_SOURCE[0]}" > "$SAB_OUT" 2>&1; sab_rc=$?
  if (( sab_rc != 0 )) && grep -q 'instrument self-test' "$SAB_OUT"; then
    pass "H1: a suite whose $_sab() is a no-op exits non-zero (rc=$sab_rc) via the instrument self-test"
  else
    fail "H1: the child with $_sab() sabotaged exited $sab_rc without refusing"
  fi
done

# =================================================================================================
# 5. verdict. Floors are reported with printf + exit, never through the helpers they back-stop.
# =================================================================================================
printf '\nmutants: %d run, %d caught\n' "$MUT_N" "$MUT_CAUGHT"
printf 'test-all-pr-battery-gate: %d passed, %d failed, %d assertion(s) executed (%ds)\n' "$passes" "$fails" "$asserted" "$((SECONDS - START_S))"

# The floor sits flush against its `if` with its threshold on the line above, for the reason
# scripts/guard-vacuity-floor.test.sh states (it slices the floor block and widens backward over
# CONTIGUOUS simple assignments).
PR_GATE_MIN_ASSERTIONS=88
if (( asserted < PR_GATE_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < PR_GATE_MIN_ASSERTIONS=%d\n' "$asserted" "$PR_GATE_MIN_ASSERTIONS" >&2
  exit 1
fi
if (( MUT_CAUGHT != MUT_N )); then
  printf '[FATAL] %d of %d mutant(s) survived or did not land\n' "$((MUT_N - MUT_CAUGHT))" "$MUT_N" >&2
  exit 1
fi
# The verdict reads the append-only log AND the counter: neutering either alone cannot turn a failing
# assertion into exit 0 (a rewritten fail() that stops counting still has to stop printing and logging).
[[ ! -s "$FAILS_LOG" ]] || exit 1
(( fails == 0 )) || exit 1
exit 0
