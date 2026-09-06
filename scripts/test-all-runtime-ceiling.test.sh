#!/usr/bin/env bash
# test-all-runtime-ceiling.test.sh — Guard 1 for the #7869 runtime ceiling.
#
# PROPERTY: once a test-all.sh run has been executing past TC_RUNTIME_CEILING_S,
# it starts no further suite, says so, and CANNOT exit green. The elapsed
# reading fails toward keeping the run alive.
#
# WHY AN EARLY `return` AND NOT AN `exit`: the lock fd is inherited by suite
# children (`exec {fd}>>`, no CLOEXEC; flock binds to the open file
# description), so a mid-suite exit would leave the lock held and would need a
# teardown — and the only teardown reaching those children is a process-group
# signal, whose group leader under lefthook's pre-commit is `git commit`.
# Returning at suite ENTRY means no child is live, so the ordinary exit releases
# the fd with no teardown at all. The arms below pin that shape.
#
# AUTHORING CONSTRAINTS (work/SKILL.md):
#   - Never `producer | grep -q` under pipefail (early match -> SIGPIPE -> a
#     NEGATIVE assertion fails OPEN). Grep a FILE.
#   - A deliberately-nonzero command inside `$( )` aborts under `set -e` before
#     fail() can print — suffix `|| true` inside the substitution.
#   - Every mutation must be ASSERTED TO LAND; a mutation that does not land
#     reports the baseline, which is indistinguishable from a pass.
#   - The unmutated CONTROL runs first: a red baseline voids every row.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only).

set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"

pass_n=0
fails=0
cases=0
# `cases` is incremented at the CALL SITE, never inside pass()/fail(), so the
# conservation check at the bottom can see a neutered verdict helper.
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t test-all-ceiling.XXXXXXXX)" || { echo "ERROR: mktemp failed" >&2; exit 2; }
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

[[ -f "$RUNNER" ]] || { echo "ERROR: $RUNNER does not exist" >&2; exit 2; }

# --- Fixtures ---------------------------------------------------------------
FIXTURES="$TESTROOT/fixtures"
mkdir -p "$FIXTURES" || exit 2
printf '#!/usr/bin/env bash\nsleep 2\nexit 0\n' > "$FIXTURES/slow.sh" || exit 2
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURES/ok.sh" || exit 2
chmod +x "$FIXTURES/slow.sh" "$FIXTURES/ok.sh" || exit 2

# --- Sandbox ----------------------------------------------------------------
# Mirrors the splice idiom of scripts/test-all-killed-classification.test.sh:
# the suite-registration region is replaced with fixture calls while run_suite,
# the summary and the exit ladder stay INTACT and under test.
#
# Every setup command is checked. A harness that fails to set up does not
# degrade into a missing result — it degrades into a confident wrong one.
build_sandbox() {
  local out="$1" arm="$2" mutation="$3"
  mkdir -p "$(dirname "$out")/lib" || return 2
  cp "$RUNNER" "$out" || return 2
  for f in test-relevance-paths.sh repo-write-boundary.sh test-contention.sh; do
    cp "$REPO_ROOT/scripts/lib/$f" "$(dirname "$out")/lib/" || return 2
  done
  python3 - "$out" "$arm" "$mutation" "$FIXTURES" <<'PY'
import sys, re
path, arm, mutation, fixtures = sys.argv[1:5]
s = open(path).read()

def sub_once(hay, old, new, what):
    assert hay.count(old) == 1, f"expected exactly one {what}, found {hay.count(old)}"
    return hay.replace(old, new)

start_anchor = 'tc_acquire "test-all"'
end_anchor = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(start_anchor) == 1, "start anchor not unique"
assert s.count(end_anchor) == 1, "end anchor not unique"
i = s.index(start_anchor) + len(start_anchor)
j = s.index(end_anchor)

# The first suite is SLOW so wall-clock advances past a 1s ceiling; the ones
# after it are what the guard must decline.
if arm == "infra":
    # The coverage-claim arm. The infra block is EXTRACTED FROM THE SOURCE rather than
    # retyped, so the harness cannot re-implement the conditional under test — a
    # hand-written copy would pass against a broken runner.
    m2 = re.search(
        r'\n([ \t]*_infra_declined_before="\$_ceiling_declined"\n.*?\n[ \t]*fi\n)',
        s, re.S)
    assert m2, "MUTATION-DID-NOT-LAND: infra dispatch block not found in source"
    infra_block = m2.group(1)
    infra_block = re.sub(
        r'run_suite "apps/web-platform/infra/run-registered-suites\.sh" bash "[^"]*"',
        f'run_suite "infrarunner" bash "{fixtures}/ok.sh"', infra_block)
    assert "infrarunner" in infra_block, "run_suite retarget failed"
    body = f'\nrun_suite "slowfixture" bash "{fixtures}/slow.sh"\n' + infra_block
else:
    calls = {
        "two":   [("slowfixture", "slow.sh"), ("after1", "ok.sh")],
        "three": [("slowfixture", "slow.sh"), ("after1", "ok.sh"), ("after2", "ok.sh")],
    }[arm]
    body = "\n" + "".join(
        f'run_suite "{label}" bash "{fixtures}/{script}"\n' for label, script in calls
    )
s = s[:i] + body + s[j:]

# Neuter the advisory lock and the preamble: taking the REAL lock would block on
# whatever else this machine is running, making the arm's runtime a property of
# the box rather than of the subject.
s = sub_once(s, 'tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 'tc_acquire call')
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)

# --- Mutations. Each neuters exactly ONE guard; each MUST land. -------------
if mutation == "no_check":
    # M1: hoist the check out of run_suite's body (delete it there).
    # Anchored on a UNIQUE code line, not on the comment prefix: `# --- Runtime ceiling`
    # now occurs twice (the run_suite block and the top-level resolution), so a regex on it
    # could delete the state declarations instead — the sandbox would then abort under
    # `set -u` with rc 1, and an rc-scored battery would read that as "mutant detected".
    s = sub_once(s, 'if (( _CEILING_S > 0 )); then', 'if false; then', 'run_suite ceiling gate')
elif mutation == "always_under":
    # M2: the elapsed comparison never fires. Aimed at the COMPARISON, not at
    # the `_ceiling_tripped` latch — that latch only gates whether the banner
    # prints once, so mutating it changes no verdict and would report a
    # survivor that is really a mis-aimed row.
    s = sub_once(s, '(( _elapsed_s >= _CEILING_S ))',
                 '(( _elapsed_s >= _CEILING_S + 999999 ))', 'elapsed comparison')
elif mutation == "no_forced_exit":
    # M3: the trip no longer forces a non-zero exit (the false-green row).
    s = sub_once(s, 'elif (( _ceiling_declined > 0 )); then',
                 'elif false; then', 'forced-exit arm')
elif mutation == "unreadable_trips":
    # M4: an unreadable/disabled ceiling curtails the run.
    # Aimed at the DISABLED DEFAULT, not the validity guard. Mutating the guard to `true`
    # no longer expresses this property after the refactor: `10#abc` is an arithmetic error,
    # so `_CEILING_S` simply stays 0 and the run completes — a survivor that looks like the
    # healthy run. Flipping the default is what makes an unusable ceiling curtail.
    s = sub_once(s, '_CEILING_S=0\nif [[ -n "${CI:-}" ]]; then',
                 '_CEILING_S=1\nif [[ -n "${CI:-}" ]]; then', 'ceiling disabled default')
elif mutation == "no_marker":
    # M5: the run is curtailed silently.
    s = sub_once(s, 'SOLEUR_TEST_ALL_RUNTIME_CEILING', 'QUIET_CEILING', 'ceiling marker')
elif mutation == "unconditional_infra_ran":
    # M8: revert the coverage claim to its unconditional form.
    s = sub_once(s, 'if (( _ceiling_declined == _infra_declined_before )); then\n      _infra_ran=1\n    fi',
                 '_infra_ran=1', 'infra coverage guard')
elif mutation == "trip_once":
    # M7: only the first post-ceiling suite is declined.
    s = sub_once(s, '_ceiling_declined=$(( _ceiling_declined + 1 ))',
                 '_ceiling_declined=1', 'declined counter')
elif mutation != "none":
    raise AssertionError(f"unknown mutation {mutation}")

open(path, "w").write(s)
PY
}

# Runs a sandbox and prints "<rc>" on the last line, log path on the first.
run_arm() {
  local arm="$1" mutation="$2" ceiling="$3" dir log rc
  dir="$TESTROOT/sb-$arm-$mutation-$ceiling"
  mkdir -p "$dir/scripts" || return 2
  build_sandbox "$dir/scripts/test-all.sh" "$arm" "$mutation" || return 2
  log="$dir/run.log"
  # `env -u CI`: the runner exempts CI (a shard's consumer is the required check), so an
  # inherited CI would silently disable the guard and every arm below would pass vacuously.
  ( cd "$REPO_ROOT" && env -u CI TC_RUNTIME_CEILING_S="$ceiling" TEST_GROUP=all \
      SOLEUR_ALLOW_FULL_GATE=1 SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$dir/scripts/test-all.sh" ) > "$log" 2>&1
  rc=$?
  printf '%s\n%s\n' "$log" "$rc"
}

# Same sandbox, CI set — for the exemption arm only.
run_arm_ci() {
  local arm="$1" mutation="$2" ceiling="$3" dir log rc
  dir="$TESTROOT/sbci-$arm-$mutation-$ceiling"
  mkdir -p "$dir/scripts" || return 2
  build_sandbox "$dir/scripts/test-all.sh" "$arm" "$mutation" || return 2
  log="$dir/run.log"
  ( cd "$REPO_ROOT" && env CI=1 TC_RUNTIME_CEILING_S="$ceiling" TEST_GROUP=all \
      SOLEUR_ALLOW_FULL_GATE=1 SOLEUR_DISABLE_SESSION_STATE=1 \
      bash "$dir/scripts/test-all.sh" ) > "$log" 2>&1
  rc=$?
  printf '%s\n%s\n' "$log" "$rc"
}

arm_rc()  { printf '%s' "$(sed -n '2p' <<<"$1")"; }
arm_log() { printf '%s' "$(sed -n '1p' <<<"$1")"; }

echo "=== Guard 1 (#7869): test-all runtime ceiling ==="

# --- CONTROL: unmutated, ceiling far above the run -------------------------
# Runs FIRST. A red baseline voids every row below, so this is not a nicety.
CTRL="$(run_arm two none 99999 || true)"
CTRL_RC="$(arm_rc "$CTRL")"; CTRL_LOG="$(arm_log "$CTRL")"
cases=$((cases + 1))
if [[ "$CTRL_RC" == "0" ]]; then
  pass "CONTROL unmutated run under the ceiling exits 0"
else
  fail "CONTROL expected rc 0, got $CTRL_RC; log: $(tail -5 "$CTRL_LOG" 2>/dev/null || true)"
fi
# H3 (must-PASS, non-canonical input): a healthy run emits NO ceiling marker,
# and both suites actually ran. Differs from the canonical trip fixture in
# ceiling value and suite outcome, which the contract explicitly permits.
cases=$((cases + 1))
if [[ "$(grep -cE 'SOLEUR_TEST_ALL_RUNTIME_CEILING' "$CTRL_LOG" || true)" -eq 0 ]]; then
  pass "H3 no ceiling marker on a healthy under-ceiling run"
else
  fail "H3 ceiling marker fired on a healthy run"
fi
cases=$((cases + 1))
if [[ "$(grep -cE '^\[ok\] after1' "$CTRL_LOG" || true)" -ge 1 ]]; then
  pass "H3 the suite after the slow one RAN when under the ceiling"
else
  fail "H3 after1 did not run under a high ceiling; log: $(tail -20 "$CTRL_LOG" 2>/dev/null || true)"
fi

# --- The trip: ceiling crossed mid-run -------------------------------------
TRIP="$(run_arm two none 1 || true)"
TRIP_RC="$(arm_rc "$TRIP")"; TRIP_LOG="$(arm_log "$TRIP")"
cases=$((cases + 1))
if [[ "$TRIP_RC" == "3" ]]; then
  pass "M3 a ceiling-curtailed run exits 3 — never green"
else
  fail "M3 expected rc 3 on a curtailed run, got $TRIP_RC; log: $(tail -20 "$TRIP_LOG" 2>/dev/null || true)"
fi
cases=$((cases + 1))
if [[ "$(grep -cE 'SOLEUR_TEST_ALL_RUNTIME_CEILING' "$TRIP_LOG" || true)" -ge 1 ]]; then
  pass "M5 the curtailed run SAYS why (marker present)"
else
  fail "M5 no SOLEUR_TEST_ALL_RUNTIME_CEILING marker; log: $(tail -20 "$TRIP_LOG" 2>/dev/null || true)"
fi
cases=$((cases + 1))
if [[ "$(grep -cE '^\[ok\] after1' "$TRIP_LOG" || true)" -eq 0 ]]; then
  pass "M1 the suite after the ceiling was NOT started"
else
  fail "M1 after1 ran despite the ceiling being crossed"
fi
# The marker must carry the measured elapsed AND the ceiling it crossed — a
# bare "ceiling hit" leaves the reader unable to tell a tight ceiling from a
# genuinely long run.
cases=$((cases + 1))
if [[ "$(grep -cE 'SOLEUR_TEST_ALL_RUNTIME_CEILING.*elapsed_s=[0-9]+.*ceiling_s=1' "$TRIP_LOG" || true)" -ge 1 ]]; then
  pass "the marker names the measured elapsed and the ceiling"
else
  fail "marker lacks elapsed_s/ceiling_s; got: $(grep 'RUNTIME_CEILING' "$TRIP_LOG" || true)"
fi

# --- M7: EVERY later suite is declined, not just the first ------------------
THREE="$(run_arm three none 1 || true)"
THREE_LOG="$(arm_log "$THREE")"
cases=$((cases + 1))
if [[ "$(grep -cE 'declined_suites=2' "$THREE_LOG" || true)" -ge 1 ]]; then
  pass "M7 both post-ceiling suites declined (counter does not saturate at 1)"
else
  fail "M7 expected declined_suites=2; got: $(grep -E 'RUNTIME_CEILING|declined' "$THREE_LOG" || true)"
fi

# --- M4: an unusable ceiling must NOT curtail the run -----------------------
# Fails toward keep-running. This is the #5454 direction: a reading that cannot
# be trusted must never be grounds for cutting work short.
UNREAD="$(run_arm two none abc || true)"
UNREAD_RC="$(arm_rc "$UNREAD")"; UNREAD_LOG="$(arm_log "$UNREAD")"
cases=$((cases + 1))
if [[ "$UNREAD_RC" == "0" ]]; then
  pass "M4 a non-numeric ceiling disables the guard (fails toward keep-running)"
else
  fail "M4 expected rc 0 with an unusable ceiling, got $UNREAD_RC"
fi
cases=$((cases + 1))
if [[ "$(grep -cE '^\[ok\] after1' "$UNREAD_LOG" || true)" -ge 1 ]]; then
  pass "M4 every suite still ran under an unusable ceiling"
else
  fail "M4 after1 was skipped under an unusable ceiling"
fi

# --- The terminal marker must NOT read green on a curtailed run -------------
# `=== N/N suites passed ===` is this repo's documented completion anchor, so a
# curtailed run that prints it certifies a battery it never ran. ADR-181 records
# the same defect for relevance declines: "a green that is not evidence, produced
# by the very change that added the gate".
cases=$((cases + 1))
if [[ "$(grep -cE '^=== 1/2 suites passed ===$' "$TRIP_LOG" || true)" -ge 1 ]]; then
  pass "the terminal marker degrades to 1/2 on a curtailed run (declines stay in the denominator)"
else
  fail "false green: marker does not account for the decline; got: $(grep -E '^=== .*suites passed' "$TRIP_LOG" || true)"
fi
cases=$((cases + 1))
if [[ "$(grep -cE 'declined \(runtime ceiling — coverage not obtained\)' "$TRIP_LOG" || true)" -ge 1 ]]; then
  pass "the breakdown line names the ceiling declines"
else
  fail "breakdown line omits the ceiling declines; got: $(grep -E '^=== .*suites:' "$TRIP_LOG" || true)"
fi

# --- A ZERO-PADDED ceiling must not be read as octal ------------------------
# bash reads a leading zero as base 8 and awk does not, so `07200` meant 3712s to
# this guard and 7200s to the sibling filter — and 3712s is BELOW the lowest
# runtime this repo records for a healthy contended run. A guard that curtails
# healthy work is worse than no guard.
OCTAL="$(run_arm two none 07200 || true)"
OCTAL_RC="$(arm_rc "$OCTAL")"; OCTAL_LOG="$(arm_log "$OCTAL")"
cases=$((cases + 1))
if [[ "$OCTAL_RC" == "0" ]]; then
  pass "a zero-padded ceiling (07200) is read as 7200, not octal 3712 — the run completes"
else
  fail "octal regression: 07200 curtailed a short run (rc $OCTAL_RC); got: $(grep 'RUNTIME_CEILING' "$OCTAL_LOG" || true)"
fi

# --- CI is exempt ----------------------------------------------------------
# The ceiling's premise is "a run past it has no consumer"; in a CI shard the
# consumer is the required check, and GitHub's default job timeout (360 min)
# sits ABOVE this ceiling, so an unexempted guard would red a required check on
# a run that was merely slow.
CI_ARM="$(run_arm_ci two none 1 || true)"
CI_RC="$(arm_rc "$CI_ARM")"; CI_LOG="$(arm_log "$CI_ARM")"
cases=$((cases + 1))
if [[ "$CI_RC" == "0" ]]; then
  pass "CI is exempt from the ceiling (a slow shard is not curtailed)"
else
  fail "CI not exempt: rc $CI_RC; got: $(grep 'RUNTIME_CEILING' "$CI_LOG" || true)"
fi

# --- An unusable ceiling SAYS SO -------------------------------------------
cases=$((cases + 1))
if [[ "$(grep -cE 'SOLEUR_TEST_ALL_CEILING_UNAVAILABLE' "$UNREAD_LOG" || true)" -ge 1 ]]; then
  pass "a disabled ceiling announces itself (armed vs disabled are distinguishable)"
else
  fail "silent disable: no SOLEUR_TEST_ALL_CEILING_UNAVAILABLE marker"
fi

# --- Coverage claim: a DECLINED suite must not be recorded as covered -------
# `run_suite` returns 0 whether it ran or declined, so a caller that infers "it ran"
# from control reaching the next line records coverage it does not have. The infra
# dispatch does exactly that, and the epilogue turns the flag into a printed claim.
INFRA_TRIP="$(run_arm infra none 1 || true)"
INFRA_TRIP_LOG="$(arm_log "$INFRA_TRIP")"
cases=$((cases + 1))
if [[ "$(grep -cF 'IS covered above' "$INFRA_TRIP_LOG" || true)" -eq 0 ]]; then
  pass "a ceiling-declined infra suite is NOT claimed as covered"
else
  fail "false coverage claim: 'IS covered above' printed for a suite that never started"
fi
# Must-PASS control — this is what makes the arm above non-vacuous: absence of the
# claim proves nothing unless the claim is PRESENT when the suite really does run.
INFRA_OK="$(run_arm infra none 99999 || true)"
INFRA_OK_LOG="$(arm_log "$INFRA_OK")"
cases=$((cases + 1))
if [[ "$(grep -cF 'IS covered above' "$INFRA_OK_LOG" || true)" -ge 1 ]]; then
  pass "an infra suite that actually ran IS claimed as covered (control)"
else
  fail "control failed: coverage claim absent though the suite ran; got: $(tail -20 "$INFRA_OK_LOG" 2>/dev/null || true)"
fi

# --- Mutation battery: each row MUST redden --------------------------------
# Expressed against the DESIGN, and each asserted to LAND — a mutation that
# does not land reports the baseline, which reads exactly like a pass.
echo "--- mutation battery ---"
mutation_reds() {
  local label="$1" mutation="$2" arm="$3" ceiling="$4" expect_rc="$5"
  local out rc
  if ! out="$(run_arm "$arm" "$mutation" "$ceiling" 2>&1)"; then
    cases=$((cases + 1))
    fail "$label: sandbox build failed (mutation did not land?): $(tail -3 <<<"$out")"
    return
  fi
  rc="$(arm_rc "$out")"
  cases=$((cases + 1))
  if [[ "$rc" != "$expect_rc" ]]; then
    pass "$label: mutant detected (rc $rc != healthy $expect_rc)"
  else
    fail "$label: MUTANT SURVIVED — rc $rc matches the healthy run"
  fi
}
# Each mutant is scored on the arm whose healthy rc it must change.
mutation_reds "M1 check hoisted out of run_suite" no_check       two 1 3
mutation_reds "M2 comparison never fires"         always_under   two 1 3
mutation_reds "M3 trip does not force non-zero"   no_forced_exit two 1 3
mutation_reds "M4 unusable ceiling trips"         unreadable_trips two abc 0
# M5 is scored on the LOG, not on rc: suppressing the marker does not change
# the exit code, so an rc-only battery cannot see it. A battery that scores
# every row the same way is blind to every property that is not an exit code.
M5="$(run_arm two no_marker 1 || true)"
M5_LOG="$(arm_log "$M5")"
cases=$((cases + 1))
if [[ "$(grep -cE 'SOLEUR_TEST_ALL_RUNTIME_CEILING' "$M5_LOG" || true)" -eq 0 ]]; then
  pass "M5 marker suppressed: mutant detected (marker absent from the curtailed run)"
else
  fail "M5 MUTANT SURVIVED — marker still present after suppression"
fi

# --- Floor + accounting (M6: the guard's own dispatch) ---------------------
# M8 is scored on the LOG: a false coverage claim leaves the exit code untouched,
# so rc-scoring is structurally blind to it — same reason M5 is scored this way.
M8="$(run_arm infra unconditional_infra_ran 1 || true)"
M8_LOG="$(arm_log "$M8")"
cases=$((cases + 1))
if [[ "$(grep -cF 'IS covered above' "$M8_LOG" || true)" -ge 1 ]]; then
  pass "M8 unconditional coverage flag: mutant detected (false claim reappears)"
else
  fail "M8 MUTANT SURVIVED — reverting the guard did not reproduce the false coverage claim"
fi

MIN_CASES=23
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '\n[FATAL] only %d assertions ran, expected >= %d — the suite asserted less than it claims.\n' \
    "$cases" "$MIN_CASES" >&2
  echo "=== test-all-runtime-ceiling: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi
if [[ $((pass_n + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: pass_n+fails (%d) != cases (%d) — a verdict was counted but not recorded.\n' \
    "$((pass_n + fails))" "$cases" >&2
  echo "=== test-all-runtime-ceiling: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

echo "=== test-all-runtime-ceiling: $pass_n passed, $fails failed ($cases assertions) ==="
[[ "$fails" -eq 0 ]] || exit 1
