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
  cp "$REL_LIB" "$RWB_LIB" "$dir/lib/" || return 1
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
  ( cd "$REPO_ROOT" && env -u TEST_GROUP -u SCRIPTS_SHARD \
      SOLEUR_DISABLE_SESSION_STATE=1 SANDBOX_RECORD="$rec_f" \
      "${env_pairs[@]}" bash "$sb" "${argv[@]+"${argv[@]}"}" ) \
      > "$out_f" 2>&1 || rc=$?
  ARM_RC=$rc
  ARM_OUT="$(cat "$out_f")"
  ARM_RECORD="$(cat "$rec_f")"
  return 0
}

# Count of RAN records in the last arm. awk, not `grep '\t'` — GNU grep treats
# BRE `\t` as a literal 't' ("stray \ before t" warning), which reads as zero
# records and turns every ran-count assert fail-open.
ran_count() { awk -F'\t' '$1=="RAN"' <<<"$ARM_RECORD" | wc -l | tr -d ' '; }

# Runnable-registration count on the real stream, for "everything ran" asserts.
RUNNABLE_N=""
runnable_n() {
  if [[ -z "$RUNNABLE_N" ]]; then
    RUNNABLE_N=$(cd "$REPO_ROOT" && env -u TEST_GROUP -u SCRIPTS_SHARD \
      SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --enumerate-commands 2>/dev/null \
      | awk -F'\t' '$1=="SUITE_COMMAND"' | wc -l | tr -d ' ')
  fi
  printf '%s\n' "$RUNNABLE_N"
}

echo "== test-all-affected: mutation matrix =="

# --- Row a: --help ------------------------------------------------------------
cases=$((cases + 1))
rc=0
_help_out=$(env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 \
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
env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --affected --full >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "b: --affected --full exits 2"
else
  fail "b: --affected --full rc=$rc, expected 2"
fi

# --- Row c: trailing positional junk -> exit 2 ---------------------------------
cases=$((cases + 1))
rc=0
env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" all extra-positional >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "c: >1 positional exits 2"
else
  fail "c: trailing positional rc=$rc, expected 2"
fi

# --- Row d: --print-affected-set emits receipts for the runnable stream ---------
cases=$((cases + 1))
rc=0
_print_out=$(cd "$REPO_ROOT" && env -u TEST_GROUP -u SCRIPTS_SHARD \
  SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --affected --print-affected-set 2>/dev/null) || rc=$?
_receipts=$(awk -F'\t' '$1=="AFFECTED_CLASS"' <<<"$_print_out" | wc -l | tr -d ' ')
if [[ "$rc" == "0" ]] && (( _receipts >= $(runnable_n) )); then
  pass "d: print-affected-set emits ${_receipts} receipts (>= $(runnable_n) runnable)"
else
  fail "d: print rc=$rc receipts=${_receipts} runnable=$(runnable_n)"
fi

# --- Row e: receipts carry real classes — spot-check the census anchors ---------
cases=$((cases + 1))
_cls_lockfile=$(awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="scripts/lint-dual-lockfile"{print $3}' <<<"$_print_out" | head -1)
_cls_sentry=$(awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="tests/scripts/sentry-brownout-retry"{print $3}' <<<"$_print_out" | head -1)
_cls_unittest=$(awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="tests/scripts/lint-rule-ids"{print $3}' <<<"$_print_out" | head -1)
if [[ "$_cls_lockfile" == "always_on" && "$_cls_sentry" == "edge:declared" && "$_cls_unittest" == edge:* ]]; then
  pass "e: lint-dual-lockfile=always_on, sentry=edge:declared, unittest-mod=${_cls_unittest}"
else
  fail "e: lockfile='${_cls_lockfile:-<none>}' sentry='${_cls_sentry:-<none>}' unittest='${_cls_unittest:-<none>}'"
fi

# --- Row f: affected run declines untouched suites, keeps always-on -------------
# Force a diff touching only the sentry brownout workflow: its declared-edge
# suite must be selected; an unrelated edge suite must not; an always-on lint
# must still run.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  -- --affected
_rc=$ARM_RC
_ran=$(ran_count)
if [[ "$_rc" == "0" ]] \
  && grep -qF $'RAN\ttests/scripts/sentry-brownout-retry' <<<"$ARM_RECORD" \
  && grep -qF $'RAN\tscripts/lint-dual-lockfile' <<<"$ARM_RECORD" \
  && ! grep -qF $'RAN\ttests/scripts/registry-gate-mutation-battery' <<<"$ARM_RECORD" \
  && grep -qF 'not-affected' <<<"$ARM_OUT" \
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
if [[ "$_rc" == "0" ]] && (( _ran >= $(runnable_n) )) \
  && grep -qF 'MODE=full' <<<"$ARM_OUT"; then
  pass "g: --full runs all ${_ran} registrations regardless of diff"
else
  fail "g: --full rc=$_rc ran=${_ran} runnable=$(runnable_n)"
fi

# --- Row h: undecidable-diff arm degrades to full --------------------------------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DETECT_OK=0' 'SANDBOX_DIFF_NAMES=' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
if [[ "$_rc" == "0" ]] && (( _ran > 200 )) \
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
if [[ "$_rc" == "0" ]] && (( _ran > 200 )) \
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
if [[ "$_rc" == "0" ]] && (( _ran > 200 )) \
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
if [[ "$_rc" == "0" ]] && (( _ran > 200 )) \
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
( cd "$REPO_ROOT" && env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD=/dev/null 'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
    bash "$_sbn" --affected ) >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "4" ]]; then
  pass "o: below-live-floor selection refuses rc=4 (AFFECTED_UNRESOLVED)"
else
  fail "o: gutted always-on rc=$rc, expected 4"
fi

# --- Row p: FORCE_ALL + affected degrades to full -----------------------------------
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
  'SOLEUR_TEST_FORCE_ALL=1' \
  -- --affected
_rc=$ARM_RC; _ran=$(ran_count)
if [[ "$_rc" == "0" ]] && (( _ran > 200 )); then
  pass "p: FORCE_ALL under affected degrades to full"
else
  fail "p: FORCE_ALL+affected rc=$_rc ran=${_ran}"
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
_enum_n=$(cd "$REPO_ROOT" && env -u TEST_GROUP -u SCRIPTS_SHARD \
  SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --enumerate-commands 2>/dev/null \
  | awk -F'\t' '$1=="SUITE_COMMAND" || $1=="SUITE_COMMAND_DECLINED"' | wc -l | tr -d ' ') || rc=$?
if [[ "$rc" == "0" ]] && (( _enum_n >= 400 )); then
  pass "r: --enumerate-commands still emits the full stream (${_enum_n} records)"
else
  fail "r: enumerate rc=$rc records=${_enum_n}"
fi

echo ""
echo "test-all-affected: $PASS passed, $FAIL failed of $((PASS + FAIL)) (cases=$cases)"
if (( FAIL > 0 )); then
  cat "$FAILLOG" >&2
  exit 1
fi
exit 0
