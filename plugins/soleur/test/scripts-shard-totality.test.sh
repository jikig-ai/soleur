#!/usr/bin/env bash
#
# Guard 1 (#7902) — SHARD TOTALITY.
#
# PROPERTY. Every suite registered for the scripts group is assigned to EXACTLY ONE matrix leg,
# so the union of the legs' assigned sets equals the full registration set with no gaps and no
# duplicates.
#
# WHY THIS IS THE HIGHEST-PRIORITY DELIVERABLE OF ITS PR. Sharding `test-scripts` makes the
# required `test` check green off three legs. If the partition drops a registration, that check
# reports green while running a strict subset — a regression reaching production behind a green
# pipeline. That is strictly WORSE than the blocked deploy #7902 is about, so the partition is
# made total BY CONSTRUCTION (round-robin at the run_suite/skip_suite chokepoint) and asserted
# here on top.
#
# THE REFERENCE SET IS DERIVED INDEPENDENTLY OF THE PARTITION, and that is the whole design.
# Deriving it by invoking the partition with K=1 would make the union comparison true by
# construction for any partition that is a function of the enumeration: the guard would degrade
# into a checksum, green on exactly the dropped-suite case it exists to catch. It is derived
# instead by STATIC extraction of run_suite/skip_suite registrations inside the runner's own
# `if want_scripts` regions, plus `--print-suite-globs` expansion — mirroring the extractor
# scripts/lint-orphan-test-suites.sh already implements. Mutation row 6 pins that.
#
# RELATIONSHIP TO lint-orphan-test-suites.sh: that lint proves a suite is REGISTERED WITH SOME
# RUNNER. This proves a REGISTERED suite is ASSIGNED TO EXACTLY ONE LEG. Adjacent; neither
# subsumes the other.
#
# ASSIGNED, NEVER EXECUTED. ADR-181 relevance gating means executed ⊊ registered even in an
# unsharded run, so an executed-set comparison would red on nearly every commit. The enumerate
# mode reports what each leg was ASSIGNED.
#
# NO RECURSION. Every child invocation here is `--enumerate`, which returns from run_suite
# before executing anything and takes no advisory lock. This suite is itself glob-discovered
# into the scripts group, so an executing child would be unbounded recursion — the failure
# lint-orphan-test-suites.sh documents at length.
#
# set -u, NOT set -e: accumulate-then-exit, the convention this repo's .test.sh files use.
set -uo pipefail

# A self-invoked .test.sh builds sandboxes in TMPDIR, and /tmp on this machine class is a
# ~4 GiB tmpfs shared by parallel worktrees. test-all.sh and run-registered-suites.sh both
# default this; a DIRECT invocation (the inner loop while editing this file) does not.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

PASS=0
FAIL=0
pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; }

WORK="$(mktemp -d -t shard-totality.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

echo "=== Guard 1: scripts-group shard totality (#7902) ==="

# --- INSTRUMENT SELF-TEST -------------------------------------------------------------------
#
# Drive both accounting helpers once each and refuse to continue unless BOTH counters moved.
# A suite whose only gate is a failure counter can have that counter neutered, and every row
# then reports green having asserted nothing (ADR-193). This runs FIRST, upstream of every
# assertion, and its own effect is subtracted before the real rows begin.
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (this row is expected)"
fail "instrument self-test (this row is expected — it is subtracted below)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  echo "FATAL: instrument self-test did not move both counters — assertions here prove nothing." >&2
  exit 2
fi
PASS=$_p0
FAIL=$_f0
echo "  (instrument self-test OK — both counters move; counters reset)"

# --- Preconditions --------------------------------------------------------------------------
for f in "$RUNNER" "$CI_YML"; do
  if [[ ! -f "$f" ]]; then
    echo "FATAL: required file missing: $f" >&2
    exit 2
  fi
done

# --- Helper: enumerate one leg --------------------------------------------------------------
#
# TEST_GROUP is pinned explicitly rather than inherited: the runner resolves
# `TEST_GROUP="${TEST_GROUP:-${1:-all}}"`, so an inherited TEST_GROUP=all would silently widen
# the child past the group under test while the positional argument said `scripts`.
enumerate_leg() {
  local spec="$1" out="$2"
  if [[ "$spec" == "-" ]]; then
    env -u SCRIPTS_SHARD TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$RUNNER" --enumerate scripts 2>/dev/null \
      | grep '^SUITE_REGISTRATION' | cut -f2 > "$out"
  else
    env SCRIPTS_SHARD="$spec" TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$RUNNER" --enumerate scripts 2>/dev/null \
      | grep '^SUITE_REGISTRATION' | cut -f2 > "$out"
  fi
}

# --- The totality comparison, as a FUNCTION so it can be positive-controlled ------------------
#
# Extracted deliberately. Written inline as `if diff -q ...; then pass; else fail; fi`, the
# assertion is neuterable by a ONE-TOKEN edit (`if true; then`) that leaves the row count
# unchanged — so neither the assertion floor nor any sibling row notices, and the guard reports
# a clean totality over a comparison that never ran. MEASURED: that exact mutation survived
# this battery's first run.
#
# As a function it has a positive control below: the same comparison is fed two sets that are
# KNOWN to differ and must report the difference. Neutering the body to satisfy the real row
# then fails the control.
totality_holds() {
  diff -q "$1" "$2" >/dev/null 2>&1
}

# --- The INDEPENDENT reference set ----------------------------------------------------------
#
# (a) Static extraction, scoped to the runner's column-0 `if want_scripts; then` .. `fi`
#     regions so registrations belonging to the webplat/bun/infra groups are excluded.
#     Labels containing `$` are skipped: those are the glob loop's `run_suite "$f"`, whose
#     members arrive via (b).
awk '
  /^if want_scripts; then$/ { inb=1; next }
  inb && /^fi$/             { inb=0; next }
  inb && /^[[:space:]]*(run_suite|skip_suite) "/ {
    line=$0
    sub(/^[[:space:]]*(run_suite|skip_suite) "/, "", line)
    idx=index(line, "\"")
    if (idx > 0) { lbl=substr(line, 1, idx-1); if (lbl !~ /\$/) print lbl }
  }
' "$RUNNER" | sort -u > "$WORK/ref_static"

# (b) Glob expansion, via the runner's own single declaration of the glob list. Cleared of
#     TEST_GROUP and SCRIPTS_SHARD for the reasons lint-orphan-test-suites.sh documents.
globs_rc=0
env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --print-suite-globs > "$WORK/globs" 2>/dev/null || globs_rc=$?
: > "$WORK/ref_glob"
if (( globs_rc == 0 )); then
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    # shellcheck disable=SC2086
    for f in $( cd "$REPO_ROOT" && eval echo $g ); do
      [[ -e "$REPO_ROOT/$f" ]] && echo "$f" >> "$WORK/ref_glob"
    done
  done < "$WORK/globs"
fi
sort -u "$WORK/ref_glob" -o "$WORK/ref_glob"

cat "$WORK/ref_static" "$WORK/ref_glob" | sort -u > "$WORK/reference"
REF_N=$(wc -l < "$WORK/reference" | tr -d ' ')

# ROW: the reference itself must be non-empty. A guard reporting "0 checked" and exiting 0 is
# vacuous, and both halves of the derivation can fail independently (a renamed want_scripts
# gate; a --print-suite-globs that stopped answering). Mutation row 2.
if (( REF_N >= 100 )); then
  pass "reference set derived independently: $REF_N registrations ($(wc -l < "$WORK/ref_static" | tr -d ' ') static + $(wc -l < "$WORK/ref_glob" | tr -d ' ') glob, deduped)"
else
  fail "reference set is implausibly small ($REF_N) — the static extraction or the glob expansion returned nothing, so every comparison below would be vacuous"
fi

# --- The matrix leg list, read from ci.yml ---------------------------------------------------
#
# Read as VALUES, not as a count. Mutation row 5 is a matrix listing ["1/3","2/3"] — two legs
# whose values still say /3 — where leg 3's suites run nowhere and both surviving legs are
# green. A count-based read cannot see that; the value list can.
awk '
  /^  test-scripts:$/ { inj=1; next }
  inj && /^  [a-z0-9_-]+:$/ { inj=0 }
  inj && /shard:/ {
    line=$0
    while (match(line, /"[0-9]+\/[0-9]+"/)) {
      print substr(line, RSTART+1, RLENGTH-2)
      line = substr(line, RSTART+RLENGTH)
    }
  }
' "$CI_YML" > "$WORK/legs"
LEGS_N=$(wc -l < "$WORK/legs" | tr -d ' ')

if (( LEGS_N >= 1 )); then
  pass "ci.yml declares $LEGS_N test-scripts matrix leg(s): $(tr '\n' ' ' < "$WORK/legs")"
else
  fail "ci.yml's test-scripts job declares no strategy.matrix.shard values — the sharded contract this guard exists for is not wired, so no union can be checked"
fi

if (( LEGS_N >= 1 )); then
  # ROW: the matrix VALUES must actually be WIRED to the runner (#7902 review, P1).
  #
  # Every other row here reads ci.yml's `strategy.matrix.shard` literals. That is a claim about what
  # the matrix DECLARES, and says nothing about what the leg RECEIVES. The wire is one line —
  # `SCRIPTS_SHARD: ${{ matrix.shard }}` — and replacing it with a literal (`SCRIPTS_SHARD: "1/3"`)
  # leaves every declared value untouched: measured, all 15 rows stayed green while all three legs
  # ran leg 1's registrations and 250 of 376 ran NOWHERE, behind a green required `test`. That is
  # verbatim the catastrophe this file's header says it prevents.
  #
  # The extractor above cannot see it either: its awk matches lowercase /shard:/, and the binding
  # reads SCRIPTS_SHARD: — a near-miss anchor collision. So this row greps the job block directly,
  # anchored on the interpolation rather than the key, because only the interpolation carries the
  # per-leg value.
  _wire=$(awk '
    /^  test-scripts:$/ { inj=1; next }
    inj && /^  [A-Za-z0-9_-]+:$/ { exit }
    inj { print }
  ' "$CI_YML" | grep -cE '^[[:space:]]*SCRIPTS_SHARD:[[:space:]]*\$\{\{[[:space:]]*matrix\.shard[[:space:]]*\}\}[[:space:]]*$' || true)
  if [[ "$_wire" == "1" ]]; then
    pass "the matrix is WIRED: test-scripts binds SCRIPTS_SHARD to \${{ matrix.shard }} exactly once"
  else
    fail "the matrix->env wire is missing or not an interpolation ($_wire matches). A literal or absent SCRIPTS_SHARD makes every leg run the same (or the full) set while all leg values stay declared and every other row here stays green."
  fi

  # ROW: every declared leg must resolve to a distinct k, and all must share one N.
  # This is what detects a leg that lost its env or a hand-edited duplicate.
  declare -a _ks=() _ns=()
  while IFS= read -r spec; do
    _ks+=( "${spec%%/*}" )
    _ns+=( "${spec##*/}" )
  done < "$WORK/legs"
  _distinct_k=$(printf '%s\n' "${_ks[@]}" | sort -u | wc -l | tr -d ' ')
  _distinct_n=$(printf '%s\n' "${_ns[@]}" | sort -u | wc -l | tr -d ' ')
  if (( _distinct_k == LEGS_N && _distinct_n == 1 && ${_ns[0]} == LEGS_N )); then
    pass "the $LEGS_N legs carry $LEGS_N distinct k values over a single N=${_ns[0]}"
  else
    fail "leg specs are inconsistent: $_distinct_k distinct k over $_distinct_n distinct N (values: $(tr '\n' ' ' < "$WORK/legs")). A leg count that disagrees with N leaves the missing residue class assigned to no leg while every declared leg reports green."
  fi

  # --- The union ----------------------------------------------------------------------------
  : > "$WORK/union"
  _leg_i=0
  while IFS= read -r spec; do
    _leg_i=$(( _leg_i + 1 ))
    enumerate_leg "$spec" "$WORK/leg_$_leg_i"
    _n=$(wc -l < "$WORK/leg_$_leg_i" | tr -d ' ')
    if (( _n >= 1 )); then
      pass "leg $spec enumerated $_n assigned registration(s)"
    else
      fail "leg $spec enumerated ZERO registrations — a leg assigned nothing is a leg whose green means nothing"
    fi
    cat "$WORK/leg_$_leg_i" >> "$WORK/union"
  done < "$WORK/legs"

  UNION_N=$(wc -l < "$WORK/union" | tr -d ' ')
  UNION_U=$(sort -u "$WORK/union" | wc -l | tr -d ' ')

  # ROW: no duplicates — union correct but MULTISET wrong (two legs claiming one label).
  # Mutation rows 4 and 7 both land here: filtering run_suite but not skip_suite makes every
  # leg emit the skip_suite registrations, so they appear N times.
  if (( UNION_N == UNION_U )); then
    pass "no registration is assigned to more than one leg ($UNION_N assignments, $UNION_U distinct)"
  else
    _dupes=$(sort "$WORK/union" | uniq -d | head -5 | tr '\n' ' ')
    fail "$(( UNION_N - UNION_U )) duplicate assignment(s): a registration claimed by two legs runs twice and its cost is paid twice; first few: $_dupes"
  fi

  # ROW: totality — the union equals the independently derived reference, exactly.
  sort -u "$WORK/union" > "$WORK/union_sorted"
  if totality_holds "$WORK/reference" "$WORK/union_sorted"; then
    pass "TOTALITY: the union of all legs equals the independently derived reference set ($REF_N registrations)"
  else
    _missing=$(comm -23 "$WORK/reference" "$WORK/union_sorted" | head -10 | tr '\n' ' ')
    _extra=$(comm -13 "$WORK/reference" "$WORK/union_sorted" | head -10 | tr '\n' ' ')
    fail "TOTALITY VIOLATED. Assigned to NO leg (these run nowhere while the required 'test' check reports green): ${_missing:-none}. Assigned but absent from the reference (the reference derivation is stale or the partition invented a label): ${_extra:-none}."
  fi
fi

# --- POSITIVE CONTROL on the totality comparison ---------------------------------------------
#
# Feed the SAME comparison two sets that differ by exactly one registration — the smallest
# discrepancy it must catch, and the shape of a suite that silently stops running — and require
# it to report the difference. Without this row, `totality_holds` can be neutered to always
# succeed and every totality claim above becomes decorative while the suite stays green.
if [[ -s "$WORK/reference" ]]; then
  head -n -1 "$WORK/reference" > "$WORK/control_dropped_one"
  if totality_holds "$WORK/reference" "$WORK/control_dropped_one"; then
    fail "POSITIVE CONTROL: the totality comparison reports two sets differing by one registration as IDENTICAL. It is neutered, so every totality verdict above is decorative."
  else
    pass "positive control: the totality comparison detects a single dropped registration"
  fi
else
  fail "POSITIVE CONTROL could not run — the reference set is empty"
fi

# --- MUST-PASS non-canonical inputs ----------------------------------------------------------
#
# Totality is required for ANY K, not only the configured one. If these fail while the
# configured K passes, the partition is tuned to one value rather than correct.
for altK in 2 5; do
  : > "$WORK/alt_union"
  for k in $(seq 1 "$altK"); do
    enumerate_leg "$k/$altK" "$WORK/alt_leg"
    cat "$WORK/alt_leg" >> "$WORK/alt_union"
  done
  _an=$(wc -l < "$WORK/alt_union" | tr -d ' ')
  sort -u "$WORK/alt_union" > "$WORK/alt_sorted"
  _au=$(wc -l < "$WORK/alt_sorted" | tr -d ' ')
  if (( _an == _au )) && diff -q "$WORK/reference" "$WORK/alt_sorted" >/dev/null 2>&1; then
    pass "non-canonical K=$altK is also total and duplicate-free"
  else
    fail "K=$altK is not total/duplicate-free ($_an assignments, $_au distinct, reference $REF_N) — the partition is correct only for the configured K"
  fi
done

# --- Fail-closed on a malformed shard spec ---------------------------------------------------
#
# A silent full-group fallback would make a broken matrix interpolation run everything and
# report green; a silent empty fallback would report green over zero coverage. Both are worse
# than refusing. `''` is included deliberately: `SCRIPTS_SHARD: ${{ matrix.shard }}` resolving
# empty is the realistic CI shape of "the env broke".
_mal_ok=1
# `１/３` is FULLWIDTH digits (U+FF11 / U+FF13), deliberately. `[0-9]` inside `[[ =~ ]]` is
# collation-dependent and matches them under a UTF-8 locale; `10#` then throws a fatal
# arithmetic error that aborts the enclosing if-compound and resumes AFTER it at status 0, so
# k/N keep their initial 0 and the leg silently runs the FULL group. An all-ASCII fixture list
# cannot see that class, which is why this row exists.
for bad in "0/3" "4/3" "1/0" "abc" "" "   " "3/" "/3" "1/3/2" "１/３"; do
  env SCRIPTS_SHARD="$bad" TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$RUNNER" --enumerate scripts >/dev/null 2>&1
  _rc=$?
  if (( _rc != 2 )); then
    _mal_ok=0
    fail "malformed SCRIPTS_SHARD='$bad' exited $_rc, expected 2 (fail closed)"
  fi
done
if (( _mal_ok == 1 )); then
  pass "every malformed SCRIPTS_SHARD spec fails closed with exit 2"
fi

# --- A syntactically VALID spec that owns nothing must also fail closed -----------------------
#
# The malformed list above covers SYNTAX. This covers SEMANTICS: any k beyond the registration
# count passes every syntactic check and matches no ordinal, so the leg runs nothing and the
# executing path exits 0 having reported "0/0 suites passed" — a green required check over zero
# coverage, reachable through the environment rather than the matrix literal.
#
# DERIVED from REF_N, never a literal: a hardcoded bound stops being out-of-range the moment
# anyone registers another suite, and the fixture would rot silently into a no-op.
# ASSERT THE MESSAGE, NOT THE EXIT CODE. Both refusals exit 2, so rc cannot say WHICH fired —
# and they are not independent: with the validator's length bound reverted, an over-long spec
# clears the validator and is caught by the zero-assignment refusal instead, at the same rc.
# Only the message separates them, so only the message can pin each one.
_over=$(( REF_N + 1 ))
_over_err=$(env SCRIPTS_SHARD="${_over}/${_over}" TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts 2>&1 >/dev/null || true)
if grep -qF 'assigned 0 of' <<<"$_over_err"; then
  pass "a valid-but-empty assignment (${_over}/${_over}, beyond ${REF_N} registrations) is refused by the zero-assignment check"
else
  fail "SCRIPTS_SHARD=${_over}/${_over} was not refused by the zero-assignment check (got: ${_over_err:-<no output>}). It is syntactically valid and matches NO ordinal, so the leg owns nothing — on the executing path that reports '0/0 suites passed' and exits 0, making the required 'test' check green over ZERO coverage."
fi

# The validator's length bound, pinned LOCALE-INDEPENDENTLY. A fullwidth-digit fixture cannot do
# this job on CI: `[0-9]` matches U+FF11 only under en_US.UTF-8 and REJECTS it under C and
# C.UTF-8, and GitHub runners set LANG=C.UTF-8 — so such a fixture would pass there under BOTH
# the correct and the reverted implementation, i.e. for the wrong reason, with every fixture on
# one side of the property. An over-long ASCII run discriminates everywhere.
_long="1234567890/1234567890"
_long_err=$(env SCRIPTS_SHARD="$_long" TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts 2>&1 >/dev/null || true)
if grep -qF 'must be k/N' <<<"$_long_err"; then
  pass "an over-long digit run is refused by the VALIDATOR (its length bound is load-bearing)"
else
  fail "SCRIPTS_SHARD=$_long was not refused by the validator (got: ${_long_err:-<no output>}). An unbounded digit class overflows 64-bit arithmetic, so a wrapped k/N pair passes the range check and matches no ordinal."
fi

# --- Unset runs the full group ---------------------------------------------------------------
enumerate_leg "-" "$WORK/unset"
_un=$(sort -u "$WORK/unset" | wc -l | tr -d ' ')
if (( _un == REF_N )); then
  pass "SCRIPTS_SHARD unset enumerates the full group ($_un) — local runs, lefthook and TEST_GROUP=all are unaffected"
else
  fail "SCRIPTS_SHARD unset enumerated $_un registrations, expected the full $REF_N"
fi

# --- ASSERTION FLOOR --------------------------------------------------------------------------
#
# Reported with printf + exit 1, NEVER through fail() — the helper this floor exists to
# backstop is exactly the thing one edit disarms (ADR-193).
MIN_ROWS=16
TOTAL=$(( PASS + FAIL ))
if (( TOTAL < MIN_ROWS )); then
  printf 'FAIL: assertion floor — %d rows executed, expected at least %d. The suite did not run to completion, so its verdict is not evidence.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi

echo ""
echo "scripts-shard-totality.test.sh: $TOTAL rows, $PASS passed, $FAIL failed"
# VERDICT IS REPORTED THE WAY THE FLOOR IS (#7902 review, P2).
if (( FAIL > 0 )); then
  printf 'VERDICT: %d of %d rows FAILED — this suite is RED.\n' "$FAIL" "$TOTAL" >&2
  exit 1
fi
echo "All tests passed"
