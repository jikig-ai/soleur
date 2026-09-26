#!/usr/bin/env bash
#
# Guard 1 (#7902) — SHARD TOTALITY.
#
# PROPERTY. Every suite registered for the scripts group is assigned to EXACTLY ONE matrix leg,
# so the union of the legs' assigned sets equals the full registration set with no gaps and no
# duplicates.
#
# WHY THIS IS THE HIGHEST-PRIORITY DELIVERABLE OF ITS PR. Sharding `test-scripts` makes the
# required `test` check green off seven legs (Guard 1b below covers the three-leg
# `test-scripts-heavy` matrix under the identical contract). If the partition drops a
# registration, that check reports green while running a strict subset — a regression
# reaching production behind a green pipeline. That is strictly WORSE than the blocked
# deploy #7902 is about, so the partition is made total BY CONSTRUCTION (round-robin at
# the run_suite/skip_suite chokepoint) and asserted here on top.
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
  local spec="$1" out="$2" group="${3:-scripts}"
  env SCRIPTS_SHARD="$spec" TEST_GROUP="$group" SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$RUNNER" --enumerate "$group" 2>/dev/null \
    | grep '^SUITE_REGISTRATION' | cut -f2 > "$out"
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
# PARALLEL CHILDREN. The two derivations below are independent, and every enumerate
# child in this file is independent of every other — each is backgrounded and its
# per-pid rc is captured by `wait`, then verdicts are evaluated serially in declared
# order so PASS/FAIL output stays deterministic. Enumerate children take no advisory
# lock (test-all.sh's _ENUMERATE exemption), so concurrency is safe by design. Fan-out
# is bounded per batch: no batch exceeds ~10 concurrent children.
#
# (b) Glob expansion child — launched FIRST so it overlaps (a). Cleared of TEST_GROUP
#     and SCRIPTS_SHARD for the reasons lint-orphan-test-suites.sh documents.
env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --print-suite-globs > "$WORK/globs" 2>/dev/null &
_globs_pid=$!

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

globs_rc=0; wait "$_globs_pid" || globs_rc=$?
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
# Read as VALUES, not as a count. Mutation row 5 is a matrix listing one leg short of
# ["1/7".."7/7"] — six legs whose values still say /7 — where leg 7's suites run nowhere and
# all surviving legs are green. A count-based read cannot see that; the value list can.
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
  # Fan out one child per declared leg (this batch is the matrix leg count itself —
  # bounded by ci.yml, ~10 at most), then collect rc per-pid and evaluate in order.
  declare -a _leg_pids=()
  _leg_i=0
  while IFS= read -r spec; do
    _leg_i=$(( _leg_i + 1 ))
    # `< /dev/null`: the child inherits this loop's stdin (the legs file) — pin it so
    # nothing in the enumerate path can ever consume the remaining leg specs.
    enumerate_leg "$spec" "$WORK/leg_$_leg_i" < /dev/null &
    _leg_pids[$(( _leg_i - 1 ))]=$!
  done < "$WORK/legs"

  : > "$WORK/union"
  _leg_i=0
  while IFS= read -r spec; do
    _leg_i=$(( _leg_i + 1 ))
    _rc=0; wait "${_leg_pids[$(( _leg_i - 1 ))]}" || _rc=$?
    if (( _rc != 0 )); then
      fail "leg $spec enumerate child exited $_rc — a dead child OR a leg the runner refused (zero-assignment) cannot prove its assigned set, so its green would mean nothing"
    else
      # pipefail: rc==0 means grep matched, so the output file is provably non-empty.
      _n=$(wc -l < "$WORK/leg_$_leg_i" | tr -d ' ')
      pass "leg $spec enumerated $_n assigned registration(s)"
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
  # Fan out the altK leg children (<= altK concurrent, <= 5), one output file each.
  declare -a _alt_pids=()
  _alt_i=0
  for k in $(seq 1 "$altK"); do
    enumerate_leg "$k/$altK" "$WORK/alt_leg_${altK}_${k}" &
    _alt_pids[$_alt_i]=$!
    _alt_i=$(( _alt_i + 1 ))
  done
  : > "$WORK/alt_union"
  _alt_i=0
  for k in $(seq 1 "$altK"); do
    _rc=0; wait "${_alt_pids[$_alt_i]}" || _rc=$?
    _alt_i=$(( _alt_i + 1 ))
    if (( _rc != 0 )); then
      fail "non-canonical K=$altK leg $k enumerate child exited $_rc — the union below is built from a lost leg"
    fi
    cat "$WORK/alt_leg_${altK}_${k}" >> "$WORK/alt_union"
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
# Fan-out bound: 10 children, the largest batch in this file.
declare -a _mal_specs=() _mal_pids=()
_mal_n=0
for bad in "0/3" "4/3" "1/0" "abc" "" "   " "3/" "/3" "1/3/2" "１/３"; do
  _mal_specs[$_mal_n]="$bad"
  env SCRIPTS_SHARD="$bad" TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$RUNNER" --enumerate scripts >/dev/null 2>&1 &
  _mal_pids[$_mal_n]=$!
  _mal_n=$(( _mal_n + 1 ))
done
for (( _mi = 0; _mi < _mal_n; _mi++ )); do
  _rc=0; wait "${_mal_pids[$_mi]}" || _rc=$?
  if (( _rc != 2 )); then
    _mal_ok=0
    fail "malformed SCRIPTS_SHARD='${_mal_specs[$_mi]}' exited $_rc, expected 2 (fail closed)"
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
# Three independent children — the two stderr probes below and the unset-spec
# enumeration after them — fanned out together, each writing its own $WORK file.
_over=$(( REF_N + 1 ))
env SCRIPTS_SHARD="${_over}/${_over}" TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts >/dev/null 2>"$WORK/over_err" &
_over_pid=$!
_long="1234567890/1234567890"
env SCRIPTS_SHARD="$_long" TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts >/dev/null 2>"$WORK/long_err" &
_long_pid=$!
env -u SCRIPTS_SHARD TEST_GROUP=scripts SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts 2>/dev/null \
  | grep '^SUITE_REGISTRATION' | cut -f2 | sort -u > "$WORK/unset" &
_unset_pid=$!

wait "$_over_pid" || true
_over_err=$(cat "$WORK/over_err")
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
wait "$_long_pid" || true
_long_err=$(cat "$WORK/long_err")
if grep -qF 'must be k/N' <<<"$_long_err"; then
  pass "an over-long digit run is refused by the VALIDATOR (its length bound is load-bearing)"
else
  fail "SCRIPTS_SHARD=$_long was not refused by the validator (got: ${_long_err:-<no output>}). An unbounded digit class overflows 64-bit arithmetic, so a wrapped k/N pair passes the range check and matches no ordinal."
fi

# --- Unset runs the full group ---------------------------------------------------------------
wait "$_unset_pid" || fail "unset-SCRIPTS_SHARD enumerate pipeline exited nonzero — its output file cannot be trusted"
_un=$(sort -u "$WORK/unset" | wc -l | tr -d ' ')
if (( _un == REF_N )); then
  pass "SCRIPTS_SHARD unset enumerates the full group ($_un) — local runs, lefthook and TEST_GROUP=all are unaffected"
else
  fail "SCRIPTS_SHARD unset enumerated $_un registrations, expected the full $REF_N"
fi

# === Guard 1b — scripts-heavy group totality =================================================
#
# The three cost-heaviest registrations live under `want_scripts_heavy` and are partitioned by
# the dedicated `test-scripts-heavy` matrix job (one suite per leg). EVERY property asserted for
# the scripts group above must hold here too — a mis-wired heavy matrix makes all three legs run
# all three suites (or none) while staying green, and the required `test` check rolls the result
# up the same way.
#
# Deliberate differences from the scripts pass, all derived from the group's shape:
#   - the reference is STATIC-ONLY: the heavy registrations are literal `run_suite`/`skip_suite`
#     lines, no glob expansion exists under `want_scripts_heavy`;
#   - the non-vacuity floor is >= 1, not >= 100 — three registrations is the whole point;
#   - non-canonical K rows use {2,3} only: K>3 legs are syntactically valid but own nothing, so
#     they hit the zero-assignment refusal by DESIGN — that boundary is pinned as a refusal row
#     below rather than traversed as a totality case;
#   - the malformed-spec list probes 4 classes (zero numerator, non-numeric, empty, fullwidth)
#     not the light arm's 10 — the validator is a shared code path, so the heavy list samples
#     each distinct class rather than re-running the full matrix; the over-long-digit-run
#     probe is likewise light-only (the digit bound is already proven).
echo ""
echo "=== Guard 1b: scripts-heavy group totality ==="

# --- Heavy reference set: static extraction over `if want_scripts_heavy; then` .. `fi` --------
awk '
  /^if want_scripts_heavy; then$/ { inb=1; next }
  inb && /^fi$/                   { inb=0; next }
  inb && /^[[:space:]]*(run_suite|skip_suite) "/ {
    line=$0
    sub(/^[[:space:]]*(run_suite|skip_suite) "/, "", line)
    idx=index(line, "\"")
    if (idx > 0) { lbl=substr(line, 1, idx-1); if (lbl !~ /\$/) print lbl }
  }
' "$RUNNER" | sort -u > "$WORK/ref_heavy"
REF_H=$(wc -l < "$WORK/ref_heavy" | tr -d ' ')

if (( REF_H >= 1 )); then
  pass "heavy reference set derived independently: $REF_H registration(s) under want_scripts_heavy"
else
  fail "heavy reference set is EMPTY — the want_scripts_heavy extraction returned nothing (group renamed? gate removed?), so every comparison below would be vacuous"
fi

# --- Heavy matrix leg list, read from the test-scripts-heavy job block -------------------------
awk '
  /^  test-scripts-heavy:$/ { inj=1; next }
  inj && /^  [a-z0-9_-]+:$/ { inj=0 }
  inj && /shard:/ {
    line=$0
    while (match(line, /"[0-9]+\/[0-9]+"/)) {
      print substr(line, RSTART+1, RLENGTH-2)
      line = substr(line, RSTART+RLENGTH)
    }
  }
' "$CI_YML" > "$WORK/legs_heavy"
LEGS_H=$(wc -l < "$WORK/legs_heavy" | tr -d ' ')

if (( LEGS_H >= 1 )); then
  pass "ci.yml declares $LEGS_H test-scripts-heavy matrix leg(s): $(tr '\n' ' ' < "$WORK/legs_heavy")"
else
  fail "ci.yml's test-scripts-heavy job declares no strategy.matrix.shard values — the heavy partition is not wired, so no union can be checked"
fi

if (( LEGS_H >= 1 )); then
  # Same wire hazard as the scripts group: declared values say nothing about what the leg
  # RECEIVES. Only the `SCRIPTS_SHARD: ${{ matrix.shard }}` interpolation inside the
  # test-scripts-heavy job block carries the per-leg value.
  _wire_h=$(awk '
    /^  test-scripts-heavy:$/ { inj=1; next }
    inj && /^  [A-Za-z0-9_-]+:$/ { exit }
    inj { print }
  ' "$CI_YML" | grep -cE '^[[:space:]]*SCRIPTS_SHARD:[[:space:]]*\$\{\{[[:space:]]*matrix\.shard[[:space:]]*\}\}[[:space:]]*$' || true)
  if [[ "$_wire_h" == "1" ]]; then
    pass "the heavy matrix is WIRED: test-scripts-heavy binds SCRIPTS_SHARD to \${{ matrix.shard }} exactly once"
  else
    fail "the heavy matrix->env wire is missing or not an interpolation ($_wire_h matches). A literal or absent SCRIPTS_SHARD makes every heavy leg run the same (or the full) set while all leg values stay declared and every other row here stays green."
  fi

  declare -a _hks=() _hns=()
  while IFS= read -r spec; do
    _hks+=( "${spec%%/*}" )
    _hns+=( "${spec##*/}" )
  done < "$WORK/legs_heavy"
  _distinct_hk=$(printf '%s\n' "${_hks[@]}" | sort -u | wc -l | tr -d ' ')
  _distinct_hn=$(printf '%s\n' "${_hns[@]}" | sort -u | wc -l | tr -d ' ')
  if (( _distinct_hk == LEGS_H && _distinct_hn == 1 && ${_hns[0]} == LEGS_H )); then
    pass "the $LEGS_H heavy legs carry $LEGS_H distinct k values over a single N=${_hns[0]}"
  else
    fail "heavy leg specs are inconsistent: $_distinct_hk distinct k over $_distinct_hn distinct N (values: $(tr '\n' ' ' < "$WORK/legs_heavy")). A leg count that disagrees with N leaves the missing residue class assigned to no leg while every declared leg reports green."
  fi

  # --- The heavy union ----------------------------------------------------------------------
  declare -a _hleg_pids=()
  _leg_i=0
  while IFS= read -r spec; do
    _leg_i=$(( _leg_i + 1 ))
    enumerate_leg "$spec" "$WORK/hleg_$_leg_i" scripts-heavy < /dev/null &
    _hleg_pids[$(( _leg_i - 1 ))]=$!
  done < "$WORK/legs_heavy"

  : > "$WORK/union_heavy"
  _leg_i=0
  while IFS= read -r spec; do
    _leg_i=$(( _leg_i + 1 ))
    _rc=0; wait "${_hleg_pids[$(( _leg_i - 1 ))]}" || _rc=$?
    if (( _rc != 0 )); then
      fail "heavy leg $spec enumerate child exited $_rc — a dead child OR a leg the runner refused (zero-assignment) cannot prove its assigned set, so its green would mean nothing"
    else
      _n=$(wc -l < "$WORK/hleg_$_leg_i" | tr -d ' ')
      pass "heavy leg $spec enumerated $_n assigned registration(s)"
    fi
    cat "$WORK/hleg_$_leg_i" >> "$WORK/union_heavy"
  done < "$WORK/legs_heavy"

  UNION_HN=$(wc -l < "$WORK/union_heavy" | tr -d ' ')
  UNION_HU=$(sort -u "$WORK/union_heavy" | wc -l | tr -d ' ')
  if (( UNION_HN == UNION_HU )); then
    pass "no heavy registration is assigned to more than one leg ($UNION_HN assignments, $UNION_HU distinct)"
  else
    _dupes=$(sort "$WORK/union_heavy" | uniq -d | head -5 | tr '\n' ' ')
    fail "$(( UNION_HN - UNION_HU )) duplicate heavy assignment(s): first few: $_dupes"
  fi

  sort -u "$WORK/union_heavy" > "$WORK/union_heavy_sorted"
  if totality_holds "$WORK/ref_heavy" "$WORK/union_heavy_sorted"; then
    pass "TOTALITY: the union of all heavy legs equals the independently derived heavy reference set ($REF_H registrations)"
  else
    _missing=$(comm -23 "$WORK/ref_heavy" "$WORK/union_heavy_sorted" | head -10 | tr '\n' ' ')
    _extra=$(comm -13 "$WORK/ref_heavy" "$WORK/union_heavy_sorted" | head -10 | tr '\n' ' ')
    fail "HEAVY TOTALITY VIOLATED. Assigned to NO leg: ${_missing:-none}. Assigned but absent from the reference: ${_extra:-none}."
  fi
fi

# --- POSITIVE CONTROL on the heavy comparison -------------------------------------------------
if [[ -s "$WORK/ref_heavy" ]]; then
  head -n -1 "$WORK/ref_heavy" > "$WORK/control_heavy_dropped_one"
  if totality_holds "$WORK/ref_heavy" "$WORK/control_heavy_dropped_one"; then
    fail "POSITIVE CONTROL (heavy): the totality comparison reports two sets differing by one registration as IDENTICAL."
  else
    pass "positive control (heavy): the totality comparison detects a single dropped registration"
  fi
else
  fail "POSITIVE CONTROL (heavy) could not run — the heavy reference set is empty"
fi

# --- Non-canonical K rows, bounded by the group's registration count ---------------------------
#
# K must stay <= REF_H: a leg index beyond the registration count is syntactically valid but
# owns nothing and must REFUSE (pinned separately below), so it cannot be traversed as a
# totality case. For the 3-member group, {2,3} exercises 2+1 and 1+1+1 — both still total.
for altK in 2 3; do
  if (( altK > REF_H )); then continue; fi
  declare -a _alth_pids=()
  _alt_i=0
  for k in $(seq 1 "$altK"); do
    enumerate_leg "$k/$altK" "$WORK/alt_hleg_${altK}_${k}" scripts-heavy &
    _alth_pids[$_alt_i]=$!
    _alt_i=$(( _alt_i + 1 ))
  done
  : > "$WORK/alt_hunion"
  _alt_i=0
  for k in $(seq 1 "$altK"); do
    _rc=0; wait "${_alth_pids[$_alt_i]}" || _rc=$?
    _alt_i=$(( _alt_i + 1 ))
    if (( _rc != 0 )); then
      fail "non-canonical heavy K=$altK leg $k enumerate child exited $_rc — the union below is built from a lost leg"
    fi
    cat "$WORK/alt_hleg_${altK}_${k}" >> "$WORK/alt_hunion"
  done
  _an=$(wc -l < "$WORK/alt_hunion" | tr -d ' ')
  sort -u "$WORK/alt_hunion" > "$WORK/alt_hsorted"
  _au=$(wc -l < "$WORK/alt_hsorted" | tr -d ' ')
  if (( _an == _au )) && diff -q "$WORK/ref_heavy" "$WORK/alt_hsorted" >/dev/null 2>&1; then
    pass "non-canonical heavy K=$altK is also total and duplicate-free"
  else
    fail "heavy K=$altK is not total/duplicate-free ($_an assignments, $_au distinct, reference $REF_H) — the heavy partition is correct only for the configured K"
  fi
done

# --- A valid spec BEYOND the heavy registration count is refused, not traversed ----------------
#
# SCRIPTS_SHARD=4/5 over a 3-registration group passes every syntactic check and matches no
# ordinal — the leg must hit the zero-assignment refusal (exit 2) rather than report green over
# zero coverage. Assert the message, not just the rc.
# The remaining heavy probes are all independent children — fanned out together
# (1 over-spec + 4 malformed + 1 webplat + 1 unset + 1 TEST_GROUP=all = 8),
# each writing its own $WORK file, evaluated serially below in declared order.
_over_h=$(( REF_H + 1 ))
# `${_over_h}/${_over_h}` (not a literal denominator): the spec must stay VALID-but-
# unassignable at any REF_H — a hardcoded N breaks the row the day the group grows past it.
env SCRIPTS_SHARD="${_over_h}/${_over_h}" TEST_GROUP=scripts-heavy SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts-heavy >/dev/null 2>"$WORK/over_h_err" &
_over_h_pid=$!

declare -a _malh_specs=() _malh_pids=()
_malh_n=0
for bad in "0/3" "abc" "" "１/３"; do
  _malh_specs[$_malh_n]="$bad"
  env SCRIPTS_SHARD="$bad" TEST_GROUP=scripts-heavy SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$RUNNER" --enumerate scripts-heavy >/dev/null 2>&1 &
  _malh_pids[$_malh_n]=$!
  _malh_n=$(( _malh_n + 1 ))
done

env SCRIPTS_SHARD="1/3" TEST_GROUP=webplat SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate webplat >/dev/null 2>&1 &
_webplat_pid=$!

env -u SCRIPTS_SHARD TEST_GROUP=scripts-heavy SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate scripts-heavy 2>/dev/null \
  | grep '^SUITE_REGISTRATION' | cut -f2 | sort -u > "$WORK/unset_heavy" &
_unset_h_pid=$!

env -u SCRIPTS_SHARD TEST_GROUP=all SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate all 2>/dev/null \
  | grep '^SUITE_REGISTRATION' | cut -f2 | sort -u > "$WORK/enum_all" &
_enum_all_pid=$!

wait "$_over_h_pid" || true
_over_h_err=$(cat "$WORK/over_h_err")
if grep -qF 'assigned 0 of' <<<"$_over_h_err"; then
  pass "a valid-but-empty heavy assignment (${_over_h}/5, beyond $REF_H registrations) is refused by the zero-assignment check"
else
  fail "SCRIPTS_SHARD=${_over_h}/5 under scripts-heavy was not refused (got: ${_over_h_err:-<no output>}) — the leg would report green over zero coverage"
fi

# --- The heavy group obeys the SAME malformed-spec refusal -------------------------------------
_mal_h_ok=1
for (( _mi = 0; _mi < _malh_n; _mi++ )); do
  _rc=0; wait "${_malh_pids[$_mi]}" || _rc=$?
  if (( _rc != 2 )); then
    _mal_h_ok=0
    fail "malformed SCRIPTS_SHARD='${_malh_specs[$_mi]}' under scripts-heavy exited $_rc, expected 2 (fail closed)"
  fi
done
if (( _mal_h_ok == 1 )); then
  pass "every malformed SCRIPTS_SHARD spec fails closed with exit 2 under scripts-heavy"
fi

# --- The scope widening did NOT open other groups -----------------------------------------------
#
# The runner's group-scope refusal was widened to {scripts, scripts-heavy}; this row pins the
# boundary it must NOT have crossed: SCRIPTS_SHARD on an unrelated group still refuses.
_rc=0; wait "$_webplat_pid" || _rc=$?
if (( _rc == 2 )); then
  pass "SCRIPTS_SHARD on an unrelated group (webplat) is still refused — the scope widening stayed scoped"
else
  fail "SCRIPTS_SHARD under TEST_GROUP=webplat exited $_rc, expected 2 — the widened group-scope check admits groups it must refuse"
fi

# --- Unset runs the full heavy group -----------------------------------------------------------
wait "$_unset_h_pid" || fail "unset-SCRIPTS_SHARD heavy enumerate pipeline exited nonzero — its output file cannot be trusted"
_un_h=$(sort -u "$WORK/unset_heavy" | wc -l | tr -d ' ')
if (( _un_h == REF_H )); then
  pass "SCRIPTS_SHARD unset enumerates the full heavy group ($_un_h) — local runs are unaffected"
else
  fail "SCRIPTS_SHARD unset enumerated $_un_h heavy registrations, expected the full $REF_H"
fi

# --- TEST_GROUP=all still covers the heavy group ------------------------------------------------
#
# `want_scripts_heavy` includes `all` so the ship gate, lefthook and main-health-monitor keep
# running the heavy suites. If the want_* helper drops `all`, the three most expensive suites
# silently leave every full-gate run — and nothing else here notices (this file scopes its
# other rows to per-group enumeration).
wait "$_enum_all_pid" || fail "TEST_GROUP=all enumerate pipeline exited nonzero — its output file cannot be trusted"
_missing_all=$(comm -23 "$WORK/ref_heavy" "$WORK/enum_all" | tr '\n' ' ')
if [[ -z "$_missing_all" ]]; then
  pass "TEST_GROUP=all covers every heavy registration — the full gate cannot silently lose them"
else
  fail "TEST_GROUP=all is missing heavy registration(s): $_missing_all — want_scripts_heavy dropped the 'all' arm, so the ship gate and monitor silently lost the most expensive suites"
fi

# Shared contiguous-tiling comparator — walks a file of `A-B` ranges and returns whether they
# tile 1..DECLARED with no gaps or overlaps. NOTE for future callers: ranges must be sorted by
# lo-bound BEFORE this call, the input must be newline-terminated (a `read` loop drops an
# unterminated last line), and the caller must not sort a file that could contain malformed
# entries (a sort key of "-" would reorder them silently).
_rows_tile_check() {
  # args: <ranges-file (one A-B per line)> <declared-total>
  # rc 0 = tiles; rc 1 = _tile_why carries the reason.
  local _rf="$1" _decl="$2" _expect=1 _rr _ra _rb
  _tile_why=""
  while IFS= read -r _rr; do
    [[ -n "$_rr" ]] || continue
    if [[ ! "$_rr" =~ ^([0123456789]+)-([0123456789]+)$ ]]; then
      _tile_why="malformed range '$_rr'"; return 1
    fi
    _ra=$((10#${BASH_REMATCH[1]})); _rb=$((10#${BASH_REMATCH[2]}))
    if (( _ra != _expect )); then
      _tile_why="range '$_rr' starts at $_ra, expected $_expect (gap or overlap)"; return 1
    fi
    _expect=$(( _rb + 1 ))
  done < "$_rf"
  if (( _expect == 1 )); then
    _tile_why="no --rows ranges extracted — a DECLARED_TOTAL-declaring battery must carry at least one"; return 1
  fi
  if (( _expect != _decl + 1 )); then
    if (( _expect > _decl + 1 )); then
      _tile_why="ranges overshoot DECLARED_TOTAL=$_decl (reached $((_expect - 1))) — a range selects rows the battery refuses to execute"
    else
      _tile_why="ranges end at $((_expect - 1)), DECLARED_TOTAL is $_decl — rows ${_expect}..${_decl} execute in no leg"
    fi
    return 1
  fi
  return 0
}

# --- The mutation battery's CI row ranges must TILE 1..DECLARED_TOTAL --------------------------
#
# The battery's own accounting is per-leg: every matrix leg asserts _row_seq reached
# DECLARED_TOTAL and EXECUTED == its in-range count. What per-leg accounting cannot see is a
# GAP between the legs' ranges — a new mutation row plus a bumped DECLARED_TOTAL without a
# matrix re-split executes in NO CI leg while every leg's own checks stay green (shrink
# fails closed: B > DECLARED_TOTAL exits 2 in the flag validator; growth is silent).
# Assert the disjoint contiguous tiling here, where the drift shows up.
_decl_total="$(sed -nE 's/^DECLARED_TOTAL=([0123456789]+)([[:space:]].*)?$/\1/p' "$REPO_ROOT/plugins/soleur/test/scripts-shard-totality-mutations.sh" | head -1)"
awk '
  /^  shard-totality-mutations:$/ { inj=1; next }
  inj && /^  [a-z0-9_-]+:$/ { inj=0 }
  inj && /rows:/ {
    line=$0
    gsub(/.*rows:[[:space:]]*\[/, "", line); gsub(/\].*/, "", line)
    n=split(line, a, ",")
    for (i=1; i<=n; i++) { gsub(/[" \t]/, "", a[i]); if (a[i] != "") print a[i] }
  }
' "$CI_YML" | sort -t- -k1,1n > "$WORK/row_ranges"
if [[ -z "$_decl_total" || ! "$_decl_total" =~ ^[0123456789]+$ ]]; then
  fail "could not read DECLARED_TOTAL from the mutation battery — the tiling check is ungrounded"
elif [[ ! -s "$WORK/row_ranges" ]]; then
  fail "ci.yml's shard-totality-mutations declares no rows: ranges — the battery is not split as declared (an unsplit job must not ship a --rows contract it ignores)"
elif _rows_tile_check "$WORK/row_ranges" "$_decl_total"; then
  pass "ci.yml mutation row ranges tile 1..$_decl_total contiguously ($(tr '\n' ' ' < "$WORK/row_ranges"))"
else
  fail "mutation row ranges do not tile 1..$_decl_total: $_tile_why — rows outside the union execute nowhere while every leg's own accounting stays green"
fi

# Wire check on the SAME job block: the `rows:` key must reach the run step as an
# interpolation. A literal `run: bash … --rows "1-12"` would execute one slice on EVERY leg
# while the declared matrix stays green — same "declared ≠ received" class the SCRIPTS_SHARD
# wire pin upstream exists for.
_rows_wire=$(awk '
  /^  shard-totality-mutations:$/ { inj=1; next }
  inj && /^  [A-Za-z0-9_-]+:$/ { exit }
  inj && /--rows[[:space:]]/ && /matrix\.rows/ { n++ }
  END { print n+0 }
' "$CI_YML")
if [[ "$_rows_wire" == "1" ]]; then
  pass "shard-totality-mutations run step consumes \${{ matrix.rows }} — declared legs cannot run one shared literal range"
else
  fail "shard-totality-mutations job has ${_rows_wire} run-step lines pairing --rows with \${{ matrix.rows }} — a literal range on the run step would execute the same slice on every leg while the matrix stays declared"
fi

# Singleton census: this arm is anchored on the ONE ci.yml rows: matrix. A second rows: key
# splitting another battery would arrive unguarded — its arrival must be loud here, not
# silently outside the property.
_rows_keys=$(grep -cE '^[[:space:]]+rows:' "$CI_YML" || true)
if (( _rows_keys == 1 )); then
  pass "ci.yml carries exactly one rows: matrix key — the arm's singleton scope is current"
else
  fail "ci.yml has ${_rows_keys} rows: matrix keys — this arm covers only shard-totality-mutations; the new job needs its own arm (or generalize this one)"
fi

# --- run_suite-carried --rows ranges must TILE their battery's DECLARED_TOTAL -----------------
#
# The same hole as the ci.yml-matrix check above, at the OTHER split site: a suite split via
# `run_suite "…-a" bash <file>.test.sh --rows A-B` distributes through the shard manifest —
# there is no ci.yml `rows:` key to read (#8864). The battery's per-leg equality floors
# (_site_seq == DECLARED_TOTAL, EXECUTED == range size) cannot see a gap BETWEEN the
# registered ranges: a DECLARED_TOTAL bump without a re-split runs the new rows in NO leg
# while every leg's own accounting stays green.
#
# EXTRACTION anchors on the run_suite CALL SHAPE and the flag argument — never the label
# (#7103). `#`-onward is stripped PER PHYSICAL LINE before backslash-continuation joining, so
# comment text can neither fabricate nor hide a range — and a comment (full-line or trailing)
# ending in \ cannot swallow a following registration because its backslash is inside the
# stripped span. skip_suite lines are declines — never counted. Quantified PER COMMAND TOKEN:
# a future second --rows suite is checked the day it registers — on ANY command shape, not
# just `bash *.test.sh` (the precedent battery itself is `bash foo-mutations.sh`; an
# unresolvable command token is emitted as <unresolved> and dies at the DECLARED_TOTAL arm).

# Extract: <label>\t<command-token>\t<A-B|UNFLAGGED>, one row per run_suite registration.
# UNFLAGGED rows are emitted only for resolvable `bash <file>.sh` commands — an unflagged
# registration of an unresolvable command carries no checkable DECLARED_TOTAL anyway.
# Command tokens containing `..` are rejected — the token later indexes $REPO_ROOT/… file
# reads, and path traversal has no legitimate spelling here.
awk '
  { line=$0; sub(/#.*/, "", line)
    while (line ~ /\\[[:space:]]*$/) {
      sub(/\\[[:space:]]*$/, "", line)
      if (getline nl) { sub(/#.*/, "", nl); line = line nl } else break
    }
    if (line !~ /^[[:space:]]*run_suite[[:space:]]/) next
    cmd=""
    if (match(line, /bash[[:space:]]+"?[A-Za-z0-9._\/-]+\.sh"?/)) {
      cmd=substr(line, RSTART, RLENGTH); sub(/^bash[[:space:]]+"?/, "", cmd); sub(/"$/, "", cmd)
      if (cmd ~ /\.\./) cmd=""
    }
    label=line; sub(/^[[:space:]]*run_suite[[:space:]]+"?/, "", label); sub(/".*/, "", label)
    if (match(line, /--rows[[:space:]]+[0123456789]{1,9}-[0123456789]{1,9}/)) {
      r=substr(line, RSTART, RLENGTH); sub(/--rows[[:space:]]+/, "", r)
      print label "\t" (cmd != "" ? cmd : "<unresolved>") "\t" r
    } else if (cmd != "") {
      print label "\t" cmd "\tUNFLAGGED"
    }
  }
' "$RUNNER" > "$WORK/run_suite_rows"

# Tokens of interest, in two passes (one each), not a per-token rescan:
#  a) every token with at least one --rows registration
#  b) every resolvable token whose battery file declares DECLARED_TOTAL — the non-vacuity arm:
#     declaring the contract while registering unflagged (or registering a ci.yml-split
#     battery without ranges) is exactly the drift this block exists to redden.
awk -F'\t' '$3 != "UNFLAGGED" { print $2 }' "$WORK/run_suite_rows" | sort -u > "$WORK/rs_flagged_tokens"
awk -F'\t' -v root="$REPO_ROOT" '$2 != "<unresolved>" && $2 != "" { print root "/" $2 }' "$WORK/run_suite_rows" | sort -u > "$WORK/rs_token_files"
_token_files=()
while IFS= read -r _f; do _token_files+=("$_f"); done < "$WORK/rs_token_files"
: > "$WORK/rs_decl_tokens"
if (( ${#_token_files[@]} > 0 )); then
  grep -lE '^DECLARED_TOTAL=[0123456789]+' "${_token_files[@]}" 2>/dev/null | sed -e "s|^${REPO_ROOT}/||" | sort -u > "$WORK/rs_decl_tokens" || true
fi
sort -u "$WORK/rs_flagged_tokens" "$WORK/rs_decl_tokens" > "$WORK/rs_interesting"

while IFS= read -r _tok; do
  # Per-token state
  awk -F'\t' -v t="$_tok" '$2==t && $3!="UNFLAGGED" {print $1 "\t" $3}' "$WORK/run_suite_rows" > "$WORK/rs_flagged"
  _unflagged_n=$(awk -F'\t' -v t="$_tok" '$2==t && $3=="UNFLAGGED"' "$WORK/run_suite_rows" | wc -l | tr -d ' ')
  _decl="$( [[ -f "$REPO_ROOT/$_tok" ]] && sed -nE 's/^DECLARED_TOTAL=([0123456789]+)([[:space:]].*)?$/\1/p' "$REPO_ROOT/$_tok" | head -1 )"
  _ranges_n=$(wc -l < "$WORK/rs_flagged" | tr -d ' ')

  _decl_lines="$( [[ -f "$REPO_ROOT/$_tok" ]] && grep -cE '^DECLARED_TOTAL=' "$REPO_ROOT/$_tok" || echo 0 )"
  if [[ "$_decl_lines" != "0" && "$_decl_lines" != "1" ]]; then
    fail "${_tok} assigns DECLARED_TOTAL ${_decl_lines} times — bash honors the LAST assignment but this guard reads the first; reconcile to exactly one file-scope declaration"
    continue
  fi
  if [[ -z "$_decl" ]]; then
    _labels="$(cut -f1 "$WORK/rs_flagged" | tr '\n' ' ')"
    fail "run_suite carries --rows for ${_tok} (labels: ${_labels% }) but that battery declares no DECLARED_TOTAL — an unsplit job must not ship a --rows contract it ignores"
    continue
  fi
  if (( _ranges_n == 0 )); then
    fail "${_tok} declares DECLARED_TOTAL=${_decl} but its ${_unflagged_n} run_suite registration(s) carry no --rows — the declared split is ignored and every row executes on every registration"
    continue
  fi
  if (( _unflagged_n > 0 )); then
    fail "${_tok} has a MIXED --rows contract: ${_unflagged_n} registration(s) unflagged beside ${_ranges_n} flagged — a dropped flag double-executes rather than loses coverage; state the flag on every registration"
    continue
  fi

  # Sort by lo-bound — registration order in test-all.sh is not the tiling order. The awk
  # extractor only emits `^[0-9]+-[0-9]+$` shapes, so sorting cannot reorder malformed
  # entries (the hazard the comparator's header warns about).
  cut -f2 "$WORK/rs_flagged" | sort -t- -k1,1n > "$WORK/rs_ranges_sorted"
  if _rows_tile_check "$WORK/rs_ranges_sorted" "$_decl"; then
    pass "${_tok}: --rows ranges tile 1..${_decl} contiguously ($(tr '\n' ' ' < "$WORK/rs_ranges_sorted"))"
  else
    fail "${_tok}: --rows ranges do not tile 1..${_decl}: ${_tile_why} — rows outside the union execute nowhere while every leg's own accounting stays green"
    continue
  fi

  # Distinct-legs pin, two reads:
  #  (a) the COMMITTED manifests — a --rows label must be pinned on a leg distinct from its
  #      siblings; an unpinned label leaves placement to the cksum fallback, which can put
  #      both halves on one leg while coverage stays total. Read against the committed TSVs
  #      regardless of SOLEUR_SHARD_MANIFEST[_HEAVY] overrides — those are fixture seams, and
  #      a fixture's own manifest says nothing about the committed pins.
  #  (b) the REALIZED legs (enumerated leg_*/hleg_* files) — only when no manifest override
  #      is bound: under a fixture manifest the halves legitimately hash-fall wherever the
  #      fixture sends them (an empty manifest keeping coverage total is a GREEN contract —
  #      co-location under fallback is wasted leg time, not lost coverage).
  if (( _ranges_n >= 2 )); then
    _legs_ok=1; : > "$WORK/rs_legs"; : > "$WORK/rs_rlegs"
    while IFS=$'\t' read -r _lbl _rr; do
      _leg="$(awk -F'\t' -v l="$_lbl" '$1 == l { print $2; exit }' "$REPO_ROOT/scripts/suite-shard-legs.tsv" "$REPO_ROOT/scripts/suite-shard-legs-heavy.tsv" 2>/dev/null | head -1)"
      if [[ -z "$_leg" ]]; then
        fail "${_tok}: --rows registration '${_lbl}' is not pinned in either shard manifest — its leg is unverifiable (hash-fallback could co-locate the halves)"
        _legs_ok=0; break
      fi
      echo "$_leg" >> "$WORK/rs_legs"
      if [[ -z "${SOLEUR_SHARD_MANIFEST:-}" && -z "${SOLEUR_SHARD_MANIFEST_HEAVY:-}" ]]; then
        _hit="$(grep -lxF "$_lbl" "$WORK"/leg_* "$WORK"/hleg_* 2>/dev/null | head -1)"
        [[ -n "$_hit" ]] && basename "$_hit" >> "$WORK/rs_rlegs"
      fi
    done < "$WORK/rs_flagged"
    if (( _legs_ok == 1 )); then
      _uniq=$(sort -u "$WORK/rs_legs" | wc -l | tr -d ' ')
      if (( _uniq != _ranges_n )); then
        fail "${_tok}: --rows halves pin to legs $(tr '\n' ' ' < "$WORK/rs_legs" | sed 's/ /,/g;s/,$//') — two halves on the same leg defeats the split while coverage stays total"
      else
        pass "${_tok}: ${_ranges_n} --rows registrations pin to distinct legs ($(tr '\n' ' ' < "$WORK/rs_legs"))"
      fi
      if [[ -s "$WORK/rs_rlegs" ]]; then
        _runiq=$(sort -u "$WORK/rs_rlegs" | wc -l | tr -d ' ')
        if (( _runiq != _ranges_n )); then
          fail "${_tok}: --rows halves REALIZE onto $(tr '\n' ' ' < "$WORK/rs_rlegs" | sed 's/ /,/g;s/,$//') — the committed pins are distinct but the runner's enumerated assignment co-locates them (fallback or manifest disengagement)"
        fi
      fi
    fi
  fi
done < "$WORK/rs_interesting"

# --- Population completeness, both directions -------------------------------------------------
#
# Direction 1: every literal `--rows A-B` in the runner (and the sourced libs it could hide
# inside) must have been extracted as a flagged row. A range inside a non-line-start
# `x && run_suite …`, an `eval`, a doubled `--rows` on one line, or a heredoc would leave the
# checked population silently while the extractor stays green.
_lit_n=$( { sed 's/#.*//' "$RUNNER"; sed 's/#.*//' "$REPO_ROOT"/scripts/lib/*.sh 2>/dev/null; } | grep -oE -- '--rows[[:space:]]+[0123456789]{1,9}-[0123456789]{1,9}' | wc -l | tr -d ' ')
_emit_n=$(awk -F'\t' '$3 != "UNFLAGGED"' "$WORK/run_suite_rows" | wc -l | tr -d ' ')
if (( _lit_n == _emit_n )); then
  pass "literal census: ${_lit_n} '--rows A-B' occurrences in test-all.sh+scripts/lib, all ${_emit_n} extracted"
else
  fail "literal census: ${_lit_n} '--rows A-B' occurrences in test-all.sh/scripts/lib but ${_emit_n} extracted — a range lives outside the line-start run_suite shape (eval, sourced lib, mid-line call, or a doubled flag on one line)"
fi

# Direction 2: every file-scope DECLARED_TOTAL declaration in the suite-bearing trees must be
# reachable by one of the two tiling arms — a --rows battery glob-registered via
# `run_suite "$f"`, registered via a non-bash command shape, or invoked from a sourced lib is
# invisible to the extractor and lands HERE.
grep -rlE '^[[:space:]]*DECLARED_TOTAL=[0123456789]+' "$REPO_ROOT/scripts" "$REPO_ROOT/plugins/soleur/test" 2>/dev/null | sort -u > "$WORK/decl_census"
grep -oE 'bash[[:space:]]+[A-Za-z0-9._/-]+\.sh[[:space:]]+--rows[[:space:]]+"?\$\{\{[[:space:]]*matrix\.rows' "$CI_YML" | awk '{print $2}' | sort -u > "$WORK/ciyml_rows_files"
_census_ok=1
while IFS= read -r _df; do
  _rel="${_df#$REPO_ROOT/}"
  if awk -F'\t' -v t="$_rel" '$2==t {f=1} END{exit !f}' "$WORK/run_suite_rows"; then
    continue
  elif grep -qxF "$_rel" "$WORK/ciyml_rows_files"; then
    continue
  else
    fail "DECLARED_TOTAL-declaring file '${_rel}' is registered in NEITHER run_suite argv nor a ci.yml rows: run step — a range contract this guard cannot tile (glob-loop registration? sourced-lib battery?)"
    _census_ok=0
  fi
done < "$WORK/decl_census"
if (( _census_ok == 1 )); then
  pass "DECLARED_TOTAL census: every declaring file is reachable by a tiling arm ($(wc -l < "$WORK/decl_census" | tr -d ' ') files)"
fi

if [[ ! -s "$WORK/rs_interesting" ]]; then
  fail "extracted ZERO --rows-carrying or DECLARED_TOTAL-declaring registrations — the extractor drifted blind, so every verdict above is vacuous"
fi

# POSITIVE CONTROL on the range-tiling comparator — feed it a gapped union (1-8 + 10-16 vs
# DECLARED_TOTAL=16) and require the gap to be reported. Without this row, the comparator can
# be neutered to always-succeed and every tiling verdict above is decorative (mirrors the
# totality_holds positive control upstream).
printf '1-8\n10-16\n' > "$WORK/rs_control_ranges"
if _rows_tile_check "$WORK/rs_control_ranges" 16; then
  fail "POSITIVE CONTROL: the --rows tiling comparator reports a gapped union (1-8 + 10-16 vs DECLARED_TOTAL=16) as TILED. It is neutered, so every run_suite --rows verdict above is decorative."
else
  pass "positive control: the --rows tiling comparator detects the gap (${_tile_why})"
fi

# --- ASSERTION FLOOR --------------------------------------------------------------------------
#
# Reported with printf + exit 1, NEVER through fail() — the helper this floor exists to
# backstop is exactly the thing one edit disarms (ADR-193).
MIN_ROWS=45
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
