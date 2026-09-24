#!/usr/bin/env bash
# test-all-affected.test.sh — the affected gate's own mutation battery (#8322).
#
# WHAT IS UNDER TEST. `scripts/test-all.sh`'s affected mode: the local default that
# runs the suites a diff can move plus every repo-global ratchet, demoting the full
# battery to CI or an explicit `--full`. The gate is fail-SAFE by construction —
# an unclassified suite runs rather than skipping — so the failure this battery
# exists to catch is the opposite direction: a selection that shrinks silently, a
# fallback that forgets to announce itself, or a refusal that lets a full-scale run
# proceed under a mode that was supposed to be exempt.
#
# HOW IT TESTS. Two harnesses, both running the runner in place (never relocating
# the real file):
#
#   PRINT ARMS drive `bash scripts/test-all.sh --affected --print-affected-set`
#   against the REAL repo — enumerate-shaped: it walks every registration, emits
#   an AFFECTED_CLASS receipt per registration, and runs nothing. Classification
#   is a property of the suite and the lib, so the real tree is the honest corpus.
#
#   SANDBOX ARMS copy the runner to $TESTROOT, inject four seams —
#   SANDBOX_DIFF_NAMES (the diff blob), SANDBOX_DETECT_OK / SANDBOX_HEAD_OK (the
#   two diff-detection arms), SANDBOX_SIBLINGS (the sibling-run count tc_preamble
#   would have promoted) — and neuter suite EXECUTION (`"$@" || rc=$?` becomes a
#   RAN record + rc=0). The chokepoint, the classifier, the pre-pass and the
#   refusal arms all stay live; only the suite payload is stubbed. The affected
#   declarations lib is copied beside the sandbox runner except in the arm that
#   asserts its absence.
#
# WHY A SANDBOX AT ALL. Asserting "suite X was not selected" requires a controlled
# diff; the real worktree's diff is whatever this branch happens to touch. The
# seams make the diff a parameter of the arm, not of the session.
#
# EXIT-CODE DOCTRINE UNDER TEST. rc=4 is "refused — nothing ran": the pre-execution
# refusals (below-floor, zero-executed, degraded-full refusal re-check) use it.
# rc=3 stays reserved for "a suite was terminated — coverage not obtained" (#7424),
# which a selection refusal is NOT. rc=2 stays argument/shape errors.
#
# AUTHORING CONSTRAINTS (work/SKILL.md; each cost a debug cycle somewhere):
#   - Never `producer | grep -q` under `set -o pipefail` — early match closes the
#     pipe, producer takes SIGPIPE, the negative assertion fails OPEN.
#   - A deliberately-nonzero command inside `$( )` aborts under `set -e` — capture
#     rc on its own line.
#   - `cases` is incremented at the CALL SITE, never inside a verdict helper.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): the sandbox is a
# copy of the runner plus seams, never a captured transcript.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
AFF_LIB="$REPO_ROOT/scripts/lib/test-affected-paths.sh"
REL_LIB="$REPO_ROOT/scripts/lib/test-relevance-paths.sh"
RWB_LIB="$REPO_ROOT/scripts/lib/repo-write-boundary.sh"

export TMPDIR="${TMPDIR:-/var/tmp}"
TESTROOT="$(mktemp -d -t test-all-affected.XXXXXXXX)" || exit 2

# BYTE-IDENTICAL to plugins/soleur/test/test-helpers.sh's assert_fixture_dir() —
# copied, not sourced, per the suite-side precedent
# (scripts/check-tom4-rls-posture.test.sh). Two repo-global ratchets police the
# fixture-write discipline this enforces.
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
assert_fixture_dir "$TESTROOT"

FAILLOG="$TESTROOT/failures.log"
: > "$FAILLOG"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT INT TERM HUP

PASS=0; FAIL=0; cases=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; printf '%s\n' "$1" >> "$FAILLOG"; }

for _required in "$RUNNER" "$AFF_LIB" "$REL_LIB" "$RWB_LIB"; do
  [[ -f "$_required" ]] || { echo "ERROR: $_required missing — the suite cannot run" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Instrument self-test (ADR-193 H1): both verdict helpers must move their
# counters and fail() must WRITE the log the exit gate reads.
# ---------------------------------------------------------------------------
_self_pass=$PASS; _self_fail=$FAIL
_real_faillog="$FAILLOG"
FAILLOG="$TESTROOT/selftest.log"; : > "$FAILLOG"
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
_self_logged=$(wc -l < "$FAILLOG" | tr -d ' ')
FAILLOG="$_real_faillog"
if (( PASS != _self_pass + 1 )) || (( FAIL != _self_fail + 1 )) || (( _self_logged != 1 )); then
  printf '\n[FATAL] instrument self-test failed: pass moved %d, fail moved %d, log lines %d\n' \
    "$((PASS - _self_pass))" "$((FAIL - _self_fail))" "$_self_logged" >&2
  exit 1
fi
PASS=$_self_pass; FAIL=$_self_fail; cases=0

# Every sandboxed SUT invocation scrubs the runner-significant environment.
# The suite asserts verdicts; an inherited CI=1 would early-return _diff_touches
# (every edge suite selects -> rows f/q red), SOLEUR_SUBAGENT/SOLEUR_ALLOW_FULL_GATE
# move the refusal arms, FORCE_ALL preempts the asserted fallback reason, and
# TEST_TIMING_LOG would write synthetic skip rows into the operator's real log.
ENV_SCRUB="-u TEST_GROUP -u SCRIPTS_SHARD -u CI -u SOLEUR_SUBAGENT -u SOLEUR_ALLOW_FULL_GATE -u SOLEUR_TEST_FORCE_ALL -u SOLEUR_INCIDENT_SKIP -u TC_RUNTIME_CEILING_S"

# ---------------------------------------------------------------------------
# Sandbox builder. $1 = sandbox runner path; $2 = "with-lib" | "no-lib".
# Copies the runner and the libs it sources fail-closed (relevance, boundary)
# plus the affected declarations lib unless the arm is testing its absence.
# test-contention.sh is deliberately NOT copied: its absence installs the
# runner's own no-op stubs, which keeps the sibling census inert except where an
# arm sets SANDBOX_SIBLINGS — and keeps every arm free of a real /proc walk and
# the advisory lock.
# ---------------------------------------------------------------------------
build_sandbox() {
  local out="$1" with_lib="${2:-with-lib}"
  local dir; dir="$(dirname "$out")"
  mkdir -p "$dir/lib" || return 1
  cp "$RUNNER" "$out" || return 1
  cp "$REL_LIB" "$dir/lib/" || return 1
  cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$dir/lib/" || return 1
  if [[ "$with_lib" == "with-lib" ]]; then
    cp "$AFF_LIB" "$dir/lib/" || return 1
  fi
  python3 - "$out" <<'PY' || return 1
import sys, re
path = sys.argv[1]
s = open(path).read()

# 1. Diff seams. Injected just before the _diff_touches definition so they sit
#    AFTER every _diff_names append and BEFORE the _infra_in_diff derivation —
#    the infra verdict then derives from the forced names honestly.
old = '_diff_touches() {'
assert s.count(old) == 1, f"expected exactly one '{old}', found {s.count(old)}"
s = s.replace(old, (
    '[[ -n "${SANDBOX_DIFF_NAMES+x}" ]] && _diff_names="$SANDBOX_DIFF_NAMES"\n'
    '[[ -n "${SANDBOX_LIVE_UNTRACKED:-}" ]] && _diff_names="${_diff_names}\n$(git ls-files --others --exclude-standard 2>/dev/null)"\n'
    '[[ -n "${SANDBOX_DETECT_OK:-}" ]] && _diff_detect_ok="$SANDBOX_DETECT_OK"\n'
    '[[ -n "${SANDBOX_HEAD_OK:-}" ]] && _diff_head_ok="$SANDBOX_HEAD_OK"\n'
    '[[ -n "${SANDBOX_PREFIXES+x}" ]] && TEST_RELEVANCE_PREFIXES=($SANDBOX_PREFIXES)\n'
    + old
), 1)

# 2. Execution stub: the suite payload never runs. The chokepoint, classifier
#    and accounting stay live; only `"$@"` is replaced with a RAN record.
old2 = '  "$@" || rc=$?'
assert s.count(old2) == 1, f"expected exactly one '{old2}', found {s.count(old2)}"
s = s.replace(old2,
    '  rc=0\n  printf \'RAN\\t%s\\n\' "$label" >> "${SANDBOX_RECORD:-/dev/null}"', 1)

# 3. Sibling-count seam, injected right after the tc_preamble call. The sandbox
#    has no contention lib, so the stubbed preamble sets nothing; the seam is
#    what the sibling refusal reads.
matches = re.findall(r'^tc_preamble$', s, re.M)
assert len(matches) == 1, f"expected exactly one column-0 tc_preamble call, found {len(matches)}"
s = re.sub(r'^tc_preamble$', (
    'tc_preamble\n'
    'if [[ -n "${SANDBOX_SIBLINGS:-}" ]]; then\n'
    '  TC_SIBLING_RUN_COUNT="$SANDBOX_SIBLINGS"\n'
    '  TC_SIBLING_RUN_COUNT_PID=$$\n'
    'fi'
), s, count=1, flags=re.M)

# 4. Corpus trim. The arms under test exercise SELECTION — a handful of named
#    labels — so the ~300-registration stream is fixture, not subject. The
#    filter sits inside run_suite BEFORE _shard_selects ticks the ordinal, so
#    a trimmed label leaves the enumerate stream AND the dispatch walk
#    identically and every ordinal map stays aligned (skip_suite declines keep
#    ticking on both sides the same way). ~2-3 min of per-arm classification
#    collapses to seconds; real-corpus evidence stays in rows d/e/r, which run
#    the unmodified runner. Keep-list = every label an arm asserts on.
old = 'run_suite() {\n  local label="$1"; shift\n'
assert s.count(old) == 1, f"expected exactly one run_suite head, found {s.count(old)}"
s = s.replace(old, old + '''  # SANDBOX corpus trim (#8322 suite): only the labels the arms assert reach
  # the chokepoint — enumerate and dispatch skip the rest identically.
  case "$label" in
    tests/scripts/dev-suite-mutex-wiring|scripts/lint-dual-lockfile|\\
    tests/scripts/registry-gate-mutation-battery|\\
    apps/web-platform/infra/run-registered-suites.sh|\\
    tests/commands/sync-domain-model|\\
    plugins/soleur/test/c4-model-freshness.test.sh) : ;;
    *) return 0 ;;
  esac
''', 1)

open(path, 'w').write(s)
print("sandbox built")
PY
}

# Run one sandbox arm. Args: name=value pairs become the arm's env; everything
# after `--` becomes the runner's argv. Sets ARM_RC / ARM_OUT / ARM_RECORD.
run_arm() {
  local sb="$TESTROOT/sb-$cases/test-all.sh" out_f="$TESTROOT/out-$cases" rec_f="$TESTROOT/rec-$cases"
  local -a env_pairs=() argv=()
  local seen_dashdash=""
  for a in "$@"; do
    if [[ "$a" == "--" ]]; then seen_dashdash=1; continue; fi
    if [[ -z "$seen_dashdash" ]]; then env_pairs+=("$a"); else argv+=("$a"); fi
  done
  : > "$rec_f"
  build_sandbox "$sb" "${SANDBOX_LIB:-with-lib}" > /dev/null || {
    ARM_RC=97; ARM_OUT=""; ARM_RECORD=""; return 1
  }
  local rc=0
  ( cd "$REPO_ROOT" && env $ENV_SCRUB \
      SOLEUR_DISABLE_SESSION_STATE=1 SANDBOX_RECORD="$rec_f" \
      TEST_TIMING_LOG="$TESTROOT/timing-$cases.tsv" \
      ${env_pairs[@]+"${env_pairs[@]}"} bash "$sb" "${argv[@]+"${argv[@]}"}" ) \
      > "$out_f" 2>&1 || rc=$?
  ARM_RC=$rc
  ARM_OUT="$(cat "$out_f")"
  ARM_RECORD="$(cat "$rec_f")"
  ARM_SB="$sb"
  return 0
}

# Count of RAN records in the last arm. awk, not `grep '\t'` — GNU grep treats
# BRE `\t` as a literal 't' ("stray \ before t" warning), which reads as zero
# records and turns every ran-count assert fail-open.
ran_count() { awk -F'\t' '$1=="RAN"' <<<"$ARM_RECORD" | wc -l | tr -d ' '; }

# Runnable-registration count for "everything ran" asserts. $1 = runner path —
# the REAL runner for row d's real-corpus receipt count, the trimmed SANDBOX
# copy for the arms (whose "everything" is the keep-list stream). Memoized per
# path: every sandbox build carries the same trim, so the count is stable.
# $2 (optional) = the arm's SANDBOX_DIFF_NAMES. An `==` assert MUST pass it:
# without it the enumerate reads the REAL branch diff, so a branch touching
# apps/web-platform/infra/ counts the infra runner the arm's forced diff skips.
RUNNABLE_N="" RUNNABLE_N_FOR=""
runnable_n() {
  if [[ "$RUNNABLE_N_FOR" != "$1|${2+x}${2-}" ]]; then
    RUNNABLE_N=$(cd "$REPO_ROOT" && env $ENV_SCRUB \
      SOLEUR_DISABLE_SESSION_STATE=1 ${2+"SANDBOX_DIFF_NAMES=$2"} \
      bash "$1" --enumerate-commands 2>/dev/null \
      | awk -F'\t' '$1=="SUITE_COMMAND"' | wc -l | tr -d ' ')
    RUNNABLE_N_FOR="$1|${2+x}${2-}"
  fi
  printf '%s\n' "$RUNNABLE_N"
}

echo "== test-all-affected: mutation matrix =="

# --- Row a: --help ------------------------------------------------------------
cases=$((cases + 1))
rc=0
_help_out=$(env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --help 2>&1) || rc=$?
if [[ "$rc" == "0" ]] && grep -qF -- '--affected' <<<"$_help_out" \
     && grep -qF -- '--full' <<<"$_help_out" \
     && grep -qF -- '--print-affected-set' <<<"$_help_out"; then
  pass "a: --help exits 0 and documents all three flags"
else
  fail "a: --help rc=$rc; out head: $(head -5 <<<"$_help_out")"
fi

# --- Row b: --affected --full conflict -> exit 2 --------------------------------
cases=$((cases + 1))
rc=0
env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --affected --full >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "b: --affected --full exits 2"
else
  fail "b: --affected --full rc=$rc, expected 2"
fi

# --- Row c: trailing positional junk -> exit 2 ---------------------------------
cases=$((cases + 1))
rc=0
env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" all extra-positional >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "c: >1 positional exits 2"
else
  fail "c: trailing positional rc=$rc, expected 2"
fi

# --- Row d: --print-affected-set emits receipts for the runnable stream ---------
cases=$((cases + 1))
rc=0
_print_out=$(cd "$REPO_ROOT" && env $ENV_SCRUB \
  SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --affected --print-affected-set 2>/dev/null) || rc=$?
_receipts=$(awk -F'\t' '$1=="AFFECTED_CLASS"' <<<"$_print_out" | wc -l | tr -d ' ')
if [[ "$rc" == "0" ]] && (( _receipts == $(runnable_n "$RUNNER") )); then
  pass "d: print-affected-set emits ${_receipts} receipts (== $(runnable_n "$RUNNER") runnable)"
else
  fail "d: print rc=$rc receipts=${_receipts} runnable=$(runnable_n "$RUNNER")"
fi

# --- Row e: receipts carry real classes — spot-check the census anchors ---------
cases=$((cases + 1))
_cls_lockfile=$(awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="scripts/lint-dual-lockfile"{print $3}' <<<"$_print_out" | head -1)
_cls_mutex=$(awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="tests/scripts/dev-suite-mutex-wiring"{print $3}' <<<"$_print_out" | head -1)
_cls_unittest=$(awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="tests/scripts/lint-rule-ids"{print $3}' <<<"$_print_out" | head -1)
if [[ "$_cls_lockfile" == "always_on" && "$_cls_mutex" == "edge:declared" && "$_cls_unittest" == edge:* ]]; then
  pass "e: lint-dual-lockfile=always_on, mutex-wiring=edge:declared, unittest-mod=${_cls_unittest}"
else
  fail "e: lockfile='${_cls_lockfile:-<none>}' mutex-wiring='${_cls_mutex:-<none>}' unittest='${_cls_unittest:-<none>}'"
fi

# --- Row f: affected run declines untouched suites, keeps always-on -------------
# Force a diff touching only the tenant-integration workflow: its declared-edge
# suite must be selected; an unrelated edge suite must not; an always-on lint
# must still run.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/tenant-integration.yml' \
  -- --affected
_rc=$ARM_RC
_ran=$(ran_count)
if [[ "$_rc" == "0" ]] \
  && grep -qF $'RAN\ttests/scripts/dev-suite-mutex-wiring' <<<"$ARM_RECORD" \
  && grep -qF $'RAN\tscripts/lint-dual-lockfile' <<<"$ARM_RECORD" \
  && ! grep -qF $'RAN\ttests/scripts/registry-gate-mutation-battery' <<<"$ARM_RECORD" \
  && grep -qF 'not-affected' <<<"$ARM_OUT" \
  && ! grep -qF 'IS covered above' <<<"$ARM_OUT" \
  && grep -qF 'MODE=affected' <<<"$ARM_OUT"; then
  pass "f: affected selects edge+always-on, declines the rest (ran=${_ran})"
else
  fail "f: rc=$_rc ran=${_ran} — $(grep -c 'not-affected' <<<"$ARM_OUT") not-affected lines"
fi

# --- Row g: --full ignores the diff, runs everything ----------------------------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  -- --full
_rc=$ARM_RC; _ran=$(ran_count)
if [[ "$_rc" == "0" ]] && (( _ran >= $(runnable_n "$ARM_SB") )) \
  && grep -qF 'MODE=full' <<<"$ARM_OUT"; then
  pass "g: --full runs all ${_ran} registrations regardless of diff"
else
  fail "g: --full rc=$_rc ran=${_ran} runnable=$(runnable_n "$ARM_SB")"
fi

# --- Row h: undecidable-diff arm degrades to full --------------------------------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DETECT_OK=0' 'SANDBOX_DIFF_NAMES=' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
_decl=$(grep -c "^\\[skip\\]" <<<"$ARM_OUT" | tr -d " ")
if [[ "$_rc" == "0" ]] && (( _ran + _decl >= $(runnable_n "$ARM_SB") )) \
  && grep -qF 'AFFECTED_FALLBACK' <<<"$ARM_OUT" \
  && grep -qF 'undecidable-diff' <<<"$ARM_OUT"; then
  pass "h: undecidable-diff degrades to full with the fallback banner"
else
  fail "h: rc=$_rc ran=${_ran} out=$(grep -c AFFECTED_FALLBACK <<<"$ARM_OUT") fallback lines"
fi

# --- Row i: HEAD-diff failure degrades to full -----------------------------------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_HEAD_OK=0' 'SANDBOX_DIFF_NAMES=' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
_decl=$(grep -c "^\\[skip\\]" <<<"$ARM_OUT" | tr -d " ")
if [[ "$_rc" == "0" ]] && (( _ran + _decl >= $(runnable_n "$ARM_SB") )) \
  && grep -qF 'undecidable-diff' <<<"$ARM_OUT"; then
  pass "i: head-diff failure degrades to full"
else
  fail "i: rc=$_rc ran=${_ran}"
fi

# --- Row j: missing declarations lib degrades to full -----------------------------
cases=$((cases + 1))
SANDBOX_LIB=no-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
_decl=$(grep -c "^\\[skip\\]" <<<"$ARM_OUT" | tr -d " ")
if [[ "$_rc" == "0" ]] && (( _ran + _decl >= $(runnable_n "$ARM_SB") )) \
  && grep -qF 'index-missing' <<<"$ARM_OUT"; then
  pass "j: missing lib degrades to full (index-missing), never narrows"
else
  fail "j: rc=$_rc ran=${_ran}"
fi

# --- Row k: runner-changed diff degrades to full ----------------------------------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=scripts/test-all.sh' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
_decl=$(grep -c "^\\[skip\\]" <<<"$ARM_OUT" | tr -d " ")
if [[ "$_rc" == "0" ]] && (( _ran + _decl >= $(runnable_n "$ARM_SB") )) \
  && grep -qF 'runner-changed' <<<"$ARM_OUT"; then
  pass "k: a diff touching the runner degrades to full (runner-changed)"
else
  fail "k: rc=$_rc ran=${_ran}"
fi

# --- Row l: SOLEUR_SUBAGENT refusal — affected proceeds, --full refuses -----------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'SOLEUR_SUBAGENT=1' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
if [[ "$_rc" == "0" ]] && (( _ran > 0 )); then
  pass "l1: affected proceeds under SOLEUR_SUBAGENT (ran=${_ran})"
else
  fail "l1: affected+subagent rc=$_rc ran=${_ran}"
fi
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'SOLEUR_SUBAGENT=1' \
  -- --full
_rc=$ARM_RC
if [[ "$_rc" == "4" ]]; then
  pass "l2: --full refuses under SOLEUR_SUBAGENT (rc=4)"
else
  fail "l2: --full+subagent rc=$_rc, expected 4"
fi

# --- Row m: sibling refusal — affected proceeds, --full refuses, degraded refuses -
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'SANDBOX_SIBLINGS=2' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
if [[ "$_rc" == "0" ]] && (( _ran > 0 )); then
  pass "m1: affected proceeds under sibling contention (ran=${_ran})"
else
  fail "m1: affected+siblings rc=$_rc ran=${_ran}"
fi
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'SANDBOX_SIBLINGS=2' \
  -- --full
_rc=$ARM_RC
if [[ "$_rc" == "4" ]]; then
  pass "m2: --full refuses under sibling contention (rc=4)"
else
  fail "m2: --full+siblings rc=$_rc, expected 4"
fi
cases=$((cases + 1))
SANDBOX_LIB=no-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'SANDBOX_SIBLINGS=2' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "4" ]]; then
  pass "m3: degraded-full (index-missing) re-arms the sibling refusal (rc=4)"
else
  fail "m3: degraded+siblings rc=$_rc, expected 4"
fi

# --- Row n: explicit TEST_GROUP=infra ask executes the infra runner ---------------
# The P0 seam: under an explicit group ask the infra registration must RUN even
# when the diff does not reach it — a counted decline here would report
# coverage for a suite that never executed.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'TEST_GROUP=infra' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] \
  && grep -qF $'RAN\tapps/web-platform/infra/run-registered-suites.sh' <<<"$ARM_RECORD"; then
  pass "n: TEST_GROUP=infra + affected EXECUTES the infra runner on an infra-free diff"
else
  fail "n: rc=$_rc record=$(cat <<<"$ARM_RECORD" | head -3)"
fi

# --- Row o: below-floor selection refuses rc=4 -------------------------------------
# Gut ALWAYS_ON to a single bogus label in the sandbox lib: the live-scanner
# floor can never be met, so the run must refuse BEFORE anything executes.
cases=$((cases + 1))
_sbn="$TESTROOT/sb-floor/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "o: sandbox build"; }
python3 - "$(dirname "$_sbn")" <<'PY'
import sys, re
p = sys.argv[1] + "/lib/test-affected-paths.sh"
s = open(p).read()
s = re.sub(r'ALWAYS_ON_SUITES=\(.*?\n\)',
           'ALWAYS_ON_SUITES=("bogus/never-registered")', s, count=1, flags=re.S)
open(p, 'w').write(s)
PY
rc=0
( cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD=/dev/null 'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
    bash "$_sbn" --affected ) >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "4" ]]; then
  pass "o: below-live-floor selection refuses rc=4 (AFFECTED_UNRESOLVED)"
else
  fail "o: gutted always-on rc=$rc, expected 4"
fi

# --- Row p: FORCE_ALL + affected degrades to full -----------------------------------
cases=$((cases + 1))
_p_diff=.github/workflows/apply-sentry-infra.yml
SANDBOX_LIB=with-lib run_arm \
  "SANDBOX_DIFF_NAMES=$_p_diff" \
  'SOLEUR_TEST_FORCE_ALL=1' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
# Same real-diff vs forced-diff asymmetry as row t: FORCE_ALL keeps relevance declines, so a
# branch touching apps/web-platform/infra/ enumerates the infra runner this arm declines.
if [[ "$_rc" == "0" ]] && (( _ran >= $(runnable_n "$ARM_SB" "$_p_diff") )) \
  && grep -qF 'reason=force-all' <<<"$ARM_OUT"; then
  pass "p: FORCE_ALL under affected degrades to full, announced"
else
  fail "p: FORCE_ALL+affected rc=$_rc ran=${_ran} runnable=$(runnable_n "$ARM_SB" "$_p_diff")"
fi

# --- Row q: epilogue carries not-affected accounting + the --full lever ------------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  -- --affected
if grep -qE 'not-affected' <<<"$ARM_OUT" \
  && grep -qF 'test-all.sh --full' <<<"$ARM_OUT"; then
  pass "q: epilogue counts not-affected and prints the --full lever"
else
  fail "q: epilogue missing not-affected accounting or --full lever"
fi

# --- Row r: enumerate contract unchanged -------------------------------------------
cases=$((cases + 1))
rc=0
# Capture once, then assert on the variable: `producer | grep -q` under
# pipefail reads as failure when grep exits early on its match and the still-
# writing producer takes SIGPIPE (the trap test-all.sh itself documents).
_enum_out=$(cd "$REPO_ROOT" && env $ENV_SCRUB \
  SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --enumerate-commands 2>/dev/null) || rc=$?
_enum_n=$(awk -F'\t' '$1=="SUITE_COMMAND" || $1=="SUITE_COMMAND_DECLINED"' <<<"$_enum_out" | wc -l | tr -d ' ')
if [[ "$rc" == "0" ]] && (( _enum_n >= 400 )) \
  && grep -qF $'SUITE_COMMAND\ttests/scripts/lint-rule-ids' <<<"$_enum_out"; then
  pass "r: --enumerate-commands emits the full stream (${_enum_n} records, named anchor present)"
else
  fail "r: enumerate rc=$rc records=${_enum_n}"
fi

# --- Row s: SCRIPTS_SHARD + affected — env -u on the enumerate child is load-bearing
# The real runner refuses SCRIPTS_SHARD under TEST_GROUP=all (:818) — the only
# group under which the affected pre-pass runs. The `env -u SCRIPTS_SHARD` on
# the nested enumerate is therefore unreachable upstream… unless the refusal is
# bypassed. Two sandbox arms do exactly that, proving the env -u is what keeps
# the child's stream ordinal-aligned with the parent's 1..N dispatch walk.
# NOTE: the carrier is unset at :850 (after parsing into _SHARD_K/_SHARD_N), so
# under a real run the nested enumerate never sees SCRIPTS_SHARD at all. To make
# `env -u SCRIPTS_SHARD` observable, s2 also removes the parent's `unset` — then
# the env -u alone is what keeps the child's stream unsharded and the map
# aligned. (Stripping env -u as well would diverge; row t already proves the
# guard catches that and fails toward coverage.)
_shardsplice() { # $1 = sandbox runner path, $2 = "nounset" to also remove the parent's unset
  python3 - "$1" "$2" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'if [[ -n "${SCRIPTS_SHARD+x}" && "$TEST_GROUP" != "scripts" && "$TEST_GROUP" != "scripts-heavy" ]]; then'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, 'if false; then # sandbox: shard+all allowed to exercise the affected pre-pass')
if sys.argv[2] == "nounset":
    old2 = 'unset SCRIPTS_SHARD'
    assert s.count(old2) == 1, s.count(old2)
    s = s.replace(old2, ': sandbox keeps SCRIPTS_SHARD so env -u on the enumerate child is load-bearing')
open(p, 'w').write(s)
PY
}

cases=$((cases + 1))
_sbn="$TESTROOT/sb-shard/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "s1: sandbox build"; }
_shardsplice "$_sbn" keep || { fail "s1: splice"; }
rc=0
( cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD="$TESTROOT/rec-$cases" \
    'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
    'SCRIPTS_SHARD=1/2' \
    bash "$_sbn" --affected ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
ARM_OUT="$(cat "$TESTROOT/out-$cases")"; ARM_RECORD="$(cat "$TESTROOT/rec-$cases")"
_ran=$(ran_count)
if [[ "$rc" == "0" ]] && ! grep -qF 'AFFECTED_DIVERGENT' <<<"$ARM_OUT" \
  && (( _ran > 0 && _ran < $(runnable_n "$_sbn") )); then
  pass "s1: sharded affected keeps the map aligned — only the leg runs (ran=${_ran})"
else
  fail "s1: sharded affected rc=$rc ran=${_ran} divergent=$(grep -c AFFECTED_DIVERGENT <<<"$ARM_OUT")"
fi

cases=$((cases + 1))
_sbn="$TESTROOT/sb-shardstrip/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "s2: sandbox build"; }
_shardsplice "$_sbn" nounset || { fail "s2: splice"; }
rc=0
( cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD="$TESTROOT/rec-$cases" \
    'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
    'SCRIPTS_SHARD=1/2' \
    bash "$_sbn" --affected ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
ARM_OUT="$(cat "$TESTROOT/out-$cases")"; ARM_RECORD="$(cat "$TESTROOT/rec-$cases")"
_ran=$(ran_count)
# Parent keeps the carrier; env -u on the child is now the ONLY thing keeping
# its stream unsharded. Aligned map => leg only, no divergence.
if [[ "$rc" == "0" ]] && ! grep -qF 'AFFECTED_DIVERGENT' <<<"$ARM_OUT" \
  && (( _ran > 0 && _ran < $(runnable_n "$_sbn") )); then
  pass "s2: env -u alone keeps the sharded enumerate aligned (ran=${_ran})"
else
  fail "s2: nounset arm rc=$rc ran=${_ran} divergent=$(grep -c AFFECTED_DIVERGENT <<<"$ARM_OUT")"
fi

# --- Row t: enumerate/dispatch ordinal divergence drops the map, runs all -------
# Splice a one-position ordinal shift into the sandbox's label map: the runtime
# label guard must notice the mismatch, drop _aff_sel, and run EVERYTHING —
# never apply another suite's selection bit.
cases=$((cases + 1))
_sbn="$TESTROOT/sb-divergent/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "t: sandbox build"; }
python3 - "$(dirname "$_sbn")" <<'PY' || { fail "t: splice"; }
import sys
p = sys.argv[1] + "/test-all.sh"
s = open(p).read()
old = '_aff_label[$_aff_ordinal]="${_aff_fields[1]}"'
assert s.count(old) == 1, s.count(old)
s = s.replace(old,
  '_aff_ordinal=$(( _aff_ordinal + 1 )); _aff_label[$_aff_ordinal]="${_aff_fields[1]}"')
open(p, 'w').write(s)
PY
rc=0
_t_diff=.github/workflows/apply-sentry-infra.yml
( cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD="$TESTROOT/rec-$cases" \
    "SANDBOX_DIFF_NAMES=$_t_diff" \
    bash "$_sbn" --affected ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
ARM_OUT="$(cat "$TESTROOT/out-$cases")"; ARM_RECORD="$(cat "$TESTROOT/rec-$cases")"
_ran=$(ran_count)
if grep -qF 'AFFECTED_DIVERGENT' <<<"$ARM_OUT" \
  && (( _ran == $(runnable_n "$_sbn" "$_t_diff") )); then
  pass "t: ordinal divergence drops the selection map; every suite runs (ran=${_ran})"
else
  fail "t: divergent map ran=${_ran} runnable=$(runnable_n "$_sbn" "$_t_diff") divergent=$(grep -c AFFECTED_DIVERGENT <<<"$ARM_OUT")"
fi

# --- Row u: self-only derivation demotes to unclassified and RUNS -----------------
# Remove a declared array in the sandbox lib so its suite derives self-only:
# the classifier must report `unclassified` (not edge:derived), and the run
# must SELECT it — fail toward coverage, and let the census flag the gap.
cases=$((cases + 1))
_sbn="$TESTROOT/sb-unclass/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "u: sandbox build"; }
python3 - "$(dirname "$_sbn")" <<'PY' || { fail "u: splice"; }
import sys, re
p = sys.argv[1] + "/lib/test-affected-paths.sh"
s = open(p).read()
s2 = re.sub(r'AFFECTED_TESTS_COMMANDS_SYNC_DOMAIN_MODEL_PATHS=\(.*?\n\)\n', '', s, count=1, flags=re.S)
assert s2 != s, "array not found"
open(p, 'w').write(s2)
PY
( cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD="$TESTROOT/rec-$cases" \
    'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
    bash "$_sbn" --affected ) > "$TESTROOT/out-$cases" 2>&1 || true
ARM_OUT="$(cat "$TESTROOT/out-$cases")"; ARM_RECORD="$(cat "$TESTROOT/rec-$cases")"
if grep -qF $'RAN\ttests/commands/sync-domain-model' <<<"$ARM_RECORD"; then
  pass "u: self-only-derived suite runs (unclassified selects, never declines)"
else
  fail "u: sync-domain-model did not run — $(grep -F 'sync-domain-model' <<<"$ARM_OUT" | head -2)"
fi
# and the receipt must say unclassified, not edge:derived
cases=$((cases + 1))
_ucls=$(cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$_sbn" --print-affected-set 2>/dev/null \
  | awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="tests/commands/sync-domain-model"{print $3}')
if [[ "$_ucls" == "unclassified" ]]; then
  pass "u2: self-only derivation reports unclassified (census-visible), not edge:derived"
else
  fail "u2: class='${_ucls:-<none>}' expected unclassified"
fi

# --- Row x: declared edges UNION with derived, never shadow ---------------------
# A declared array records what derivation could not reach AT WRITE TIME. If the
# suite later gains a derivable dependency — modelled here by splicing the suite
# file OUT of its declared array and diff-touching it — the suite must still
# select. Under the shadowing semantics this row replaces, it would decline:
# the declaration would hide the dependency the diff just reached.
cases=$((cases + 1))
_sbn="$TESTROOT/sb-union/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "x: sandbox build"; }
python3 - "$(dirname "$_sbn")" <<'PY' || { fail "x: splice"; }
import sys, re
p = sys.argv[1] + "/lib/test-affected-paths.sh"
s = open(p).read()
old = '  "tests/commands/test-sync-domain-model.sh"\n'
assert old in s, "self-edge line not found"
s2 = s.replace(old, '', 1)
open(p, 'w').write(s2)
PY
rc=0
( cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD="$TESTROOT/rec-$cases" \
    'SANDBOX_DIFF_NAMES=tests/commands/test-sync-domain-model.sh' \
    bash "$_sbn" --affected ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
ARM_OUT="$(cat "$TESTROOT/out-$cases")"; ARM_RECORD="$(cat "$TESTROOT/rec-$cases")"
_xcls=$(cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$_sbn" --print-affected-set 2>/dev/null \
  | awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="tests/commands/sync-domain-model"{print $3}')
if grep -qF $'RAN\ttests/commands/sync-domain-model' <<<"$ARM_RECORD" \
  && [[ "$_xcls" == "edge:declared" ]]; then
  pass "x: declared ∪ derived — diff to a derived-only path still selects (class=edge:declared)"
else
  fail "x: rc=$rc class='${_xcls:-<none>}' ran=$(grep -c 'sync-domain-model' <<<"$ARM_RECORD")"
fi

# --- Rows w: the unscoped untracked append --------------------------------------
# w1 is the source pin: under _AFFECTED the runner appends `git ls-files
# --others --exclude-standard` UNSCOPED — a brand-new suite file's self-edge and
# a new file under a declared prefix are otherwise invisible to the diff blob.
cases=$((cases + 1))
_untr_block="$(awk '/^if \(\( _AFFECTED == 1 \)\); then/{f=1} f&&/^fi$/{exit} f' "$RUNNER")"
if grep -qF 'git ls-files --others --exclude-standard 2>/dev/null' <<<"$_untr_block" \
  && ! grep -qE 'ls-files --others --exclude-standard --' <<<"$_untr_block"; then
  pass "w1: affected mode appends the UNSCOPED untracked list to _diff_names"
else
  fail "w1: unscoped untracked append missing or re-scoped under _AFFECTED"
fi

# w2 is the behaviour: a real untracked file under a declared directory prefix
# must select the suite that owns the prefix — while a declared suite the diff
# does not reach still declines. The probe lives in the REAL worktree for the
# duration of the arm (ls-files --others is a live git query); it is removed
# immediately after, before the next arm's diff is read.
cases=$((cases + 1))
_probe="knowledge-base/engineering/architecture/diagrams/zz-8322-untracked-probe.c4"
printf 'probe\n' > "$REPO_ROOT/$_probe"
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'SANDBOX_LIVE_UNTRACKED=1' \
  -- --affected
rm -f "$REPO_ROOT/$_probe"
if [[ "$ARM_RC" == "0" ]] \
  && grep -qF $'RAN\tplugins/soleur/test/c4-model-freshness.test.sh' <<<"$ARM_RECORD" \
  && ! grep -qF $'RAN\ttests/commands/sync-domain-model' <<<"$ARM_RECORD"; then
  pass "w2: untracked file under a declared prefix selects its suite; unreached declared suites still decline"
else
  fail "w2: rc=$ARM_RC c4=$(grep -c 'c4-model-freshness' <<<"$ARM_RECORD") sync=$(grep -c 'sync-domain-model' <<<"$ARM_RECORD")"
fi

# --- Rows v: lint-orphan-test-suites census mutations ----------------------------
# The census consumes the classification index fail-closed. Each arm builds a
# hardlinked repo sandbox (mutating the REAL lib would corrupt the worktree:
# cp -al links share inodes, so the row rm's the target before replacing it)
# and splices one staleness class into the lib copy. The linter must exit 1
# naming the lie — green behind a stale index is the failure mode these buy.
build_census_sandbox() { # $1 = dir
  local d="$1" item
  mkdir -p "$d/scripts"
  cp -al "$REPO_ROOT/scripts/." "$d/scripts/" 2>/dev/null \
    || cp -r "$REPO_ROOT/scripts/." "$d/scripts/"
  rm -f "$d/scripts/lib/test-affected-paths.sh"
  cp "$REPO_ROOT/scripts/lib/test-affected-paths.sh" "$d/scripts/lib/"
  for item in "$REPO_ROOT"/.[!.]* "$REPO_ROOT"/*; do
    [[ -e "$item" ]] || continue
    [[ "$(basename "$item")" == "scripts" ]] && continue
    ln -sfn "$item" "$d/$(basename "$item")"
  done
  printf '%s\n' "$d/scripts/lint-orphan-test-suites.sh"
}

cases=$((cases + 1))
_csv="$(build_census_sandbox "$TESTROOT/census-stale-alwayson")"
printf '\nALWAYS_ON_SUITES+=("zz-census-mutation-ghost")\n' \
  >> "$(dirname "$_csv")/lib/test-affected-paths.sh"
rc=0
( cd "$TESTROOT/census-stale-alwayson" && env $ENV_SCRUB \
    SOLEUR_DISABLE_SESSION_STATE=1 bash "$_csv" ) \
    > "$TESTROOT/out-$cases" 2>&1 || rc=$?
if [[ "$rc" != "0" ]] \
  && grep -qF "ALWAYS_ON_SUITES entry 'zz-census-mutation-ghost' is not a live registration" "$TESTROOT/out-$cases"; then
  pass "v1: stale ALWAYS_ON_SUITES entry fails the census, naming the entry"
else
  fail "v1: census rc=$rc — $(grep -c ERROR "$TESTROOT/out-$cases") ERROR line(s)"
fi

cases=$((cases + 1))
_csv="$(build_census_sandbox "$TESTROOT/census-stale-consumed")"
printf '\nAFFECTED_CONSUMED_EDGES+=("zz-ghost-label|AFFECTED_TESTS_COMMANDS_SYNC_DOMAIN_MODEL_PATHS")\n' \
  >> "$(dirname "$_csv")/lib/test-affected-paths.sh"
rc=0
( cd "$TESTROOT/census-stale-consumed" && env $ENV_SCRUB \
    SOLEUR_DISABLE_SESSION_STATE=1 bash "$_csv" ) \
    > "$TESTROOT/out-$cases" 2>&1 || rc=$?
if [[ "$rc" != "0" ]] \
  && grep -qF "AFFECTED_CONSUMED_EDGES names label 'zz-ghost-label', which is not a live registration" "$TESTROOT/out-$cases"; then
  pass "v2: stale consumed-edge mapping fails the census, naming the label"
else
  fail "v2: census rc=$rc — $(grep -c ERROR "$TESTROOT/out-$cases") ERROR line(s)"
fi

echo ""
# Conservation + floor: a truncated row block must not read as green.
if (( PASS + FAIL != cases )); then
  echo "[FATAL] verdict mismatch: PASS($PASS)+FAIL($FAIL) != cases($cases) — a row was skipped" >&2
  exit 2
fi
MIN_CASES=31
if (( cases < MIN_CASES )); then
  echo "[FATAL] only $cases cases ran — below the $MIN_CASES floor; a row block went missing" >&2
  exit 2
fi
echo "test-all-affected: $PASS passed, $FAIL failed of $((PASS + FAIL)) (cases=$cases)"
if (( FAIL > 0 )); then
  cat "$FAILLOG" >&2
  exit 1
fi
exit 0
