#!/usr/bin/env bash
#
# MUTATION BATTERY for Guard 1 (#7902 AC12).
#
# Guard 1 (plugins/soleur/test/scripts-shard-totality.test.sh) asserts that every scripts-group
# registration is assigned to exactly one matrix leg. A guard that cannot be driven RED is
# vacuous, so this battery breaks the partition eight ways and requires the guard to notice
# each one.
#
# HOW THIS BATTERY AVOIDS THE FAILURES ITS OWN CLASS IS KNOWN FOR:
#
#   * It restores from a PRISTINE COPY taken before row 1, never `git checkout`. A battery that
#     restores to HEAD reverts an UNCOMMITTED fix and then scores the defect against itself.
#   * It runs the UNMUTATED CONTROL FIRST. A battery whose control is not green is VOID, not
#     passing, and every row below it is then arbitrary.
#   * It asserts each mutation LANDED (`cmp` against the pristine copy) before reading a
#     verdict. A mutation that did not land reports the BASELINE, which is indistinguishable
#     from a survivor.
#   * It anchors on exact unique strings and refuses an ambiguous anchor, rather than a
#     file-wide `sed`. scripts/test-all.sh is ~2400 lines with ~200 near-identical run_suite
#     lines, so an unanchored substitution silently rewrites a different registration and the
#     guard then reports a baseline that looks like a pass.
#   * It restores and RE-VERIFIES after every row, and fails loudly if a restore did not take.
#
# DELIBERATELY NOT NAMED `*.test.sh`, and that is a correctness constraint, not a style choice.
# `plugins/soleur/test/*.test.sh` is glob-discovered into the scripts group, so under that name
# this battery would be registered as a suite and run INSIDE a `scripts/test-all.sh` run — while
# mutating `scripts/test-all.sh` itself. Bash reads a script incrementally by byte offset, so an
# in-place edit can change what the ALREADY-RUNNING parent goes on to execute, and the resulting
# failures look like plausible test results rather than corruption. The repo's other mutation
# batteries (`tests/scripts/registry-gate-mutation-battery`,
# `scripts/cf-tunnel-liveness-gate-mutations`) drop the suffix for the same family of reasons.
#
# It runs instead from its own dedicated `shard-totality-mutations` job in ci.yml, whose checkout
# is exclusive to it. That job is also what satisfies AC14 unambiguously: a NON-SHARDED job that
# drives the enumerate mode K times and can therefore observe a cross-leg union.
#
# set -u, not -e: accumulate-then-exit.
# repo-write-boundary-sandbox: not-needed
#
# This battery relocates scripts/test-all.sh (it snapshots the pristine runner and restores it
# around each mutation), which is what makes scripts/lib/repo-write-boundary.test.sh enumerate it.
# It does NOT need the boundary lib, because it never drives the runner down a path that can write
# to the repo: every invocation goes through Guard 1, which calls `test-all.sh --enumerate`, and
# that mode returns at the enumerate terminator BEFORE the repo-write-boundary epilogue and starts
# no suite at all. The only writes this file performs are its own `cp` snapshot/restore of the
# runner, which the EXIT trap reverses and which the dirty-tree refusal at the top makes visible.
#
# If a future row ever runs the runner in EXECUTING mode, this declaration is wrong: copy
# scripts/lib/repo-write-boundary.sh into the sandbox instead of carrying this marker.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
GUARD="$REPO_ROOT/plugins/soleur/test/scripts-shard-totality.test.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

PASS=0
FAIL=0
pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; }

WORK="$(mktemp -d -t shard-mut.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }

PRISTINE_RUNNER="$WORK/test-all.sh.pristine"
PRISTINE_GUARD="$WORK/guard.pristine"
PRISTINE_CI="$WORK/ci.yml.pristine"
cp "$RUNNER" "$PRISTINE_RUNNER" || { echo "FATAL: pristine copy failed" >&2; exit 2; }
cp "$GUARD"  "$PRISTINE_GUARD"  || { echo "FATAL: pristine copy failed" >&2; exit 2; }
cp "$CI_YML" "$PRISTINE_CI"     || { echo "FATAL: pristine copy failed" >&2; exit 2; }

restore_all() {
  cp "$PRISTINE_RUNNER" "$RUNNER"
  cp "$PRISTINE_GUARD"  "$GUARD"
  cp "$PRISTINE_CI"     "$CI_YML"
}
# Restore on ANY exit path, including an abort mid-row. Leaving a mutated runner on disk would
# poison every later suite in the same run.
trap 'restore_all; rm -rf "$WORK"' EXIT

# REFUSE TO RUN ON A DIRTY TARGET (#7902 review). This battery mutates tracked files in place and
# restores them from a pristine copy taken at ITS start — so a concurrent edit to any target is
# silently REVERTED when it exits, with no error and no diff. That is not hypothetical: it ate a
# set of guard fixtures during this PR's own review, and the loss is invisible until something
# downstream reports a stale row count.
#
# In CI the checkout is exclusive and clean, so this never fires. Locally it is the difference
# between a safe run and silent data loss. Override deliberately with SHARD_BATTERY_ALLOW_DIRTY=1
# if you are certain the pending changes are yours and disposable.
if [[ "${SHARD_BATTERY_ALLOW_DIRTY:-}" != "1" ]]; then
  _dirty=$(cd "$REPO_ROOT" && git status --porcelain -- \
    scripts/test-all.sh \
    .github/workflows/ci.yml \
    plugins/soleur/test/scripts-shard-totality.test.sh 2>/dev/null || true)
  if [[ -n "${_dirty//[[:space:]]/}" ]]; then
    echo "REFUSING: this battery mutates and then RESTORES its targets, which would discard the" >&2
    echo "          uncommitted changes below. Commit or stash them first, or set" >&2
    echo "          SHARD_BATTERY_ALLOW_DIRTY=1 if they are disposable." >&2
    printf '%s\n' "$_dirty" >&2
    exit 2
  fi
fi

echo "=== Guard 1 mutation battery (#7902 AC12) ==="

# --- Instrument self-test (ADR-193) ---------------------------------------------------------
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)"
fail "instrument self-test (expected — subtracted)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  echo "FATAL: instrument self-test did not move both counters." >&2
  exit 2
fi
PASS=$_p0; FAIL=$_f0
echo "  (instrument self-test OK — both counters move; counters reset)"

# --- Mechanics -------------------------------------------------------------------------------

# Apply one exact-anchor substitution to a file. Refuses a missing or ambiguous anchor, and
# refuses a substitution that did not change the file.
mutate() {
  local file="$1" old="$2" new="$3"
  python3 - "$file" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
n = s.count(old)
if n == 0:
    sys.stderr.write("ANCHOR MISSING\n"); sys.exit(3)
if n > 1:
    sys.stderr.write("ANCHOR AMBIGUOUS (%d occurrences)\n" % n); sys.exit(4)
open(path, "w").write(s.replace(old, new, 1))
PY
}

# Run the guard and report its exit code. The guard is the SUT here.
guard_rc() {
  # `env -u CI` IS LOAD-BEARING (#7902 review round 2, found by CI itself).
  #
  # Under CI the relevance gate's bypass is an UNCONDITIONAL early return, so a decline is
  # unreachable and `skip_suite` is never invoked — the runner takes the `run_suite` arm at every
  # relevance-gated site. ROW7's mutation removes the shard filter from `skip_suite`, so in that
  # environment it edits a function nobody calls: the guard stays GREEN and the row reports
  # SURVIVOR. Measured — the battery was 13/13 locally and 12/13 on the runner, failing on ROW7
  # alone, which is the signature of a fixture that cannot reach the code it mutates.
  #
  # Clearing CI here makes declines reachable, so both registration arms are exercised and every
  # row scores against the richer population. It does not weaken the other rows: they mutate the
  # partition itself, which is arm-independent.
  env -u CI bash "$GUARD" > "$WORK/guard_out" 2>&1
  echo $?
}

# One mutation row, end to end: apply -> assert landed -> read verdict -> restore -> re-verify.
row() {
  local id="$1" file="$2" old="$3" new="$4" want="$5" desc="$6"
  local pristine
  case "$file" in
    "$RUNNER") pristine="$PRISTINE_RUNNER" ;;
    "$GUARD")  pristine="$PRISTINE_GUARD" ;;
    "$CI_YML") pristine="$PRISTINE_CI" ;;
    *) fail "$id — unknown file $file"; return ;;
  esac

  if ! mutate "$file" "$old" "$new" 2>"$WORK/muterr"; then
    fail "$id — mutation could not be applied: $(cat "$WORK/muterr"). The anchor no longer matches the source, so this row measured NOTHING."
    cp "$pristine" "$file"
    return
  fi
  if cmp -s "$pristine" "$file"; then
    fail "$id — mutation DID NOT LAND (file byte-identical to pristine). A verdict read now would be the baseline, not the mutant."
    cp "$pristine" "$file"
    return
  fi

  local rc; rc=$(guard_rc)
  cp "$pristine" "$file"
  if ! cmp -s "$pristine" "$file"; then
    echo "FATAL: restore of $file did not take — later rows would score against a mutated tree." >&2
    exit 2
  fi

  if [[ "$want" == "RED" ]]; then
    if (( rc != 0 )); then
      pass "$id — guard went RED as required ($desc)"
    else
      fail "$id — SURVIVOR: guard stayed GREEN under '$desc'. Either the fixtures do not exercise the property, or the mutant is equivalent — decide which; do not leave it unlabelled."
    fi
  else
    if (( rc == 0 )); then
      pass "$id — guard stayed GREEN as required ($desc)"
    else
      fail "$id — guard went RED on a must-PASS input ($desc); it is over-tight: $(tail -3 "$WORK/guard_out" | tr '\n' ' ')"
    fi
  fi
}

# --- CONTROL: the unmutated tree must be GREEN ----------------------------------------------
#
# Read FIRST. If the control is not green the whole battery is VOID rather than passing, and
# every row below would be scored against a broken baseline.
_control_rc=$(guard_rc)
if (( _control_rc == 0 )); then
  pass "CONTROL — the unmutated tree is GREEN, so every row below scores a real mutation"
else
  echo "FATAL: CONTROL IS RED (exit $_control_rc). This battery is VOID, not failing." >&2
  tail -20 "$WORK/guard_out" >&2
  exit 2
fi

# --- Row 1: off-by-one in the partition -------------------------------------------------------
# Residue class 0 is then matched by no k, so ~1/N of all registrations run on no leg while
# every declared leg reports green.
row "ROW1" "$RUNNER" \
  '(( (_shard_ordinal - 1) % _SHARD_N != _SHARD_K - 1 ))' \
  '(( (_shard_ordinal - 1) % _SHARD_N != _SHARD_K ))' \
  RED "off-by-one: residue class 0 assigned to no leg"

# --- Row 2: enumerate mode returns nothing ----------------------------------------------------
# A guard reporting "0 checked" and exiting 0 is vacuous; this proves it does not.
row "ROW2" "$RUNNER" \
  "  printf 'SUITE_REGISTRATION\\t%s\\n' \"\$1\"" \
  "  : # mutated: emit nothing" \
  RED "enumerate mode emits no registrations at all"

# --- Row 3: a registration assigned to no leg -------------------------------------------------
# The reference (static extraction) sees this registration; the runtime never reaches it, so it
# is assigned to no leg. This is the exact shape of a suite that silently stops running.
row "ROW3" "$RUNNER" \
  '  run_suite "scripts/test-all-runtime-ceiling" bash scripts/test-all-runtime-ceiling.test.sh' \
  '  if false; then
    run_suite "MUTANT_ROW3_UNREACHABLE" bash /dev/null
  fi
  run_suite "scripts/test-all-runtime-ceiling" bash scripts/test-all-runtime-ceiling.test.sh' \
  RED "a registration visible to the reference but reachable by no leg"

# --- Row 4: two legs claim the same label -----------------------------------------------------
# Union is correct; the MULTISET is wrong. A totality-only check passes here.
row "ROW4" "$RUNNER" \
  '  if (( _SHARD_N > 0 )) && (( (_shard_ordinal - 1) % _SHARD_N != _SHARD_K - 1 )); then
    return 1
  fi' \
  '  if false; then
    return 1
  fi' \
  RED "every leg claims every registration (union right, multiset wrong)"

# --- Row 5: ci.yml leg count disagrees with N -------------------------------------------------
# Two legs whose values still say /3: leg 3's suites run nowhere and both surviving legs are
# green. A count-based read of the matrix cannot see this.
row "ROW5" "$CI_YML" \
  '        shard: ["1/3", "2/3", "3/3"]' \
  '        shard: ["1/3", "2/3"]' \
  RED "ci.yml declares 2 legs while the partition computes mod 3"

# --- Row 7: filter in run_suite but not skip_suite ---------------------------------------------
# Both increment `suites`. Filtering only one makes every leg emit the skip_suite registrations,
# so per-leg denominators and the epilogue's decline accounting disagree.
row "ROW7" "$RUNNER" \
  '  _shard_selects || return 0
  if (( _ENUMERATE == 1 )); then _shard_enumerate_declined_dispatch "$label" "$rerun"; return 0; fi
  suites=$((suites + 1))
  skipped=$((skipped + 1))' \
  '  if (( _ENUMERATE == 1 )); then _shard_enumerate_declined_dispatch "$label" "$rerun"; return 0; fi
  suites=$((suites + 1))
  skipped=$((skipped + 1))' \
  RED "skip_suite bypasses the shard filter (its registrations land on every leg)"

# --- Row 8: malformed SCRIPTS_SHARD falls back to running nothing ------------------------------
# The green-on-zero-coverage catastrophe: a broken matrix interpolation would make a leg assign
# itself no suites and report success.
row "ROW8" "$RUNNER" \
  '    echo "ERROR: SCRIPTS_SHARD must be k/N with 1 <= k <= N (got: '"'"'${SCRIPTS_SHARD}'"'"')." >&2
    echo "       Unset it to run the full group. A malformed value is never inferred: it fails" >&2
    echo "       closed rather than silently running everything or nothing." >&2
    exit 2
  fi
  _SHARD_K=$(( 10#${BASH_REMATCH[1]} ))' \
  '    _SHARD_K=1; _SHARD_N=1000000; return 0 2>/dev/null || true
  fi
  _SHARD_K=$(( 10#${BASH_REMATCH[1]} ))' \
  RED "a malformed shard spec falls back to assigning (almost) nothing instead of exiting 2"

# --- HARNESS ROW: delete the totality comparison ----------------------------------------------
# Deleting the union comparison while leaving the guard's iteration intact must still drive the
# suite RED — here via the assertion floor, which is why the floor is reported with printf and
# an explicit exit rather than through fail().
row "HARNESS" "$GUARD" \
  '  diff -q "$1" "$2" >/dev/null 2>&1' \
  '  return 0  # mutated: report every pair of sets as identical' \
  RED "totality_holds is neutered to always succeed (must be caught by its positive control)"

# --- Row 6 (META): the reference must NOT be derived from the partition ------------------------
#
# The plan's row 6 is "derive the reference by calling the partition with K=1 — rows 1/3/5 must
# not silently pass". That is a claim about the guard's DERIVATION being load-bearing, so it is
# measured as a pair rather than as a single verdict:
#
#   (a) with the REAL, independently derived reference, ROW3 is RED   — established above;
#   (b) with a K=1 TAUTOLOGY reference, the same ROW3 mutation goes GREEN.
#
# (b) going green is the FINDING, not a failure: it is what proves the independent derivation
# is doing the work. If (b) were also RED, the derivation would be interchangeable and the
# guard's central design claim would be unsupported.
_taut_old='cat "$WORK/ref_static" "$WORK/ref_glob" | sort -u > "$WORK/reference"'
_taut_new='enumerate_leg "1/1" "$WORK/reference"; sort -u "$WORK/reference" -o "$WORK/reference"'
if mutate "$GUARD" "$_taut_old" "$_taut_new" 2>"$WORK/muterr"; then
  if cmp -s "$PRISTINE_GUARD" "$GUARD"; then
    fail "ROW6 — tautology stub did not land; this row measured nothing."
    cp "$PRISTINE_GUARD" "$GUARD"
  else
    # ROW6 is the ONLY row that calls `mutate` directly instead of through row(), so it must
    # re-do row()'s two safety checks by hand (#7902 review, P2). Without them: a drifted anchor
    # makes `mutate` exit non-zero, its stderr is swallowed, the runner is left UNMUTATED, the
    # tautology reference trivially returns 0, and the row prints PASS for "the mutation did not
    # apply" — the exact false-green this file's own header (`A mutation that did not land reports
    # the BASELINE, which is indistinguishable from a survivor`) exists to forbid. The anchor is
    # byte-identical to ROW3's, so drift breaks both: ROW3 loudly, ROW6 silently.
    _row6_ok=1
    if ! mutate "$RUNNER" \
      '  run_suite "scripts/test-all-runtime-ceiling" bash scripts/test-all-runtime-ceiling.test.sh' \
      '  if false; then
    run_suite "MUTANT_ROW6_UNREACHABLE" bash /dev/null
  fi
  run_suite "scripts/test-all-runtime-ceiling" bash scripts/test-all-runtime-ceiling.test.sh'; then
      _row6_ok=0
    fi
    if cmp -s "$PRISTINE_RUNNER" "$RUNNER"; then _row6_ok=0; fi
    if (( _row6_ok == 0 )); then
      fail "ROW6 — the tautology mutation did not land (anchor drifted?); this row measured nothing."
      cp "$PRISTINE_GUARD" "$GUARD"; cp "$PRISTINE_RUNNER" "$RUNNER"
      _taut_rc=-1
    else
    _taut_rc=$(guard_rc)
    cp "$PRISTINE_GUARD" "$GUARD"
    cp "$PRISTINE_RUNNER" "$RUNNER"
    if (( _taut_rc == 0 )); then
      pass "ROW6 — a K=1 tautology reference is BLIND to the ROW3 dropped registration (exit 0) while the real reference catches it. The independent derivation is load-bearing, not decorative."
    else
      fail "ROW6 — the tautology reference ALSO caught the dropped registration. Either the stub did not take effect, or the reference derivation is not what makes this guard work — in which case the guard's central design claim is unsupported and must be re-argued."
    fi
    fi
  fi
else
  fail "ROW6 — could not apply the tautology stub: $(cat "$WORK/muterr")"
fi

# --- Row 9: a syntactically VALID spec that owns nothing -----------------------------------
# k beyond the registration count passes every syntactic check and matches no ordinal. Without
# the post-registration refusal the executing path prints "0/0 suites passed" and exits 0, i.e.
# the required check is green over zero coverage.
row "ROW9" "$RUNNER" \
  'if (( _SHARD_N > 0 && _shard_assigned == 0 )); then' \
  'if false; then' \
  RED "a leg assigned 0 registrations is accepted instead of refused"

# --- Row 10: collation widens the digit class -------------------------------------------------
# `[0-9]` in `[[ =~ ]]` matches fullwidth digits under a UTF-8 collation; `10#` then throws a
# fatal arithmetic error that ABORTS the if-compound and resumes after `fi` with status 0, so
# k/N keep their initial 0 and the leg silently runs the FULL group.
row "ROW10" "$RUNNER" \
  '^([0123456789]{1,9})/([0123456789]{1,9})$' \
  '^([0-9]+)/([0-9]+)$' \
  RED "the digit class is ranged rather than enumerated (collation-widened, unbounded)"

# --- MUST-PASS non-canonical input ------------------------------------------------------------
# Raising a leg's ceiling AND keeping the partition intact must NOT red the guard: it is a
# totality guard, not a performance guard.
row "MUSTPASS" "$CI_YML" \
  '    timeout-minutes: 60
    # No setup-node' \
  '    timeout-minutes: 59
    # No setup-node' \
  GREEN "an unrelated ceiling edit that changes no assignment"

# --- ASSERTION FLOOR ---------------------------------------------------------------------------
MIN_ROWS=12
TOTAL=$(( PASS + FAIL ))
if (( TOTAL < MIN_ROWS )); then
  printf 'FAIL: assertion floor — %d rows executed, expected at least %d. The battery did not run to completion.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi

echo ""
echo "scripts-shard-totality-mutations.sh: $TOTAL rows, $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  exit 1
fi
echo "All tests passed"
