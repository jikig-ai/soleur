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
#   asserts its absence. A fifth seam, SANDBOX_STAGED_NAMES (#9173), is
#   injected by build_sandbox INSIDE the runner's staged-scope branch
#   (anchored on the `diff --cached --name-status` line) — the placement is
#   intra-branch by design, since a post-assembly substitution cannot prove
#   the branch diff sources stayed dark under `--affected-scope=staged`: a
#   leak would land ON TOP of the substituted set. It is injected, never
#   shipped: an env-readable seam in the production runner is the only
#   SANDBOX_* hook that could NARROW a real run's diff.
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
ENV_SCRUB="-u TEST_GROUP -u SCRIPTS_SHARD -u CI -u SOLEUR_SUBAGENT -u SOLEUR_ALLOW_FULL_GATE -u SOLEUR_TEST_FORCE_ALL -u SOLEUR_INCIDENT_SKIP -u TC_RUNTIME_CEILING_S -u SOLEUR_ENUM_DEADLINE_S -u SECONDS -u SANDBOX_STAGED_NAMES"

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
  # Duration manifests the runner-changed banner sums. Absent by default (the banner
  # then says "duration unknown"); an arm that asserts the cost clause supplies a
  # synthetic directory so the expected minutes are a fixture fact, not a live number.
  if [[ -n "${SANDBOX_MANIFEST_DIR:-}" ]]; then
    cp "$SANDBOX_MANIFEST_DIR"/*.tsv "$dir/" || return 1
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
    '[[ -n "${SANDBOX_LIVE_UNTRACKED:-}" && "${_AFF_SCOPE:-branch}" != "staged" ]] && _diff_names="${_diff_names}\n$(git ls-files --others --exclude-standard 2>/dev/null)"\n'
    '[[ -n "${SANDBOX_DETECT_OK:-}" ]] && _diff_detect_ok="$SANDBOX_DETECT_OK"\n'
    '[[ -n "${SANDBOX_HEAD_OK:-}" ]] && _diff_head_ok="$SANDBOX_HEAD_OK"\n'
    '[[ -n "${SANDBOX_PREFIXES+x}" ]] && TEST_RELEVANCE_PREFIXES=($SANDBOX_PREFIXES)\n'
    + old
), 1)

# 1b. Staged-scope seam. Injected INSIDE the staged branch — anchored on the
#     `diff --cached --name-status` line — so a sandboxed runner substitutes
#     the index read at its own derivation point. Intra-branch placement is
#     load-bearing: a post-assembly substitution cannot prove the branch
#     sources below stayed dark under staged scope, because a leak would land
#     ON TOP of the substituted set (sc5/sc6 rely on that). A supplied staged
#     set stands in for a successful index read, so both detection arms set;
#     a real failure path is exercised through SANDBOX_DETECT_OK instead.
#     Never shipped inline — the shipped staged branch documents the anchor.
staged_anchor = '$(git -c core.quotePath=false diff --cached --name-status -M 2>/dev/null || true)"'
assert s.count(staged_anchor) == 1, f"expected exactly one staged -M anchor, found {s.count(staged_anchor)}"
s = s.replace(staged_anchor, staged_anchor + '''
  [[ -n "${SANDBOX_STAGED_NAMES+x}" ]] \\
    && { _diff_names="$SANDBOX_STAGED_NAMES"; _diff_detect_ok=1; _diff_head_ok=1; }''', 1)

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
    plugins/soleur/test/c4-model-freshness.test.sh|\\
    test/x-community|plugins/soleur) : ;;
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
  # Mutation hook (#9307 Guard 3): SANDBOX_MUT_OLD/SANDBOX_MUT_NEW replace ONE
  # exact line of the sandbox copy, and a mutation that did not land is rc 98
  # — a mutant that does not land reports the BASELINE, which reads as a pass.
  if [[ -n "${SANDBOX_MUT_OLD:-}" ]]; then
    SB="$sb" python3 - <<'PY' || { ARM_RC=98; ARM_OUT="mutation did not land"; ARM_RECORD=""; return 1; }
import os, sys
p = os.environ["SB"]
s = open(p).read()
old = os.environ["SANDBOX_MUT_OLD"]
new = os.environ["SANDBOX_MUT_NEW"]
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  fi
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
# Exact label match: `grep -qF $'RAN\tplugins/soleur'` is a PREFIX match and is also satisfied by
# `plugins/soleur/test/…` labels, so a row asserting one suite could pass on a sibling.
ran_exact() { awk -F'\t' -v l="$1" '$1=="RAN" && $2==l {f=1} END{exit !f}' <<<"$ARM_RECORD"; }

# Runnable-registration count for "everything ran" asserts. $1 = runner path —
# the REAL runner for row d's real-corpus receipt count, the trimmed SANDBOX
# copy for the arms (whose "everything" is the keep-list stream). Not memoized:
# every call site is a `$(…)` subshell, so a memo variable would never survive.
# $2 (optional) = the arm's SANDBOX_DIFF_NAMES. An arm that forces a diff MUST
# pass it: without it the enumerate reads the REAL branch diff, so a branch
# touching apps/web-platform/infra/ counts the infra runner the arm skips.
runnable_n() {
  (cd "$REPO_ROOT" && env $ENV_SCRUB \
    SOLEUR_DISABLE_SESSION_STATE=1 ${2+"SANDBOX_DIFF_NAMES=$2"} \
    bash "$1" --enumerate-commands 2>/dev/null) \
    | awk -F'\t' '$1=="SUITE_COMMAND"' | wc -l | tr -d ' '
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

# --- Rows k2-k4: the runner-changed banner and --help (RUNNER EDITS) ---------------
# The full-fallback arm must say WHAT happened, what it COSTS and how to PREVIEW or scope
# it: before this, a registration-only edit read as a bare MODE=full with no cost and no
# escape, which looks like a hang. k2 is the no-manifest arm, k3 pins the cost clause to a
# synthetic manifest (a hardcoded number cannot satisfy it), k4 the --help block.
_k_mode='[affected] MODE=full (degraded: runner-changed) — selection declines disabled; relevance declines still apply.'
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=scripts/test-all.sh' \
  -- --affected
if grep -qF 'this diff edits the runner' <<<"$ARM_OUT" \
   && grep -qF 'the battery is running in FULL' <<<"$ARM_OUT" \
   && grep -qF 'duration unknown, manifest unavailable' <<<"$ARM_OUT" \
   && grep -qF 'bash scripts/test-all.sh --print-selection' <<<"$ARM_OUT" \
   && grep -qF -- '--affected --affected-scope=staged' <<<"$ARM_OUT" \
   && grep -qF 'INDEX only' <<<"$ARM_OUT" \
   && grep -qF 'TEST_GROUP=affected is a different selector' <<<"$ARM_OUT" \
   && grep -qxF -- "$_k_mode" <<<"$ARM_OUT"; then
  pass "k2: the runner-changed banner states cause, preview and scope commands, and keeps the MODE=full line verbatim"
else
  fail "k2: banner missing a required clause; out: $(grep -F '[affected]' <<<"$ARM_OUT" | head -8)"
fi

cases=$((cases + 1))
_k3_dir="$TESTROOT/k3-manifests"; mkdir -p "$_k3_dir" || { echo "FATAL: k3 fixture dir" >&2; exit 2; }
assert_fixture_dir "$_k3_dir"
printf '# synthetic\nzz/a\t120000\tmeasured\nzz/b\t30000\tmeasured\n' > "$_k3_dir/suite-durations.tsv"
printf '# synthetic\nzz/c\t30000\tmeasured\n' > "$_k3_dir/suite-durations-heavy.tsv"
SANDBOX_MANIFEST_DIR="$_k3_dir" SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=scripts/test-all.sh' \
  -- --affected
# 120000 + 30000 + 30000 ms = 3 minutes exactly.
if grep -qF 'about 3 min of suite time at manifest weights, serial and uncontended' <<<"$ARM_OUT" \
   && ! grep -qF 'duration unknown' <<<"$ARM_OUT"; then
  pass "k3: the banner's N is the manifest sum (3 min for the synthetic 180000 ms)"
else
  fail "k3: cost clause wrong; out: $(grep -F 'battery is running' <<<"$ARM_OUT" | head -2)"
fi

cases=$((cases + 1))
_k4_out=$(env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --help 2>&1) || true
if grep -qF 'RUNNER EDITS' <<<"$_k4_out" \
   && grep -qF 'bash scripts/test-all.sh --print-selection' <<<"$_k4_out" \
   && grep -qF -- '--affected --affected-scope=staged' <<<"$_k4_out" \
   && grep -qF 'TEST_GROUP=affected is a DIFFERENT, heuristic selector' <<<"$_k4_out" \
   && grep -qF 'not an escape from the fallback' <<<"$_k4_out"; then
  pass "k4: --help carries the RUNNER EDITS block with the preview and staged-scope commands"
else
  fail "k4: --help lacks the RUNNER EDITS block"
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
# Splice a one-position shift into the sandbox's LABEL map only: the runtime
# label guard must notice the mismatch, drop _aff_sel, and run EVERYTHING —
# never apply another suite's selection bit. The selection bits stay aligned
# on purpose: under this diff most of them are 0, so a guard that printed
# AFFECTED_DIVERGENT but kept the map would decline suites and fail `==`.
cases=$((cases + 1))
_sbn="$TESTROOT/sb-divergent/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "t: sandbox build"; }
python3 - "$(dirname "$_sbn")" <<'PY' || { fail "t: splice"; }
import sys
p = sys.argv[1] + "/test-all.sh"
s = open(p).read()
old = '_aff_label[$_aff_ordinal]="${_aff_fields[1]}"'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, '_aff_label[$(( _aff_ordinal + 1 ))]="${_aff_fields[1]}"')
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
# The victim is dev-suite-mutex-wiring: tests/commands/sync-domain-model was the victim until D1 (#9307) made
# its `REPO_ROOT="$(cd ... /../.. && pwd)"` idiom resolve, which gave it real derived edges and so no longer a
# self-only derivation. Any victim must stay self-only WITHOUT its array; the row proves it by the class.
cases=$((cases + 1))
_sbn="$TESTROOT/sb-unclass/test-all.sh"
build_sandbox "$_sbn" with-lib >/dev/null || { fail "u: sandbox build"; }
python3 - "$(dirname "$_sbn")" <<'PY' || { fail "u: splice"; }
import sys, re
p = sys.argv[1] + "/lib/test-affected-paths.sh"
s = open(p).read()
s2 = re.sub(r'AFFECTED_TESTS_SCRIPTS_DEV_SUITE_MUTEX_WIRING_PATHS=\(.*?\n\)\n', '', s, count=1, flags=re.S)
assert s2 != s, "array not found"
open(p, 'w').write(s2)
PY
( cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    SANDBOX_RECORD="$TESTROOT/rec-$cases" \
    'SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml' \
    bash "$_sbn" --affected ) > "$TESTROOT/out-$cases" 2>&1 || true
ARM_OUT="$(cat "$TESTROOT/out-$cases")"; ARM_RECORD="$(cat "$TESTROOT/rec-$cases")"
if grep -qF $'RAN\ttests/scripts/dev-suite-mutex-wiring' <<<"$ARM_RECORD"; then
  pass "u: self-only-derived suite runs (unclassified selects, never declines)"
else
  fail "u: dev-suite-mutex-wiring did not run — $(grep -F 'dev-suite-mutex-wiring' <<<"$ARM_OUT" | head -2)"
fi
# and the receipt must say unclassified, not edge:derived
cases=$((cases + 1))
_ucls=$(cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$_sbn" --print-affected-set 2>/dev/null \
  | awk -F'\t' '$1=="AFFECTED_CLASS" && $2=="tests/scripts/dev-suite-mutex-wiring"{print $3}')
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

# --- Rows y/z: deleted-checkout fail-fast + enumerate watchdog (#8761) ----------
# The enumerate path previously carried no liveness check and no wall-clock
# bound: a worktree deleted mid-run left every git probe degrading to
# empty-but-zero output, so the walk either completed `exit 0` over a
# truncated receipt set or — on the incident tree — spun for hours. These arms
# pin the contract: deleted cwd => fast non-zero with the named error, and the
# enumerate family dies at the watchdog deadline even mid-iteration.
#
# The fixture is a REAL git worktree of a TESTROOT-local repo (the incident
# shape); the sandbox runner lives OUTSIDE the worktree so deleting it does
# not remove the script under test. assert_fixture_dir guards every rm -rf.
# Sets _WT/_SB globals — printing two paths space-separated would break under a
# whitespace TMPDIR and could truncate the path an arm then rm -rf's.
_wt_fixture() { # $1 = fixture root
  local d="$1"
  _WT=""; _SB=""
  git init -q "$d/repo" || return 1
  git -C "$d/repo" -c user.email=suite@example.com -c user.name=suite \
    commit -qm init --allow-empty || return 1
  git -C "$d/repo" worktree add -q --detach "$d/wt" HEAD || return 1
  build_sandbox "$d/sb/test-all.sh" with-lib >/dev/null || return 1
  _WT="$d/wt"; _SB="$d/sb/test-all.sh"
}

# Bounded wait for a backgrounded runner. `wait` blocks until the child exits
# (no kill -0 polling — an unreaped zombie child still answers kill -0); a
# marker-touching sleeper is the timeout arm, SIGKILLing the child so a wedged
# run cannot leak. Sets WAIT_RC to the child's rc, or 124 when the bound fired.
# MUST be called in the main shell — inside $( ) the subshell's jobs-table copy
# never learns the child's exit, so `wait` blocks until the bound fires and
# every read reports 124 (measured: the runner had already exited 4).
_wait_bound() { # $1 = pid, $2 = seconds, $3 = markerfile
  local _p="$1" _b="$2" _m="$3"
  rm -f "$_m"
  ( sleep "$_b"; : > "$_m"; kill -KILL "$_p" 2>/dev/null ) &
  local _k=$!
  WAIT_RC=0
  wait "$_p" 2>/dev/null || WAIT_RC=$?
  kill "$_k" 2>/dev/null
  wait "$_k" 2>/dev/null
  [[ -f "$_m" ]] && WAIT_RC=124
  return 0
}

# y1: mid-walk deletion. A `sleep` spliced after the ordinal tick widens the
# walk window deterministically; the deletion lands once the walk has started
# (first receipt observed) but cannot have finished (per-registration sleep).
cases=$((cases + 1))
_wtd="$TESTROOT/wtdel-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "y1: fixture build"
else
  python3 - "$_sb" <<'PY' || { fail "y1: splice"; }
import sys
p = sys.argv[1]
s = open(p).read()
old = '  _shard_ordinal=$(( _shard_ordinal + 1 ))'
assert s.count(old) == 1, f"ordinal tick anchor count={s.count(old)}"
s = s.replace(old, old + '\n  sleep 0.4', 1)
open(p, 'w').write(s)
PY
  ( cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$_sb" --print-affected-set ) > "$TESTROOT/out-$cases" 2>&1 &
  _wpid=$!
  # Wait for the walk to reach its first registration, then delete mid-walk.
  _d=0
  while (( _d < 100 )); do
    grep -q $'AFFECTED_CLASS\t' "$TESTROOT/out-$cases" 2>/dev/null && break
    kill -0 "$_wpid" 2>/dev/null || break
    sleep 0.1; _d=$(( _d + 1 ))
  done
  assert_fixture_dir "$_wt"
  rm -rf "$_wt"
  _wait_bound "$_wpid" 45 "$TESTROOT/bound-$cases"; rc=$WAIT_RC
  if [[ "$rc" == "124" ]]; then
    fail "y1: deleted-cwd run outlived the 45s bound (the incident shape)"
  elif [[ "$rc" == "4" ]] && grep -qF 'working tree missing' "$TESTROOT/out-$cases"; then
    pass "y1: mid-walk deletion exits rc=4 with the named error"
  else
    fail "y1: rc=$rc — want 4 + 'working tree missing' ($(tail -3 "$TESTROOT/out-$cases"))"
  fi
fi

# y2: launch with the cwd already deleted — the up-front guard, not the walk.
cases=$((cases + 1))
_wtd="$TESTROOT/wtpre-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "y2: fixture build"
else
  rc=0; _t0=$SECONDS
  ( cd "$_wt" && assert_fixture_dir "$_wt" && rm -rf "$_wt" && \
    env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$_sb" --print-affected-set ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
  _elapsed=$(( SECONDS - _t0 ))
  if [[ "$rc" == "4" ]] && (( _elapsed < 30 )) \
    && grep -qF 'working tree missing' "$TESTROOT/out-$cases"; then
    pass "y2: launch in a deleted cwd exits 4 in ${_elapsed}s"
  else
    fail "y2: rc=$rc elapsed=${_elapsed}s (want 4, fast, named error)"
  fi
fi

# y3: sibling flag spelling — the guard is mode-agnostic, so --enumerate must
# fail identically in a deleted cwd.
cases=$((cases + 1))
_wtd="$TESTROOT/wtpre-enum-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "y3: fixture build"
else
  rc=0
  ( cd "$_wt" && assert_fixture_dir "$_wt" && rm -rf "$_wt" && \
    env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$_sb" --enumerate ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
  if [[ "$rc" == "4" ]] && grep -qF 'working tree missing' "$TESTROOT/out-$cases"; then
    pass "y3: --enumerate in a deleted cwd exits 4 with the named error"
  else
    fail "y3: rc=$rc (want 4 + 'working tree missing')"
  fi
fi

# z1: the watchdog is the hard bound — a spin spliced at the TOP of
# _shard_selects (ahead of the liveness/deadline checks, so nothing else can
# end it) must die at SOLEUR_ENUM_DEADLINE_S + grace, printing the deadline.
cases=$((cases + 1))
_wtd="$TESTROOT/wtspin-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "z1: fixture build"
else
  python3 - "$_sb" <<'PY' || { fail "z1: splice"; }
import sys
p = sys.argv[1]
s = open(p).read()
old = '_shard_selects() {\n'
assert s.count(old) == 1, f"_shard_selects head count={s.count(old)}"
s = s.replace(old, old + '  while :; do :; done\n', 1)
open(p, 'w').write(s)
PY
  _t0=$SECONDS
  ( cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      SOLEUR_ENUM_DEADLINE_S=5 bash "$_sb" --print-affected-set ) \
      > "$TESTROOT/out-$cases" 2>&1 &
  _wpid=$!
  _wait_bound "$_wpid" 40 "$TESTROOT/bound-$cases"; rc=$WAIT_RC
  if [[ "$rc" == "124" ]]; then
    fail "z1: spliced spin outlived deadline+grace (40s)"
  else
    _elapsed=$(( SECONDS - _t0 ))
    if [[ "$rc" != "0" ]] && grep -qF 'enumerate deadline' "$TESTROOT/out-$cases"; then
      pass "z1: watchdog kills the spliced spin at ${_elapsed}s (rc=$rc)"
    else
      fail "z1: rc=$rc elapsed=${_elapsed}s out=$(tail -3 "$TESTROOT/out-$cases")"
    fi
  fi
fi

# z2: a non-numeric SOLEUR_ENUM_DEADLINE_S must normalize to the default and
# never abort the run under set -u/arithmetic.
cases=$((cases + 1))
_wtd="$TESTROOT/wtbadnum-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "z2: fixture build"
else
  rc=0
  ( cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      SOLEUR_ENUM_DEADLINE_S=not-a-number bash "$_sb" --print-affected-set ) \
      > "$TESTROOT/out-$cases" 2>&1 || rc=$?
  if [[ "$rc" == "0" ]]; then
    pass "z2: non-numeric SOLEUR_ENUM_DEADLINE_S normalizes; run completes"
  else
    fail "z2: rc=$rc (want 0) out=$(tail -3 "$TESTROOT/out-$cases")"
  fi
fi

# z3: must-PASS — an intact fixture worktree exits 0 with the full receipt
# count (derived programmatically, never hardcoded) and no guard/deadline line.
cases=$((cases + 1))
_wtd="$TESTROOT/wthealth-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "z3: fixture build"
else
  rc=0
  ( cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$_sb" --print-affected-set ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
  _receipts=$(awk -F'\t' '$1=="AFFECTED_CLASS"' "$TESTROOT/out-$cases" | wc -l | tr -d ' ')
  # Same-runner, same-mode baseline in the fixture's main checkout — receipt
  # counts, not SUITE_COMMAND records (a declined registration still emits an
  # AFFECTED_CLASS receipt, so runnable_n's record type miscounts here).
  _base_out=$(cd "$_wtd/repo" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$_sb" --print-affected-set 2>/dev/null) || true
  _want=$(awk -F'\t' '$1=="AFFECTED_CLASS"' <<<"$_base_out" | wc -l | tr -d ' ')
  if [[ "$rc" == "0" ]] && (( _receipts == _want && _want > 0 )) \
    && ! grep -qF 'working tree missing' "$TESTROOT/out-$cases" \
    && ! grep -qF 'enumerate deadline' "$TESTROOT/out-$cases"; then
    pass "z3: intact worktree exits 0 with full receipts (${_receipts}/${_want})"
  else
    fail "z3: rc=$rc receipts=${_receipts} want=${_want}"
  fi
fi

# z4: must-PASS — a cwd reached through a SYMLINKED path stays [[ -d ]]-true
# while the target lives: no false positive on the path-based probe.
cases=$((cases + 1))
_wtd="$TESTROOT/wtsymlink-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "z4: fixture build"
else
  ln -sfn "$_wt" "$TESTROOT/wtlink-$cases"
  rc=0
  ( cd "$TESTROOT/wtlink-$cases" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$_sb" --print-affected-set ) > "$TESTROOT/out-$cases" 2>&1 || rc=$?
  if [[ "$rc" == "0" ]] && ! grep -qF 'working tree missing' "$TESTROOT/out-$cases"; then
    pass "z4: symlinked cwd path completes clean (no false positive)"
  else
    fail "z4: rc=$rc — $(tail -3 "$TESTROOT/out-$cases")"
  fi
fi

# z5: pipe-EOF — a consumer reading the enumerate stream through $( ) must get
# EOF when the RUN exits, not when the disarmed watchdog's sleep would end. The
# runner's watchdog subshell spawns `sleep <deadline>` as a child; a disarm that
# kills only the subshell orphans the sleep holding the consumer's read pipe —
# the "process gone, consumer still waits" shape #8761 is about. Deadline is
# 900s, walk is seconds: a leaked sleep makes this arm take ~900s, not <120s.
cases=$((cases + 1))
_wtd="$TESTROOT/wtpipe-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "z5: fixture build"
else
  ( _cap=$(cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
        bash "$_sb" --print-affected-set 2>/dev/null)
    printf 'rc=%s\n' "$?" > "$TESTROOT/caprc-$cases"
    printf '%s' "$_cap" > "$TESTROOT/cap-$cases" ) &
  _wpid=$!
  _wait_bound "$_wpid" 120 "$TESTROOT/bound-$cases"; rc=$WAIT_RC
  if [[ "$rc" == "124" ]]; then
    fail "z5: $( ) consumer blocked past 120s — leaked watchdog child held the pipe"
  elif grep -qF 'rc=0' "$TESTROOT/caprc-$cases" \
    && grep -q $'AFFECTED_CLASS\t' "$TESTROOT/cap-$cases"; then
    pass "z5: $( ) consumer EOFs at run exit (not watchdog-lifetime)"
  else
    fail "z5: caprc=$(cat "$TESTROOT/caprc-$cases" 2>/dev/null || echo missing)"
  fi
fi

# z6: pipe-EOF on the ABNORMAL path — the mid-walk deletion exits the runner 4,
# but the watchdog subshell is still armed; if its sleep outlives the exit it
# holds this consumer's read pipe until the (default 900s) deadline. The EXIT
# trap's disarm is what makes the refusal actually fast end-to-end. Splices the
# same per-registration sleep as y1 so the deletion lands mid-walk.
cases=$((cases + 1))
_wtd="$TESTROOT/wtpipedel-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "z6: fixture build"
else
  python3 - "$_sb" <<'PY' || { fail "z6: splice"; }
import sys
p = sys.argv[1]
s = open(p).read()
old = '  _shard_ordinal=$(( _shard_ordinal + 1 ))'
assert s.count(old) == 1, f"ordinal tick anchor count={s.count(old)}"
s = s.replace(old, old + '\n  sleep 1', 1)
open(p, 'w').write(s)
PY
  # tee keeps the $( ) EOF semantics identical (its read-end still waits on
  # every upstream writer, leaked sleep included) while making the first
  # receipt observable — the deletion is polled, never a fixed offset that can
  # land before the watchdog arms or after the walk ends.
  ( _cap=$(cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
        bash "$_sb" --print-affected-set 2>/dev/null \
        | tee "$TESTROOT/live-$cases")
    printf 'rc=%s\n' "$?" > "$TESTROOT/caprc-$cases"
    printf '%s' "$_cap" > "$TESTROOT/cap-$cases" ) &
  _wpid=$!
  _seen=0
  for _i in $(seq 1 100); do
    if grep -q $'AFFECTED_CLASS\t' "$TESTROOT/live-$cases" 2>/dev/null; then _seen=1; break; fi
    sleep 0.1
  done
  assert_fixture_dir "$_wt"
  rm -rf "$_wt"
  _wait_bound "$_wpid" 60 "$TESTROOT/bound-$cases"; rc=$WAIT_RC
  if [[ "$rc" == "124" ]]; then
    fail "z6: $( ) consumer blocked past 60s on the exit-4 path — watchdog leaked"
  elif [[ -f "$TESTROOT/caprc-$cases" ]] \
    && grep -qF 'rc=4' "$TESTROOT/caprc-$cases" \
    && grep -qF 'working tree missing' "$TESTROOT/cap-$cases"; then
    pass "z6: deleted-cwd refusal EOFs a $( ) consumer promptly (rc=4)"
  else
    fail "z6: rc=$rc caprc=$(cat "$TESTROOT/caprc-$cases" 2>/dev/null || echo missing)"
  fi
fi

# y4: EXECUTING mode mid-walk deletion — the probe is mode-agnostic, but past
# the first registration a battery abort is exit 3 (coverage unresolved), not
# the enumerate refusal's 4. First RAN record proves the walk began; the
# summary marker must NOT appear (a truncated run never reaches it).
cases=$((cases + 1))
_wtd="$TESTROOT/wtexec-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "y4: fixture build"
else
  python3 - "$_sb" <<'PY' || { fail "y4: splice"; }
import sys
p = sys.argv[1]
s = open(p).read()
old = '  _shard_ordinal=$(( _shard_ordinal + 1 ))'
assert s.count(old) == 1, f"ordinal tick anchor count={s.count(old)}"
s = s.replace(old, old + '\n  sleep 1', 1)
open(p, 'w').write(s)
PY
  ( cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      SANDBOX_RECORD="$TESTROOT/ran-$cases" \
      bash "$_sb" > "$TESTROOT/out-$cases" 2>&1 ) &
  _wpid=$!
  for _i in $(seq 1 100); do
    grep -q '^RAN' "$TESTROOT/ran-$cases" 2>/dev/null && break
    sleep 0.1
  done
  assert_fixture_dir "$_wt"
  rm -rf "$_wt"
  _wait_bound "$_wpid" 60 "$TESTROOT/bound-$cases"; rc=$WAIT_RC
  if [[ "$rc" == "3" ]] \
    && grep -qF 'working tree missing' "$TESTROOT/out-$cases" \
    && ! grep -qF 'suites passed ===' "$TESTROOT/out-$cases"; then
    pass "y4: executing-mode mid-walk deletion exits 3, no summary marker"
  else
    fail "y4: rc=$rc (want 3, unresolved) out=$(tail -2 "$TESTROOT/out-$cases" 2>/dev/null | tr '\n' ' ')"
  fi
fi

# z7: the GRACEFUL per-registration deadline, isolated from the watchdog —
# the two share one bound, so a watchdog would race it; the splice no-ops the
# arm (`_ENUM_TOP_PID=$$` -> true leaves the subshell's kill -0 liveness loop
# empty → it exits immediately, unarmed). The 1s per-registration sleep walks
# the 6-label corpus past a 3s deadline at a registration boundary, where the
# graceful check exits 4 with the named error the signal-death path can't
# produce.
cases=$((cases + 1))
_wtd="$TESTROOT/wtgrace-$cases"
_wt=""; _sb=""
_wt_fixture "$_wtd" && { _wt="$_WT"; _sb="$_SB"; }
if [[ -z "$_wt" || -z "$_sb" ]]; then
  fail "z7: fixture build"
else
  python3 - "$_sb" <<'PY' || { fail "z7: splice"; }
import sys
p = sys.argv[1]
s = open(p).read()
tick = '  _shard_ordinal=$(( _shard_ordinal + 1 ))'
assert s.count(tick) == 1, f"tick count={s.count(tick)}"
s = s.replace(tick, tick + '\n  sleep 1', 1)
arm = '  _ENUM_TOP_PID=$$'
assert s.count(arm) == 1, f"arm count={s.count(arm)}"
s = s.replace(arm, '  true  # SANDBOX: watchdog unarmed — this arm tests the graceful layer', 1)
open(p, 'w').write(s)
PY
  _t0=$SECONDS
  rc=0
  _out=$(cd "$_wt" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
      SOLEUR_ENUM_DEADLINE_S=3 \
      bash "$_sb" --print-affected-set 2>&1) || rc=$?
  _elapsed=$(( SECONDS - _t0 ))
  if [[ "$rc" == "4" ]] && (( _elapsed < 30 )) \
    && grep -qF 'enumerate deadline exceeded' <<<"$_out" \
    && grep -qF 'registrations walked' <<<"$_out"; then
    pass "z7: graceful deadline exits 4 with named error (elapsed ${_elapsed}s)"
  else
    fail "z7: rc=$rc elapsed=${_elapsed}s out=$(tail -2 <<<"$_out" | tr '\n' ' ')"
  fi
fi

# --- z8: a live NON-git cwd fails open (advisor finding #6) ------------------
cases=$((cases + 1))
_ng_dir="$TESTROOT/non-git-cwd"
build_sandbox "$_ng_dir/test-all.sh" with-lib
_out=$(cd "$_ng_dir" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
    bash ./test-all.sh --enumerate 2>&1) || _ng_rc=$?
if [[ "${_ng_rc:-0}" == "0" ]] \
  && grep -q 'enumerate complete' <<<"$_out" \
  && ! grep -qF 'working tree missing' <<<"$_out"; then
  pass "z8: live non-git cwd fails open (enumerate complete, no refusal)"
else
  fail "z8: rc=${_ng_rc:-0} out=$(tail -3 <<<"$_out" | tr '\n' ' ')"
fi

# --- Rows sc: --affected-scope=staged (#9173) ---------------------------------
# The pre-commit gate's unit of work is the COMMIT: under staged scope the
# selection diff is the index (`git diff --cached`), the branch window is
# dark, and a staged runner/index path resolves to BOUNDED selection (self-
# edges + the unconditional always-on battery) under a loud note — never the
# full-corpus fallback that made ts commits unlandable on runner-diff
# branches. Branch scope keeps byte-identical behavior; rows a-z8 above are
# the regression net for that.

# sc1-sc3: flag mis-combinations exit 2 — the scope describes only the
# affected axes, so a --full ask, an unknown enum, or a non-affected
# TEST_GROUP must refuse rather than silently scope nothing.
cases=$((cases + 1))
rc=0
_out=$(env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --affected-scope=staged --full 2>&1) || rc=$?
# The token assertion matters as much as rc=2: an unrecognized flag ALSO
# exits 2 (it lands as a positional and dies on TEST_GROUP validation), so a
# bare-rc arm passes vacuously if the flag were never implemented — the
# scope-specific message is what pins the validation block itself.
if [[ "$rc" == "2" ]] && grep -qF 'cannot be combined with --full' <<<"$_out"; then
  pass "sc1: --affected-scope with --full exits 2 (scope-named error)"
else
  fail "sc1: --affected-scope=staged --full rc=$rc out=$(tail -2 <<<"$_out" | tr '\n' ' ')"
fi

cases=$((cases + 1))
rc=0
_out=$(env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --affected --affected-scope=bogus 2>&1) || rc=$?
if [[ "$rc" == "2" ]] && grep -qF 'must be one of: branch, staged' <<<"$_out"; then
  pass "sc2: unknown --affected-scope value exits 2 (enum error)"
else
  fail "sc2: --affected-scope=bogus rc=$rc out=$(tail -2 <<<"$_out" | tr '\n' ' ')"
fi

cases=$((cases + 1))
rc=0
_out=$(env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --affected-scope=staged scripts 2>&1) || rc=$?
if [[ "$rc" == "2" ]] && grep -qF 'different axis' <<<"$_out"; then
  pass "sc3: --affected-scope under a non-affected TEST_GROUP exits 2 (axis error)"
else
  fail "sc3: --affected-scope=staged scripts rc=$rc out=$(tail -2 <<<"$_out" | tr '\n' ' ')"
fi

# sc4: `--affected-scope=branch` is the default spelled out — accepted, runs.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=.github/workflows/tenant-integration.yml' \
  -- --affected --affected-scope=branch
if [[ "$ARM_RC" == "0" ]] && grep -qF 'MODE=affected' <<<"$ARM_OUT"; then
  pass "sc4: --affected-scope=branch accepted (identical to default)"
else
  fail "sc4: rc=$ARM_RC out=$(tail -3 <<<"$ARM_OUT" | tr '\n' ' ')"
fi

# sc5: the commit-scope gate. Staged set = two ts test files — the run must
# select their edged suites plus always-on ratchets, print the scope line,
# and fire NEITHER the full-corpus fallback NOR the runner-scope note (no
# runner/index path is staged). Two staged paths also pin that a second
# staged file is unioned, not shadowed (Guard 1 row 3).
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_STAGED_NAMES=tests/commands/test-sync-domain-model.sh\nplugins/soleur/test/c4-model-freshness.test.sh' \
  -- --affected --affected-scope=staged
if [[ "$ARM_RC" == "0" ]] \
  && grep -qF 'AFFECTED_SCOPE' <<<"$ARM_OUT" \
  && grep -qF 'scope=staged' <<<"$ARM_OUT" \
  && grep -qF $'RAN\ttests/commands/sync-domain-model' <<<"$ARM_RECORD" \
  && grep -qF $'RAN\tplugins/soleur/test/c4-model-freshness.test.sh' <<<"$ARM_RECORD" \
  && grep -qF $'RAN\tscripts/lint-dual-lockfile' <<<"$ARM_RECORD" \
  && ! grep -qF 'AFFECTED_FALLBACK' <<<"$ARM_OUT" \
  && ! grep -qF 'AFFECTED_RUNNER_IN_SCOPE' <<<"$ARM_OUT"; then
  pass "sc5: staged ts selects edged+always-on — no fallback, no runner-scope note"
else
  fail "sc5: rc=$ARM_RC ran=$(ran_count) markers=$(grep -cE 'AFFECTED_' <<<"$ARM_OUT")"
fi

# sc6: a staged runner/index path resolves to BOUNDED selection under a loud
# note — the runner's own always-on battery still runs, unedged suites still
# decline, and _aff_fallback stays empty so the run never degrades to the
# full corpus.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_STAGED_NAMES=scripts/test-all.sh' \
  -- --affected --affected-scope=staged
if [[ "$ARM_RC" == "0" ]] \
  && grep -qF 'AFFECTED_RUNNER_IN_SCOPE' <<<"$ARM_OUT" \
  && ! grep -qF 'AFFECTED_FALLBACK' <<<"$ARM_OUT" \
  && grep -qF $'RAN\tscripts/lint-dual-lockfile' <<<"$ARM_RECORD" \
  && grep -qF $'RAN\ttests/scripts/registry-gate-mutation-battery' <<<"$ARM_RECORD" \
  && ! grep -qF $'RAN\ttests/commands/sync-domain-model' <<<"$ARM_RECORD"; then
  # ADR-262: scripts/test-all.sh is now a gate-machinery edge of every --pr-gated battery
  # (PR_GATE_MACHINERY_PATHS), so the registry battery is SELECTED here; it was the "unedged suite"
  # this row used to assert declined, and tests/commands/sync-domain-model still plays that role.
  pass "sc6: staged runner path → bounded selection + runner-in-scope note"
else
  fail "sc6: rc=$ARM_RC ran=$(ran_count) markers=$(grep -cE 'AFFECTED_' <<<"$ARM_OUT")"
fi

# sc7: a staged-diff detection failure still degrades to the full battery —
# the fail-safe direction is unchanged under staged scope.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_STAGED_NAMES=tests/commands/test-sync-domain-model.sh' \
  'SANDBOX_DETECT_OK=0' \
  -- --affected --affected-scope=staged
_rc=$ARM_RC; _ran=$(ran_count)
_decl=$(grep -c "^\\[skip\\]" <<<"$ARM_OUT" | tr -d " ")
if [[ "$_rc" == "0" ]] && (( _ran + _decl >= $(runnable_n "$ARM_SB") )) \
  && grep -qF 'AFFECTED_FALLBACK' <<<"$ARM_OUT" \
  && grep -qF 'undecidable-diff' <<<"$ARM_OUT" \
  && ! grep -qF 'AFFECTED_RUNNER_IN_SCOPE' <<<"$ARM_OUT"; then
  pass "sc7: staged-diff detection failure degrades to full (undecidable-diff)"
else
  fail "sc7: rc=$_rc ran=${_ran} decl=${_decl} runnable=$(runnable_n "$ARM_SB")"
fi

# sc8: TEST_GROUP=affected (the heuristic axis) scopes its diff the same way
# — the flag is valid on either affected axis.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_STAGED_NAMES=tests/commands/test-sync-domain-model.sh' \
  'TEST_GROUP=affected' \
  -- --affected-scope=staged
if [[ "$ARM_RC" == "0" ]] \
  && grep -qF 'AFFECTED_SCOPE' <<<"$ARM_OUT" \
  && grep -qF $'RAN\ttests/commands/sync-domain-model' <<<"$ARM_RECORD"; then
  pass "sc8: TEST_GROUP=affected + staged flag scopes the heuristic axis"
else
  fail "sc8: rc=$ARM_RC ran=$(ran_count) out=$(tail -3 <<<"$ARM_OUT" | tr '\n' ' ')"
fi

# --- sc9: the staged branch of the assembly really reads the INDEX ---------
# The SANDBOX_* seams substitute names, never the invocation — so this arm
# pins the WIRE, not the artifact (the same real-state technique the infra
# suite's assembly arm uses): extract the real assembly, evaluate it inside a
# scratch repo carrying one staged file, one committed-ahead-of-origin file,
# and one untracked file UNDER A RELEVANCE PREFIX (scripts/, so the scoped
# untracked append would reach it), and assert the staged blob holds exactly
# the index. The extraction covers the unscoped appends too — a dropped
# staged guard on ANY append must show up here.
#
# TWO HARSHNESS DETAILS, both caught by the architecture seat (#9197):
# - the eval unsets the runner's full 9-name GIT_* list, not just GIT_DIR:
#   this suite is always-on, so it runs inside the lefthook bun-test hook
#   itself — where lefthook injects GIT_INDEX_FILE/GIT_WORK_TREE and the
#   eval'd `git diff --cached` would read the bookkeeping index instead of
#   the scratch repo's;
# - the branch-scope eval is the non-vacuity arm: the same extraction under
#   unset _AFF_SCOPE MUST show the untracked/branch fixtures, proving the
#   staged-darkness assertion discriminates rather than measuring an empty
#   channel.
cases=$((cases + 1))
REAL_REPO="$TESTROOT/realstate-staged"
mkdir -p "$REAL_REPO"
# The fixture BUILD unset the whole GIT_* prefix before any git op — this
# suite is always-on, so it runs inside the very lefthook hook that injects
# GIT_INDEX_FILE/GIT_WORK_TREE/GIT_DIR. Under that env an unscrubbed
# `git add`/`git commit`/`git update-ref` inside the scratch repo lands on
# the LIVE index and refs (data-loss class #7772/#7835 — 16 stray commits
# measured on a live branch). The prefix sweep (${!GIT_@}) is used instead
# of the runner's named 9-name list because a named list went stale within
# a day in a prior incident — same reason the eval's scrub was widened.
if (
  set -e
  for _v in "${!GIT_@}"; do unset "$_v"; done
  cd "$REAL_REPO"
  git init -q -b main .
  git config user.email t@t; git config user.name t
  echo base > base.txt
  mkdir -p scripts
  echo tracked > scripts/tracked-unstaged-fixture.sh
  echo torename > to-rename-fixture.sh
  git add -A && git commit -q -m base
  git update-ref refs/remotes/origin/main HEAD
  echo x > branch-only-fixture.sh
  git add -A && git commit -q -m ahead
  echo y > staged-fixture.test.ts
  git add staged-fixture.test.ts
  git mv to-rename-fixture.sh renamed-fixture.sh
  echo more >> scripts/tracked-unstaged-fixture.sh   # tracked, modified, UNSTAGED
  echo z > scripts/untracked-fixture.test.sh         # untracked, relevance-prefixed
) >/dev/null 2>&1; then
  _staged_asm="$TESTROOT/assembly-staged.sh"
  # Range ends at the _diff_touches comment, covering ALL diff sources —
  # staged branch, both branch arms, the rename pair, and all three
  # untracked appends (scoped + both unscoped).
  awk '/^_diff_detect_ok=0$/,/^# Does this run'"'"'s diff/' "$RUNNER" > "$_staged_asm"
  # Env-read pin (#9197 security seat): the shipped runner must contain NO
  # `${SANDBOX_STAGED_NAMES+x}` read — the seam exists only in sandbox copies
  # (build_sandbox §1b). Anchored on the +x expansion form, not the bare name,
  # because the shipped staged branch's comment documents the anchor in
  # prose — a bare-token grep would match the comment and pin nothing.
  _asm_gits=$(grep -c 'git ' "$_staged_asm")
  if grep -qF 'SANDBOX_STAGED_NAMES+x' "$RUNNER"; then
    fail "sc9: SANDBOX_STAGED_NAMES env-read found in the shipped runner — the seam must be injected, never shipped"
  elif ! grep -qF 'diff --cached' "$_staged_asm" || (( _asm_gits < 6 )); then
    fail "sc9: assembly extraction missing the staged branch (diff --cached absent or truncated: ${_asm_gits} git lines)"
  else
    _staged_eval=$(cd "$REAL_REPO" && (
      for _v in "${!GIT_@}"; do unset "$_v"; done
      bash -c "
        source '$REPO_ROOT/scripts/lib/test-relevance-paths.sh'
        _AFF_SCOPE=staged; _AFFECTED=1; TEST_GROUP=affected
        $(cat "$_staged_asm")
        printf '%s\nDETECT=%s HEAD=%s\n' \"\$_diff_names\" \"\$_diff_detect_ok\" \"\$_diff_head_ok\""
    ) 2>/dev/null || true)
    _branch_eval=$(cd "$REAL_REPO" && (
      for _v in "${!GIT_@}"; do unset "$_v"; done
      bash -c "
        source '$REPO_ROOT/scripts/lib/test-relevance-paths.sh'
        _AFFECTED=1; TEST_GROUP=affected
        $(cat "$_staged_asm")
        printf '%s\nDETECT=%s HEAD=%s\n' \"\$_diff_names\" \"\$_diff_detect_ok\" \"\$_diff_head_ok\""
    ) 2>/dev/null || true)
    # Detection-failure wiring: eval the same extraction in a non-repo dir —
    # `git diff --cached` fails, so a correctly-wired staged branch leaves
    # BOTH detection arms 0 (the undecidable-diff fail-safe direction).
    # _AFFECTED/TEST_GROUP are bound (to their non-affected values), not left
    # unset: SHELLOPTS exports `nounset` into every `bash -c` child, and the
    # extracted range contains `(( _AFFECTED == 1 ))` — an unbound read aborts
    # the child BEFORE the printf and this leg would measure an empty string.
    _norepo_eval=$(cd "$TESTROOT" && (
      for _v in "${!GIT_@}"; do unset "$_v"; done
      bash -c "
        source '$REPO_ROOT/scripts/lib/test-relevance-paths.sh'
        _AFF_SCOPE=staged; _AFFECTED=0; TEST_GROUP=all
        $(cat "$_staged_asm")
        printf 'DETECT=%s HEAD=%s\n' \"\$_diff_detect_ok\" \"\$_diff_head_ok\""
    ) 2>/dev/null || true)
    # The `to-rename-fixture.sh` assert pins the rename SOURCE, not only the
    # destination: `--name-only` alone emits `renamed-fixture.sh`; only the
    # `--name-status -M` append under staged scope carries the R100 old path.
    if grep -qF 'staged-fixture.test.ts' <<<"$_staged_eval" \
      && grep -qF 'renamed-fixture.sh' <<<"$_staged_eval" \
      && grep -qF 'to-rename-fixture.sh' <<<"$_staged_eval" \
      && ! grep -qF 'branch-only-fixture.sh' <<<"$_staged_eval" \
      && ! grep -qF 'tracked-unstaged-fixture.sh' <<<"$_staged_eval" \
      && ! grep -qF 'untracked-fixture.test.sh' <<<"$_staged_eval" \
      && grep -qF 'branch-only-fixture.sh' <<<"$_branch_eval" \
      && grep -qF 'tracked-unstaged-fixture.sh' <<<"$_branch_eval" \
      && grep -qF 'untracked-fixture.test.sh' <<<"$_branch_eval" \
      && grep -qF 'DETECT=1 HEAD=1' <<<"$_staged_eval" \
      && grep -qF 'DETECT=0 HEAD=0' <<<"$_norepo_eval"; then
      pass "sc9: staged scope reads the index — branch window, unstaged mods, and untracked set dark; rename rows + detection wiring verified"
    else
      fail "sc9: blobs drifted — staged{staged=$(grep -c staged-fixture <<<"$_staged_eval") rename=$(grep -c renamed-fixture <<<"$_staged_eval") branch=$(grep -c branch-only <<<"$_staged_eval") unstaged=$(grep -c tracked-unstaged <<<"$_staged_eval") untracked=$(grep -c untracked-fixture <<<"$_staged_eval") det=$(grep -o 'DETECT=[0-9] HEAD=[0-9]' <<<"$_staged_eval" | head -1)} branch-eval{branch=$(grep -c branch-only <<<"$_branch_eval") unstaged=$(grep -c tracked-unstaged <<<"$_branch_eval") untracked=$(grep -c untracked-fixture <<<"$_branch_eval")} norepo{$(grep -o 'DETECT=[0-9] HEAD=[0-9]' <<<"$_norepo_eval" | head -1)}"
    fi
  fi
else
  fail "sc9: real-state scratch repo could not be built"
fi

# --- Rows t1-t10 + m1-m3,m5,m7,m8 + t11/m9 + f1: anchored edges (#9307, Guard 3) -----
# (The `m` ids repeat the earlier contention rows' ids; every failure message carries its row text.)
# A derived edge that is a DIRECTORY is a path PREFIX, matched at the start of a
# diff line; a FILE edge is an exact line. The bare command word `test` in
# `bun test <file>` resolves to the repo-root `test/` directory, and as a
# substring it selected every suite carrying it for any diff path that merely
# CONTAINED "test" — a knowledge-base-only diff included. `test/x-community`
# (argv `bun test test/x-community.test.ts`) and `plugins/soleur`
# (`bun test plugins/soleur/`) are the two sandbox labels that carry it.
#
# t1: a path that merely contains "test" (a spec directory named *-test-*) must
#     not select a root-`test/` suite.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=knowledge-base/project/specs/feat-x-test-y/spec.md' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] \
  && ! ran_exact 'test/x-community' \
  && ! ran_exact 'plugins/soleur' \
  && ran_exact 'scripts/lint-dual-lockfile'; then
  pass "t1: a path merely containing 'test' selects no root test/ suite (always-on still ran)"
else
  fail "t1: rc=$_rc ran=$(ran_count) — $(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t2: positive control — the suite's own file selects it.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/x-community.test.ts' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] && ran_exact 'test/x-community'; then
  pass "t2: test/x-community.test.ts selects test/x-community"
else
  fail "t2: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t3: a NESTED test/ directory is not the root test/ directory.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=apps/web-platform/test/z.ts' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] \
  && ! ran_exact 'test/x-community' \
  && ran_exact 'scripts/lint-dual-lockfile'; then
  pass "t3: apps/web-platform/test/z.ts does not select the root test/ suite"
else
  fail "t3: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t4: a real directory edge still selects on a path under it.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=plugins/soleur/skills/x/SKILL.md' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] && ran_exact 'plugins/soleur'; then
  pass "t4: a path under plugins/soleur/ selects the plugins/soleur suite"
else
  fail "t4: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t5: a directory edge is a prefix of the diff line, not a fragment of it.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=knowledge-base/plugins/soleur/notes.md' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] \
  && ! ran_exact 'plugins/soleur' \
  && ran_exact 'scripts/lint-dual-lockfile'; then
  pass "t5: knowledge-base/plugins/soleur/notes.md does not select plugins/soleur"
else
  fail "t5: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t6: a second diff line is still matched after a non-matching first line.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_DIFF_NAMES=knowledge-base/a.md\ntest/x-community.test.ts' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] && ran_exact 'test/x-community'; then
  pass "t6: the second diff line selects the suite after a non-matching first line"
else
  fail "t6: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t7: a runner SUBCOMMAND is not an operand. `bun test <file>` must not mint the
#     repo-root test/ directory as an edge: a diff that touches some OTHER file
#     under test/ selects neither test/x-community nor plugins/soleur.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/some-unrelated.test.ts' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] \
  && ! ran_exact 'test/x-community' \
  && ! ran_exact 'plugins/soleur' \
  && ran_exact 'scripts/lint-dual-lockfile'; then
  pass "t7: a path under test/ that no suite names selects no bun-test suite (subcommand is not an edge)"
else
  fail "t7: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t8: a RENAME SOURCE selects. `git diff --name-only` lists only the destination of a rename,
#     so the old path reaches the diff blob only inside the `--name-status -M` row
#     `R100<TAB>old<TAB>new`. A FILE edge must match that old path exactly.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_DIFF_NAMES=elsewhere/x-community.test.ts\nR100\ttest/x-community.test.ts\telsewhere/x-community.test.ts' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] && ran_exact 'test/x-community'; then
  pass "t8: moving a file out from under a file edge (R100 old<TAB>new) still selects the suite"
else
  fail "t8: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t9: the same for a DIRECTORY edge — a file moved out of plugins/soleur/ selects the suite
#     that guards that directory, though no diff line begins with the old path.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_DIFF_NAMES=elsewhere/a/SKILL.md\nR100\tplugins/soleur/skills/a/SKILL.md\telsewhere/a/SKILL.md' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] && ran_exact 'plugins/soleur'; then
  pass "t9: moving a file out of a directory edge (R100 old<TAB>new) still selects the suite"
else
  fail "t9: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# t10: git C-quotes a path with a non-ASCII byte, `"` or `\`: the line arrives wrapped in `"…"`.
#      The wrapper must not hide a directory prefix from an anchored edge.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_DIFF_NAMES="plugins/soleur/caf\\303\\251.md"' \
  -- --affected
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] && ran_exact 'plugins/soleur'; then
  pass "t10: a git-quoted path under a directory edge still selects the suite"
else
  fail "t10: rc=$_rc ran=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | tr '\n' ' ')"
fi

# m1-m3: each mutant rewrites ONE line of the sandbox runner and must be
# DETECTED — the row's scenario must produce the verdict the un-mutated runner
# would have failed. A mutation that did not land is rc 98 and fails the row.
#
# m1: directory edges revert to the legacy SLASH-LESS substring match — t5's
#     scenario must now select plugins/soleur, the false positive anchoring removes.
cases=$((cases + 1))
SANDBOX_MUT_OLD='    */) [[ "$_n" == *"${_NL}${e}"* ]] ;;' \
SANDBOX_MUT_NEW='    */) [[ "$_n" == *"${e%/}"* ]] ;;' \
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=knowledge-base/plugins/soleur/notes.md' \
  -- --affected
if [[ "$ARM_RC" != "98" ]] && ran_exact 'plugins/soleur'; then
  pass "m1: substring-match mutant selects plugins/soleur on knowledge-base/plugins/soleur/ (t5 detects it)"
else
  fail "m1: rc=$ARM_RC — $ARM_OUT"
fi

# m2: the anchored branch never matches (the guard's own dispatch is dead) —
#     t2's positive scenario must now fail to select.
cases=$((cases + 1))
SANDBOX_MUT_OLD='        if _diff_edge_hit "${p#^}"; then return 0; fi' \
SANDBOX_MUT_NEW='        if false; then return 0; fi' \
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/x-community.test.ts' \
  -- --affected
if [[ "$ARM_RC" == "0" ]] \
  && ran_exact 'scripts/lint-dual-lockfile' \
  && ! ran_exact 'test/x-community'; then
  pass "m2: dead-dispatch mutant fails to select test/x-community (t2 detects it)"
else
  fail "m2: rc=$ARM_RC — $ARM_OUT"
fi

# m3: only the FIRST diff line is considered — t6's scenario must now miss.
cases=$((cases + 1))
SANDBOX_MUT_OLD='    _DEH_N="${_NL}${_diff_names//$'"'"'\t'"'"'/${_NL}}${_NL}"' \
SANDBOX_MUT_NEW='    _DEH_N="${_NL}${_diff_names%%${_NL}*}${_NL}"' \
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_DIFF_NAMES=knowledge-base/a.md\ntest/x-community.test.ts' \
  -- --affected
if [[ "$ARM_RC" == "0" ]] \
  && ran_exact 'scripts/lint-dual-lockfile' \
  && ! ran_exact 'test/x-community'; then
  pass "m3: first-line-only mutant misses the second diff line (t6 detects it)"
else
  fail "m3: rc=$ARM_RC — $ARM_OUT"
fi

# m5: the subcommand skip never fires — t7's scenario must now select the
#     bun-test suites through the resurrected bare `test` edge.
cases=$((cases + 1))
SANDBOX_MUT_OLD='    "bun test"|"npm test"|"pnpm test"|"yarn test"|"go test"|"cargo test"|"deno test"|"make test"|"run test")' \
SANDBOX_MUT_NEW='    "bun NEVER"|"npm test"|"pnpm test"|"yarn test"|"go test"|"cargo test"|"deno test"|"make test"|"run test")' \
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/some-unrelated.test.ts' \
  -- --affected
if [[ "$ARM_RC" != "98" ]] && ran_exact 'plugins/soleur'; then
  pass "m5: dead-skip mutant selects plugins/soleur via the bare test edge (t7 detects it)"
else
  fail "m5: rc=$ARM_RC — $ARM_OUT"
fi

# m7: the TAB split never happens (the blob is read as plain lines) — t8's rename scenario
#     must now miss, because the old path only exists inside the R100 row.
cases=$((cases + 1))
SANDBOX_MUT_OLD='    _DEH_N="${_NL}${_diff_names//$'"'"'\t'"'"'/${_NL}}${_NL}"' \
SANDBOX_MUT_NEW='    _DEH_N="${_NL}${_diff_names}${_NL}"' \
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_DIFF_NAMES=elsewhere/x-community.test.ts\nR100\ttest/x-community.test.ts\telsewhere/x-community.test.ts' \
  -- --affected
if [[ "$ARM_RC" == "0" ]] \
  && ran_exact 'scripts/lint-dual-lockfile' \
  && ! ran_exact 'test/x-community'; then
  pass "m7: no-TAB-split mutant misses the rename source (t8 detects it)"
else
  fail "m7: rc=$ARM_RC — $ARM_OUT"
fi

# m8: the C-quote unwrap is dropped — t10's quoted path must now miss the directory prefix.
cases=$((cases + 1))
SANDBOX_MUT_OLD='    _DEH_N="${_DEH_N//${_NL}\"/${_NL}}"' \
SANDBOX_MUT_NEW='    _DEH_N="${_DEH_N}"' \
SANDBOX_LIB=with-lib run_arm \
  $'SANDBOX_DIFF_NAMES="plugins/soleur/caf\\303\\251.md"' \
  -- --affected
if [[ "$ARM_RC" == "0" ]] \
  && ran_exact 'scripts/lint-dual-lockfile' \
  && ! ran_exact 'plugins/soleur'; then
  pass "m8: no-unwrap mutant misses a git-quoted path (t10 detects it)"
else
  fail "m8: rc=$ARM_RC — $ARM_OUT"
fi

# t11 / m9: edge MINTING. A directory token written WITHOUT a trailing "/" (22 declared entries,
#     `.github/workflows`, `scripts/lib`, ...) must become a prefix edge `^dir/`; a file stays an
#     exact `^file`; a `.`-rooted token keeps the legacy unanchored form. Driven on the runner's
#     own `_affected_add_edge` (extracted verbatim, no sandbox), so the sandbox rows -- whose
#     tokens all end in "/" -- cannot hide a dropped normalisation. m9 deletes the `-d`
#     normalisation and must change t11's directory answer.
cases=$((cases + 1))
_edge_src=$(awk '/^_affected_in_list\(\) \{/{f=1} f{print} f && /^_affected_add_edge\(\) \{/{g=1} g && /^\}/{exit}' "$RUNNER")
_edge_run() { ( cd "$REPO_ROOT" && eval "$1" && _AC_EDGES=() && _affected_add_edge "$2" && printf '%s' "${_AC_EDGES[*]}" ); }
_t11_dir=$(_edge_run "$_edge_src" scripts/lib)
_t11_file=$(_edge_run "$_edge_src" scripts/test-all.sh)
_t11_dot=$(_edge_run "$_edge_src" ./scripts)
if [[ -n "$_edge_src" && "$_t11_dir" == "^scripts/lib/" && "$_t11_file" == "^scripts/test-all.sh" && "$_t11_dot" == "./scripts" ]]; then
  pass "t11: a slash-less directory token is minted as ^dir/, a file as ^file, a ./-rooted token stays unanchored"
else
  fail "t11: dir='${_t11_dir}' file='${_t11_file}' dot='${_t11_dot}' src=${#_edge_src}B"
fi

cases=$((cases + 1))
_mut_src=$(python3 -c '
import sys
s = sys.stdin.read()
old = "if [[ -d \"$_p\" ]]; then _p=\"${_p%/}/\"; fi"
assert s.count(old) == 1, s.count(old)
sys.stdout.write(s.replace(old, ":"))
' <<<"$_edge_src") || _mut_src=""
_m9_dir=$(_edge_run "$_mut_src" scripts/lib)
if [[ -n "$_mut_src" && "$_mut_src" != "$_edge_src" && "$_m9_dir" == "^scripts/lib" ]]; then
  pass "m9: dropping the directory normalisation mints ^scripts/lib (no slash), which t11 rejects"
else
  fail "m9: landed=$([[ "$_mut_src" != "$_edge_src" ]] && echo yes || echo no) dir='${_m9_dir}'"
fi

# f1: the always-on ratchet floor is a PINNED value, the declared list still meets it, and the floor has not fallen
#     behind the list: the plan's rule is "floor = count - 5", so a list that grew by more than the slack without the
#     floor following (116 against 139 went unnoticed) fails here. Row `o` guts the list to one label, which refuses for
#     ANY floor >= 2, so it cannot tell 141 from 2. Raising the floor is a deliberate edit to this row AND the runner.
cases=$((cases + 1))
_f1_floor=$(sed -n 's/^_MIN_ALWAYS_ON_DECLARED=\([0-9][0-9]*\)$/\1/p' "$RUNNER")
# shellcheck source=/dev/null
_f1_count=$( ( source "$AFF_LIB" >/dev/null 2>&1; echo "${#ALWAYS_ON_SUITES[@]}" ) )
if [[ "$_f1_floor" == "141" && "$_f1_count" =~ ^[0-9]+$ ]] && (( _f1_count >= _f1_floor && _f1_count - _f1_floor <= 5 )); then
  pass "f1: _MIN_ALWAYS_ON_DECLARED is pinned at 141 and ALWAYS_ON_SUITES ($_f1_count) meets it within the slack of 5"
else
  fail "f1: floor='${_f1_floor}' (want 141) always-on count='${_f1_count}' (need floor <= count <= floor + 5; move the floor to count - 5 here and in the runner together)"
fi

# --- Rows p1-p6 + m4: --print-selection (#9307) -------------------------------------
# `--print-affected-set` prints each registration's CLASS and ignores the diff; it
# was read as a selection once and reported 306 "selected" for a diff that selects
# ~150. `--print-selection` runs the SAME pre-pass a real run applies and prints
# what THIS diff selects, without running a suite.
#
# p1: rows and summary for a forced diff. Sandbox corpus = 6 runnable labels.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/x-community.test.ts' \
  -- --print-selection
_rc=$ARM_RC
_sel_yes=$(awk -F'\t' '$1=="AFFECTED_SELECTED" && $3=="1"{print $2}' <<<"$ARM_OUT" | sort | tr '\n' ' ')
_sum=$(awk -F'\t|[[:space:]]' '$1=="AFFECTED_SUMMARY"' <<<"$ARM_OUT" | head -1)
if [[ "$_rc" == "0" ]] \
  && [[ "$_sel_yes" == "scripts/lint-dual-lockfile test/x-community " ]] \
  && grep -qF $'AFFECTED_SELECTED\tplugins/soleur\t0' <<<"$ARM_OUT" \
  && grep -qF 'selected=2 of=6 always_on=1 edge=1 fallback=none' <<<"$_sum" \
  && [[ "$(ran_count)" == "0" ]]; then
  pass "p1: --print-selection prints the exact selected set + summary and runs nothing"
else
  fail "p1: rc=$_rc selected='${_sel_yes}' summary='${_sum}' ran=$(ran_count)"
fi

# p2: the print and the run cannot diverge — the suites a real `--affected` run
#     executes for the same diff are exactly the rows printed as selected=1.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/x-community.test.ts' \
  -- --affected
_rc=$ARM_RC
_ran_set=$(awk -F'\t' '$1=="RAN"{print $2}' <<<"$ARM_RECORD" | sort | tr '\n' ' ')
if [[ "$_rc" == "0" && "$_ran_set" == "$_sel_yes" && -n "$_sel_yes" ]]; then
  pass "p2: the printed selected set equals the set a real --affected run executes"
else
  fail "p2: rc=$_rc ran='${_ran_set}' printed='${_sel_yes}'"
fi

# p3: a degraded run names its fallback instead of inventing a selection.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DETECT_OK=0' 'SANDBOX_DIFF_NAMES=' \
  -- --print-selection
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] \
  && grep -qF 'AFFECTED_SUMMARY' <<<"$ARM_OUT" \
  && grep -qF 'fallback=undecidable-diff' <<<"$ARM_OUT" \
  && ! grep -qF $'AFFECTED_SELECTED\t' <<<"$ARM_OUT"; then
  pass "p3: undecidable-diff prints a fallback summary and no per-suite rows"
else
  fail "p3: rc=$_rc — $(grep -c AFFECTED_ <<<"$ARM_OUT") AFFECTED_ lines"
fi

# p4: an executing affected run states its selection on stdout too.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/x-community.test.ts' \
  -- --affected
if [[ "$ARM_RC" == "0" ]] && grep -qF 'AFFECTED_SUMMARY' <<<"$ARM_OUT" \
  && grep -qF 'selected=2 of=6' <<<"$ARM_OUT"; then
  pass "p4: a real --affected run prints the AFFECTED_SUMMARY line"
else
  fail "p4: rc=$ARM_RC summary lines=$(grep -c AFFECTED_SUMMARY <<<"$ARM_OUT")"
fi

# p5: --print-selection is an affected-axis flag — it refuses the combinations
#     where no pre-pass runs.
cases=$((cases + 1))
_p5a=0; env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --print-selection --full >/dev/null 2>&1 || _p5a=$?
_p5b=0; env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --print-selection webplat >/dev/null 2>&1 || _p5b=$?
if [[ "$_p5a" == "2" && "$_p5b" == "2" ]]; then
  pass "p5: --print-selection exits 2 with --full and with a non-all TEST_GROUP"
else
  fail "p5: --full rc=$_p5a, webplat rc=$_p5b, expected 2/2"
fi

# p6: --print-affected-set stays class-only — no selection records leak into it.
cases=$((cases + 1))
_p6=$(cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  SOLEUR_ENUM_DEADLINE_S=900 bash "$RUNNER" --affected --print-affected-set 2>/dev/null) || true
if grep -qF $'AFFECTED_CLASS\t' <<<"$_p6" \
  && ! grep -qF 'AFFECTED_SELECTED' <<<"$_p6" && ! grep -qF 'AFFECTED_SUMMARY' <<<"$_p6"; then
  pass "p6: --print-affected-set emits classes only (no AFFECTED_SELECTED / AFFECTED_SUMMARY)"
else
  fail "p6: class lines=$(grep -c AFFECTED_CLASS <<<"$_p6") selected=$(grep -c AFFECTED_SELECTED <<<"$_p6") summary=$(grep -c AFFECTED_SUMMARY <<<"$_p6")"
fi

# m4: the pre-pass selects everything (the decline bit is neutered) — p1's
#     `plugins/soleur 0` row must now read 1, proving the printed bit is the
#     pre-pass's own and not a recomputation.
cases=$((cases + 1))
SANDBOX_MUT_OLD='              _aff_sel[$_aff_ordinal]=0' \
SANDBOX_MUT_NEW='              _aff_sel[$_aff_ordinal]=1' \
SANDBOX_LIB=with-lib run_arm \
  'SANDBOX_DIFF_NAMES=test/x-community.test.ts' \
  -- --print-selection
if [[ "$ARM_RC" != "98" ]] && grep -qF $'AFFECTED_SELECTED\tplugins/soleur\t1' <<<"$ARM_OUT"; then
  pass "m4: a select-everything pre-pass mutant flips the printed bit (p1 detects it)"
else
  fail "m4: rc=$ARM_RC — $(grep -c AFFECTED_SELECTED <<<"$ARM_OUT") rows"
fi

# --- Rows q1-q4 + m6: --print-selection --paths and the why-columns (#9307) --------
# `--paths=<a,b>` answers "what would THESE paths select?" without a real diff. It
# is print-only by construction (valid only with --print-selection, which exits
# before any suite runs), so it can never narrow a real run's diff. Each
# AFFECTED_SELECTED row also carries the suite's class and its edge set, so the
# reason a suite is (not) selected is on the row instead of in the classifier.
#
# q1: the why-columns — class and edges ride on the row.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  -- --print-selection --paths=README.md
_rc=$ARM_RC
_row=$(awk -F'\t' '$1=="AFFECTED_SELECTED" && $2=="test/x-community"' <<<"$ARM_OUT" | head -1)
if [[ "$_rc" == "0" ]] \
  && [[ "$(awk -F'\t' '{print $3"|"$4}' <<<"$_row")" == "0|edge:declared" ]] \
  && awk -F'\t' '{print $5}' <<<"$_row" | grep -qF '^plugins/soleur/skills/community/scripts/' \
  && grep -qF $'AFFECTED_SELECTED\tscripts/lint-dual-lockfile\t1\talways_on\t' <<<"$ARM_OUT"; then
  pass "q1: rows carry bit, class and edge set (declared edges shown anchored)"
else
  fail "q1: rc=$_rc row='${_row}'"
fi

# q2: --paths selects by the given paths, not by the real diff.
cases=$((cases + 1))
SANDBOX_LIB=with-lib run_arm \
  -- --print-selection --paths=test/x-community.test.ts
_rc=$ARM_RC
if [[ "$_rc" == "0" ]] \
  && grep -qF $'AFFECTED_SELECTED\ttest/x-community\t1\t' <<<"$ARM_OUT" \
  && grep -qF 'fallback=none' <<<"$ARM_OUT"; then
  pass "q2: --paths=test/x-community.test.ts selects test/x-community, no fallback"
else
  fail "q2: rc=$_rc — $(grep -E 'AFFECTED_(SUMMARY|FALLBACK)' <<<"$ARM_OUT" | head -2)"
fi

# q3: --paths is print-only: refused without --print-selection.
cases=$((cases + 1))
_q3a=0; env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --affected --paths=README.md >/dev/null 2>&1 || _q3a=$?
_q3b=0; env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --paths=README.md >/dev/null 2>&1 || _q3b=$?
if [[ "$_q3a" == "2" && "$_q3b" == "2" ]]; then
  pass "q3: --paths exits 2 unless --print-selection is named"
else
  fail "q3: --affected rc=$_q3a, bare rc=$_q3b, expected 2/2"
fi

# q4: against the REAL runner and corpus, --paths bypasses the runner-changed
#     fallback this very branch would otherwise hit, and reports a live selection.
cases=$((cases + 1))
_q4=$(cd "$REPO_ROOT" && env $ENV_SCRUB SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --print-selection --paths=README.md 2>/dev/null) || true
_q4_sum=$(grep -F 'AFFECTED_SUMMARY' <<<"$_q4" | head -1)
_q4_sel=$(sed -E 's/.*selected=([0-9]+) .*/\1/' <<<"$_q4_sum")
if grep -qF 'fallback=none' <<<"$_q4_sum" && [[ "$_q4_sel" =~ ^[0-9]+$ ]] && (( _q4_sel >= 100 )); then
  pass "q4: real corpus, --paths=README.md: ${_q4_sum#AFFECTED_SUMMARY }"
else
  fail "q4: summary='${_q4_sum}'"
fi

# f2: scripts/test-affected-kb-consumers is hedged (always-on, ADR-242 decision 19): selected on a docs-only diff, with the
#     class `always_on`, exactly once. Against the REAL runner and corpus: the sandbox arms trim the corpus to the keep-list,
#     where this label is absent. f1 cannot catch the label being removed (the count would still meet the floor).
cases=$((cases + 1))
_f2_rows=$(grep -cF "AFFECTED_SELECTED"$'\t'"scripts/test-affected-kb-consumers"$'\t'"1"$'\t'"always_on"$'\t' <<<"$_q4" || true)
if [[ "$_f2_rows" == "1" ]]; then
  pass "f2: scripts/test-affected-kb-consumers is selected on a docs-only diff with class always_on (exactly one row)"
else
  fail "f2: expected exactly one AFFECTED_SELECTED row for scripts/test-affected-kb-consumers (selected=1, always_on); got $_f2_rows"
fi

# m6: the paths override is dead — q2's selection must now be empty.
cases=$((cases + 1))
SANDBOX_MUT_OLD='  _diff_names="${_PRINT_PATHS//,/$'"'"'\n'"'"'}"' \
SANDBOX_MUT_NEW='  _diff_names=""' \
SANDBOX_LIB=with-lib run_arm \
  -- --print-selection --paths=test/x-community.test.ts
if [[ "$ARM_RC" == "0" ]] \
  && grep -qF $'AFFECTED_SELECTED\tscripts/lint-dual-lockfile\t1\t' <<<"$ARM_OUT" \
  && ! grep -qF $'AFFECTED_SELECTED\ttest/x-community\t1\t' <<<"$ARM_OUT"; then
  pass "m6: dead-override mutant stops selecting test/x-community (q2 detects it)"
else
  fail "m6: rc=$ARM_RC — $(grep -c AFFECTED_SELECTED <<<"$ARM_OUT") rows"
fi

# q5: `--paths` reaches the ENUMERATE child's relevance gates (#9307). On the real registration
#     stream (a ~2 s walk), a docs-only path declines `apps/web-platform [unit]`; naming a path
#     under apps/web-platform un-declines it. The parent forwards `--paths` to its child, so a
#     `--print-selection --paths=...` report decides these registrations on the NAMED paths.
cases=$((cases + 1))
_q5_docs=$(cd "$REPO_ROOT" && env -u CI -u TEST_GROUP SOLEUR_DISABLE_SESSION_STATE=1 timeout 300 \
  bash "$RUNNER" --enumerate-commands --paths=README.md all 2>/dev/null | awk -F'\t' '$1=="SUITE_COMMAND_DECLINED"{print $2}')
_q5_app=$(cd "$REPO_ROOT" && env -u CI -u TEST_GROUP SOLEUR_DISABLE_SESSION_STATE=1 timeout 300 \
  bash "$RUNNER" --enumerate-commands --paths=apps/web-platform/lib/x.ts all 2>/dev/null | awk -F'\t' '$1=="SUITE_COMMAND_DECLINED"{print $2}')
if [[ -n "$_q5_docs" ]] && grep -qxF 'apps/web-platform [unit]' <<<"$_q5_docs" && ! grep -qxF 'apps/web-platform [unit]' <<<"$_q5_app"; then
  pass "q5: --enumerate-commands --paths declines apps/web-platform [unit] for a docs path and runs it for an app path"
else
  fail "q5: docs-declined='$(tr '\n' ',' <<<"$_q5_docs")' app-declined='$(tr '\n' ',' <<<"$_q5_app")'"
fi

# q6: the WIRE. q5 proves the child honours `--paths`; this proves the parent passes it. One
#     comment-stripped, assignment-anchored call carries `_aff_child_paths` on the enumerate call.
cases=$((cases + 1))
_q6_n=$(grep -vE '^[[:space:]]*#' "$RUNNER" | grep -cE '^[[:space:]]*_aff_stream="\$\(.*--enumerate-commands .*\$\{_aff_child_paths\[@\]' || true)
_q6_set=$(grep -vE '^[[:space:]]*#' "$RUNNER" | grep -cE '^[[:space:]]*if \(\( _PRINT_PATHS_REQ == 1 \)\); then _aff_child_paths=\(--paths=' || true)
if [[ "$_q6_n" == "1" && "$_q6_set" == "1" ]]; then
  pass "q6: the pre-pass forwards --paths to its enumerate child (one call site, one assignment)"
else
  fail "q6: enumerate call carries _aff_child_paths x${_q6_n}, assignment x${_q6_set} (expected 1 and 1)"
fi

echo ""
# Conservation + floor: a truncated row block must not read as green.
if (( PASS + FAIL != cases )); then
  echo "[FATAL] verdict mismatch: PASS($PASS)+FAIL($FAIL) != cases($cases) — a row was skipped" >&2
  exit 2
fi
MIN_CASES=89
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
