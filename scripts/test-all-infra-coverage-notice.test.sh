#!/usr/bin/env bash
# Regression suite for scripts/test-all.sh's infra COVERAGE CLAIM (#7103 R5(a) follow-up) AND for
# the ADR-181 relevance gate that declines expensive suites on an irrelevant diff.
#
# THE FILENAME UNDER-DESCRIBES THE FILE, and deliberately so. Renaming it would churn the
# run_suite registration in test-all.sh and break `git log` continuity for no property gained, so
# the scope is stated here instead. Everything below the "THE RELEVANCE GATE" banner is the
# ADR-181 half; everything above it is the original coverage-claim half. They share one sandbox
# harness because they test the same file's decisions about which suites to execute.
#
# WHY THIS EXISTS. The epilogue notice and the runner invocation were keyed on two DIFFERENT
# facts and nothing coupled them:
#
#   the notices ->  _infra_in_diff   (a fact about the DIFF)
#   the runner  ->  want_infra()     (a fact about TEST_GROUP)
#
# CI runs `test-all.sh webplat`, `bun` and `scripts`; want_infra is false in all three. So on
# every CI run of an infra-touching PR — precisely the case R5(a) exists for — three job logs
# printed "apps/web-platform/infra/ IS covered above" over a run in which the infra runner never
# executed. That is strictly WORSE than the behaviour it replaced: `main` printed "infra is NOT
# covered above", which was true in every group. Inverting the sentence without coupling it to
# the invocation turned a universally-true warning into a conditionally-false assurance.
#
# HOW IT TESTS. `run_suite` is replaced with a RECORDER in a sandbox copy, so the assertions are
# about which suites test-all.sh *decided* to run and what it *claimed* about that decision —
# without executing a single suite. Each arm therefore compares two observable facts from the
# same run, which is the coupling the defect broke. A spelling assertion (grep the source for
# `_infra_ran`) could not do this: it would pass against any implementation that mentions the
# variable, including one that never sets it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the suite can be pointed at an older or mutated copy and PROVED to red against
# it. A guard that has never been shown to fail is not evidence; this is how that gets shown.
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
PASS=0; FAIL=0

# /tmp is a machine-global ~4 GiB tmpfs shared by every parallel worktree, and this file builds
# ONE FULL SANDBOX COPY PER ARM — a count that grew with the table-driven relevance arms. Under
# test-all.sh TMPDIR is already /var/tmp; a DIRECT invocation (the documented inner loop while
# editing the gate) inherits the bare /tmp, which makes this suite's verdicts a function of
# another session's disk usage. `mktemp -d` respects TMPDIR, so defaulting it here is the whole
# fix. Setup failures below are already checked — a harness that cannot build its sandbox must
# abort, never report a verdict about the SUT.
export TMPDIR="${TMPDIR:-/var/tmp}"

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Build a sandbox copy whose run_suite records instead of running, and whose diff-detection
# result is forced. $1 = sandbox path, $2 = 1|0 for "diff touches infra".
build_sandbox() {
  local out="$1" in_diff="$2"
  cp "$TARGET" "$out" || return 1
  # The sandbox RELOCATES test-all.sh, so anything it resolves via ${BASH_SOURCE[0]} has to be
  # relocated with it. The relevance-predicate data file is sourced fail-CLOSED (a missing one
  # exits 2, because empty predicates would decline every gated suite while the summary still
  # read green), so without this copy every arm below would measure that guard firing rather
  # than the gate it guards.
  mkdir -p "$(dirname "$out")/lib" || return 1
  cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$(dirname "$out")/lib/" || return 1
  # Recorder. Appended AFTER the original definition so it wins, and before any invocation.
  python3 - "$out" "$in_diff" <<'PY'
import sys, re
path, in_diff = sys.argv[1], sys.argv[2]
s = open(path).read()

# 1. Force the diff verdict deterministically: this suite is about the NOTICE, not about
#    git plumbing, and deriving it from the real repo would make the arms depend on whatever
#    the working tree happens to touch today.
#    The anchor is the INITIALISATION, which sits BEFORE the re-derivation immediately below
#    it — so forcing the value here is not sufficient on its own. Step 1b neuters that
#    re-derivation; without it the force is silently overwritten on any branch whose real diff
#    touches apps/web-platform/infra/, and every arm then measures the runner RUNNING when the
#    fixture declared it declined. That is a false RED on exactly the PRs this suite is meant
#    to protect, and it is invisible on a branch that happens not to touch infra.
old = '_infra_in_diff=0'
assert s.count(old) == 1, f"expected exactly one '{old}', found {s.count(old)}"
s = s.replace(old, (
    f'_infra_in_diff={in_diff}\n'
    '_SANDBOX_FORCED_DIFF=1\n'
    '[[ -n "${SANDBOX_DIFF_NAMES:-}" ]] && _diff_names="$SANDBOX_DIFF_NAMES"\n'
    '[[ -n "${SANDBOX_DETECT_OK:-}" ]] && _diff_detect_ok="$SANDBOX_DETECT_OK"\n'
))

# 1b. Neuter the re-derivation that follows the initialisation. `run_arm` does not set
#     SANDBOX_DIFF_NAMES, so `$_diff_names` still holds the REAL diff — and a real diff that
#     touches apps/web-platform/infra/ sets _infra_in_diff back to 1, defeating step 1.
old1b = """if grep -qF 'apps/web-platform/infra/' <<<"$_diff_names"; then
  _infra_in_diff=1
fi"""
assert s.count(old1b) == 1, f"expected exactly one infra re-derivation, found {s.count(old1b)}"
s = s.replace(old1b, """if [[ -z "${_SANDBOX_FORCED_DIFF:-}" ]] && grep -qF 'apps/web-platform/infra/' <<<"$_diff_names"; then
  _infra_in_diff=1
fi""")

# 2. Neuter the detection block so it cannot overwrite the forced value. SANDBOX_DETECT_OK can
#    still force it back to 0 for the fail-SAFE arm.
old2 = '_diff_detect_ok=0'
assert s.count(old2) == 1, f"expected exactly one '{old2}', found {s.count(old2)}"
s = s.replace(old2, '_diff_detect_ok=1')

# 3. Replace run_suite's BODY with a recorder. Matches the definition line and its block.
#    The recorder KEEPS the `suites` increment: the denominator is itself under test (a gated
#    suite must stay in it), so a recorder that dropped the counter would make every count
#    assertion below vacuous.
m = re.search(r'^run_suite\(\) \{.*?^\}', s, re.S | re.M)
assert m, "could not locate run_suite() definition"
s = s[:m.start()] + 'run_suite() { suites=$((suites + 1)); echo "RECORDED_SUITE:$1" >> "$SANDBOX_RECORD"; }' + s[m.end():]

open(path, 'w').write(s)
print("sandbox built")
PY
}

# Parse the runner's summary into PARSED_PASS / PARSED_TOTAL / PARSED_FAIL / PARSED_SKIP.
#
# TWO LINES, deliberately (the shape #7424 established and ADR-181 extends): a BREAKDOWN line
# emitted only when something was killed or declined, then the TERMINAL MARKER
# `=== P/N suites passed ===`, byte-identical to what it has always been. The marker is last so
# that the runner's final `===` line is always the one pollers anchor on; the breakdown carries
# the detail. Reading the marker alone therefore cannot tell a decline from a failure, which is
# why this parser reads both.
#
# Returns non-zero when the marker is absent or a decline occurred with no breakdown line, so a
# summary that silently stopped reporting declines FAILS rather than reading as zero skips.
parse_summary() {
  local out="$1" marker breakdown
  PARSED_PASS=""; PARSED_TOTAL=""; PARSED_FAIL=""; PARSED_SKIP=""
  marker=$(grep -oE '=== [0-9]+/[0-9]+ suites passed ===' <<<"$out" | tail -1)
  [[ -n "$marker" ]] || return 1
  PARSED_PASS=$(sed 's|=== \([0-9]*\)/.*|\1|' <<<"$marker")
  PARSED_TOTAL=$(sed 's|.*/\([0-9]*\) suites passed ===|\1|' <<<"$marker")

  breakdown=$(grep -oE '=== [0-9]+ suites: .* ===' <<<"$out" | tail -1)
  if [[ -n "$breakdown" ]]; then
    PARSED_FAIL=$(grep -oE '[0-9]+ failed' <<<"$breakdown" | grep -oE '^[0-9]+')
    PARSED_SKIP=$(grep -oE '[0-9]+ skipped' <<<"$breakdown" | grep -oE '^[0-9]+')
  else
    # No breakdown line means nothing was killed or declined — both are zero by construction.
    PARSED_FAIL=0; PARSED_SKIP=0
  fi
  [[ "$PARSED_PASS" =~ ^[0-9]+$ && "$PARSED_TOTAL" =~ ^[0-9]+$ ]] || return 1
  [[ "$PARSED_FAIL" =~ ^[0-9]+$ && "$PARSED_SKIP" =~ ^[0-9]+$ ]] || return 1
  return 0
}

# Run one arm. $1=group $2=in_diff $3=incident_skip -> sets ARM_OUT / ARM_RAN
run_arm() {
  local group="$1" in_diff="$2" incident="$3"
  local sb="$TMP/test-all-${group}-${in_diff}-${incident}.sh"
  build_sandbox "$sb" "$in_diff" >/dev/null || { fail "sandbox build failed for $group"; return 1; }
  export SANDBOX_RECORD="$TMP/record-${group}-${in_diff}-${incident}.txt"
  : > "$SANDBOX_RECORD"
  # Per-arm timing log so the labelled-field assertions read THIS arm's rows and never a
  # previous arm's leftovers.
  ARM_TIMING="$TMP/timing-${group}-${in_diff}-${incident}.tsv"
  : > "$ARM_TIMING"
  # SOLEUR_TEST_FORCE_ALL pins the two relevance-gated batteries ON, so the INFRA gate is the
  # only variable these arms move. Without it they would inherit whatever this worktree's real
  # diff happens to touch — and a diff irrelevant to those batteries would make them decline,
  # changing the skip count these arms assert on for a reason that has nothing to do with infra.
  # SOLEUR_SUBAGENT / SOLEUR_ALLOW_FULL_GATE are cleared for the same reason as the two
  # variables below: test-all.sh exits 4 under SOLEUR_SUBAGENT=1 BEFORE any registration, so
  # an inherited value makes every arm measure a run that did nothing -- and the 10 matrix
  # cells then pass VACUOUSLY on `claim (0) matches invocation (0)`. The environment that
  # sets it is a spawned agent, i.e. exactly how this PR tells reviewers to run suites.
  ARM_OUT=$(cd "$REPO_ROOT" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
            SOLEUR_INCIDENT_SKIP="$incident" TEST_GROUP="$group" \
            SOLEUR_TEST_FORCE_ALL=1 \
            TEST_TIMING_LOG="$ARM_TIMING" timeout 120 bash "$sb" 2>&1)
  ARM_RAN=0
  grep -q 'RECORDED_SUITE:apps/web-platform/infra/run-registered-suites.sh' "$SANDBOX_RECORD" && ARM_RAN=1
  return 0
}

# POSITIVE CONTROL, first assertion in the file. MIN_ASSERTIONS counts PASS+FAIL, so a neutered
# `fail()` drops failing assertions out of the sum and is caught only while slack >= the number of
# failures -- and slack is 0 only by hand-maintenance of MIN_FIXED. Measured: `fail(){ return 0; }`
# left this suite at 99/0 rc 0, a no-op oracle that says nothing about the SUT. This control fails
# loudly instead, and costs one assertion.
_c_pass=$PASS _c_fail=$FAIL
pass "[control] pass() moves its counter"
fail "[control] EXPECTED-FAIL probe -- not a real failure; retracted on the next line"
if [[ "$PASS" -eq $((_c_pass + 1)) && "$FAIL" -eq $((_c_fail + 1)) ]]; then
  FAIL=$((FAIL - 1))   # retract the deliberate failure; the counter move is the evidence
  pass "[control] both counters are live, so a real failure is reportable"
else
  echo "FATAL: pass()/fail() do not move their counters -- every verdict below is unreadable." >&2
  exit 1
fi

echo "=== test-all.sh infra coverage-notice suite ==="echo "=== test-all.sh infra coverage-notice suite ==="

# --- THE CORE INVARIANT, over the full group x diff matrix ---------------------------------
# The claim and the invocation must agree in EVERY cell. This is the assertion the defect
# would have failed in three of them.
for group in all webplat bun scripts infra; do
  for in_diff in 1 0; do
    run_arm "$group" "$in_diff" 0 || continue
    claims_covered=0
    grep -q 'IS covered above' <<<"$ARM_OUT" && claims_covered=1
    if [[ "$claims_covered" == "$ARM_RAN" ]]; then
      pass "group=$group in_diff=$in_diff — claim ($claims_covered) matches invocation ($ARM_RAN)"
    else
      fail "group=$group in_diff=$in_diff — CLAIMED covered=$claims_covered but runner ran=$ARM_RAN"
    fi
  done
done

# --- The three CI shards specifically, on an infra-touching diff ----------------------------
# Named individually because these are the exact invocations ci.yml uses, and the defect was
# invisible anywhere else.
for group in webplat bun scripts; do
  run_arm "$group" 1 0 || continue
  if grep -q 'IS covered above' <<<"$ARM_OUT"; then
    fail "CI shard '$group' claims infra coverage it does not have"
  else
    pass "CI shard '$group' does not claim infra coverage"
  fi
  if grep -q 'NOT covered above' <<<"$ARM_OUT"; then
    pass "CI shard '$group' says plainly that infra is not covered"
  else
    fail "CI shard '$group' is silent about infra on a diff that touches it"
  fi
done

# --- The incident bypass must be attributed only when it is the actual cause ----------------
run_arm bun 1 1 || true
if grep -q 'SOLEUR_INCIDENT_SKIP=1' <<<"$ARM_OUT"; then
  fail "a non-infra group attributes its skip to the incident bypass, which was not consulted"
else
  pass "the incident bypass is not blamed for a skip caused by TEST_GROUP"
fi

run_arm infra 1 1 || true
if grep -q 'was SKIPPED (SOLEUR_INCIDENT_SKIP=1)' <<<"$ARM_OUT"; then
  pass "an infra-group run skipped by the bypass attributes it to the bypass"
else
  fail "the incident bypass fired but is not named in the epilogue"
fi
if [[ "$ARM_RAN" == 0 ]]; then
  pass "the incident bypass actually prevents the invocation"
else
  fail "the incident bypass printed but the runner ran anyway"
fi

# --- The positive case still works ----------------------------------------------------------
run_arm infra 1 0 || true
if [[ "$ARM_RAN" == 1 ]] && grep -q 'IS covered above' <<<"$ARM_OUT"; then
  pass "TEST_GROUP=infra runs the runner and says so"
else
  fail "TEST_GROUP=infra did not both run the runner and claim it (ran=$ARM_RAN)"
fi

# --- A GATED SUITE IS A COUNTED VERDICT, NOT A MISSING ONE (Phase B) -------------------------
# The defect being closed: run_suite increments `suites` on ENTRY, so wrapping a call in `if`
# removes it from the denominator entirely. `N/N suites passed` then cannot distinguish
# "286/286 because two were gated" from "286/286 because two were DE-REGISTERED" — and the
# second is the #3366 class, a suite running in zero runners while the summary reads green.
#
# The two arms differ ONLY in the diff verdict, so the denominator is the controlled variable.
# Comparing two arms of the same run shape is what makes this a coupling assertion rather than
# a spelling one: a `grep skipped test-all.sh` would pass against any file that mentions it.
INFRA_LABEL='apps/web-platform/infra/run-registered-suites.sh'

# TEST_GROUP=all, not infra: the `infra` group short-circuits the diff check entirely
# (`$TEST_GROUP == "infra" || $_infra_in_diff == 1`), so under it a decline is unreachable
# and the arm would silently measure nothing. `all` is the group where the diff verdict is
# actually the deciding variable, which is what makes these two arms a controlled pair.
run_arm all 1 0 || true
RUN_OUT="$ARM_OUT"
if parse_summary "$RUN_OUT"; then
  RUN_TOTAL="$PARSED_TOTAL"; RUN_SKIP="$PARSED_SKIP"
  pass "the summary carries all four counts on a run where nothing was gated"
else
  RUN_TOTAL=""; RUN_SKIP=""
  fail "the summary does not report passed/failed/skipped/total"
fi
if [[ "$RUN_SKIP" == "0" ]]; then
  pass "a run that gated nothing reports 0 skipped"
else
  fail "a run that gated nothing reports skipped=$RUN_SKIP"
fi

run_arm all 0 0 || true
SKIP_OUT="$ARM_OUT"; SKIP_TIMING="$ARM_TIMING"
if parse_summary "$SKIP_OUT"; then
  SKIP_TOTAL="$PARSED_TOTAL"; SKIP_S="$PARSED_SKIP"; SKIP_P="$PARSED_PASS"; SKIP_F="$PARSED_FAIL"
else
  SKIP_TOTAL=""; SKIP_S=""; SKIP_P=""; SKIP_F=""
  fail "the summary on a gated run does not report passed/failed/skipped/total"
fi

if [[ -n "$SKIP_S" && "$SKIP_S" == "1" ]]; then
  pass "the gated suite is reported as skipped (S=1)"
else
  fail "the gated suite is not reported as skipped (S=$SKIP_S)"
fi
# THE denominator assertion. If the gated suite vanished from `suites`, this is the arm that
# says so — and it says so by comparing against a run of the same shape, not against a literal
# that would need updating every time a suite is registered.
if [[ -n "$RUN_TOTAL" && "$SKIP_TOTAL" == "$RUN_TOTAL" ]]; then
  pass "gating a suite leaves the denominator intact ($SKIP_TOTAL both ways)"
else
  fail "gating a suite changed the denominator: ran=$RUN_TOTAL gated=$SKIP_TOTAL"
fi
if [[ -n "$SKIP_P" ]] && [[ "$((SKIP_P + SKIP_F + SKIP_S))" == "$SKIP_TOTAL" ]]; then
  pass "P + F + S == N on a gated run ($SKIP_P + $SKIP_F + $SKIP_S == $SKIP_TOTAL)"
else
  fail "P + F + S != N on a gated run ($SKIP_P + $SKIP_F + $SKIP_S vs $SKIP_TOTAL)"
fi
# A skipped suite counted as PASSED is the precise "green that is not evidence" this closes.
if [[ -n "$RUN_TOTAL" && -n "$SKIP_P" && "$SKIP_P" -lt "$RUN_TOTAL" ]]; then
  pass "a skipped suite is not counted as passed ($SKIP_P < $RUN_TOTAL)"
else
  fail "a skipped suite was counted in the passed numerator ($SKIP_P of $RUN_TOTAL)"
fi

# The skip must be ACTIONABLE, not merely honest: name the suite, why, and how to re-run it.
if grep -qF "$INFRA_LABEL" <<<"$SKIP_OUT"; then
  pass "the skip line names the suite"
else
  fail "the skip line does not name the suite"
fi
if grep -qF 'not_in_diff' <<<"$SKIP_OUT"; then
  pass "the skip line names its reason"
else
  fail "the skip line does not name a machine-readable reason"
fi
if grep -qF "bash $INFRA_LABEL" <<<"$SKIP_OUT"; then
  pass "the skip line carries the exact re-run command"
else
  fail "the skip line does not carry a re-run command"
fi

# --- TEST_TIMING_LOG: skip= is a LABELLED field, and field 3 stays unambiguous ---------------
# Field 3 already carries the bare `FAIL` marker, so an unlabelled append would be positionally
# ambiguous between the ok, FAIL and skip shapes — the same reasoning test-all.sh already
# applies to tmp_delta=.
if [[ -s "$SKIP_TIMING" ]] && awk -F'\t' -v l="$INFRA_LABEL" '$1==l && $3 ~ /^skip=/ {found=1} END{exit !found}' "$SKIP_TIMING"; then
  pass "TEST_TIMING_LOG records the skip as a labelled field-3 value"
else
  fail "TEST_TIMING_LOG has no skip=<reason> row for the gated suite"
fi
if awk -F'\t' '$3 == "FAIL" {bad=1} END{exit bad}' "$SKIP_TIMING"; then
  pass "a gated suite is not logged as a FAIL"
else
  fail "the gated suite was written to TEST_TIMING_LOG as a FAIL"
fi

# --- THE RELEVANCE GATE (Phase C / ADR-181, extended by its 2026-08-12 addendum) --------------
# These suites are a large share of a full local run and guard paths most PRs never touch. The
# gate declines them on an irrelevant diff — which is only safe if the decline is DERIVED from the
# diff rather than from anything ambient, and if every bypass really bypasses.
#
# Every arm below drives a SYNTHETIC diff fixture. None reads the branch's real diff: an arm
# whose verdict depends on what this worktree happens to have edited today would pass or fail
# for reasons that have nothing to do with the gate.
#
# THE TABLE, NOT TWO SCALARS. The predecessor held the two batteries' labels in a pair of
# hand-named scalars and every assertion below enumerated them, so adding a third gated suite left
# this suite quantifying over 2 of 3 while its comments silently became false. (Those two
# identifiers are deliberately not spelled here: an acceptance check greps this file for them to
# prove they are gone, and a body-grep sees comments too.) Driving every arm from GATED makes this
# suite quantify over gated suites STRUCTURALLY: a fifth gate inherits every arm here for free,
# and a gate added to test-all.sh without a row here reds at the REGISTRATION FLOOR below, which
# derives the expected set from the runner. The linter's own floor does NOT cover this table --
# it compares RELEVANCE_ARRAYS against the runner and never reads GATED.
#
# label | the predicate array in scripts/lib/test-relevance-paths.sh that gates it.
# The label MUST be byte-identical to skip_suite's $1 at the call site — that is skip_suite's
# documented contract, and the RECORDED_SUITE probe below reads the same string.
GATED=(
  "tests/scripts/registry-gate-mutation-battery|REGISTRY_BATTERY_PATHS"
  "scripts/cf-tunnel-liveness-gate-mutations|CF_TUNNEL_BATTERY_PATHS"
  "plugins/soleur/test/c4-from-components.test.sh|C4_PRODUCER_PATHS"
  ".github/scripts/test/run-all.sh|GITHUB_SCRIPTS_SUITE_PATHS"
  "apps/web-platform [unit]|WEBPLAT_APP_PATHS"
)

# REGISTRATION FLOOR, derived from $TARGET — not a hand-typed literal.
#
# THE GAP THIS CLOSES, and it was live: `GATED` is a SIXTH declaration site for a gated suite, and
# nothing kept it in sync with the runner. An earlier revision guarded it with `-lt 4` and a comment
# claiming "a gate added to test-all.sh without an entry here reds via the derived floor in
# scripts/lint-orphan-test-suites.sh". That floor compares RELEVANCE_ARRAYS against the runner and
# never reads GATED. So a fifth gate added by following the HOW-TO block verbatim left the linter
# green, this file's floor green (5 >= 4), and every arm below quantifying over 4 of 5 — while
# MIN_ASSERTIONS shrank in lockstep because it derives from ${#GATED[@]}. That is verbatim the
# defect this table was introduced to remove, one level up. Three independent review agents found
# it; the comment asserting it could not happen is what made it worth all three.
#
# NAMES, not just a count. A cardinality floor cannot see a SUBSTITUTION — swap which array backs
# which gate and 4 == 4 still holds. Comparing the sorted array names the runner actually
# dereferences against the names GATED registers catches both directions.
#
# NOT a tautology: the expected set comes from $TARGET (scripts/test-all.sh, the artifact under
# test) while GATED is hand-maintained here, so the two operands have independent lifetimes. The
# one thing this cannot check is the label<->array PAIRING, which check_element_arms covers
# behaviourally.
RUNNER_ARRAYS=$(sed 's/[[:space:]]*#.*$//' "$TARGET" \
  | grep -oE '_diff_touches +"?\$\{[A-Z0-9_]+\[@\]' \
  | grep -oE '[A-Z0-9_]+\[@\]' | sed 's/\[@\]//' | sort -u)
GATED_ARRAYS=$(printf '%s\n' "${GATED[@]}" | sed 's/^[^|]*|//' | sort -u)
if [[ "$RUNNER_ARRAYS" != "$GATED_ARRAYS" ]]; then
  echo "FATAL: GATED does not match the predicate arrays scripts/test-all.sh dereferences." >&2
  echo "  runner: $(printf '%s' "$RUNNER_ARRAYS" | tr '\n' ' ')" >&2
  echo "  GATED : $(printf '%s' "$GATED_ARRAYS" | tr '\n' ' ')" >&2
  echo "  Every gated suite needs a GATED row, or its decline is asserted by nothing here." >&2
  exit 1
fi
# Non-vacuity: an extraction that silently yielded nothing would make the comparison above
# trivially true on both sides. The runner carries at least the two ADR-181 batteries.
if [[ "$(printf '%s\n' "$RUNNER_ARRAYS" | grep -c .)" -lt 2 ]]; then
  echo "FATAL: extracted fewer than 2 predicate arrays from $TARGET -- the registration floor certified nothing." >&2
  exit 1
fi

# $1 = label. Echoes 1 if that gated suite ran in the LAST run_gate_arm, else 0. Stdout is its
# ONLY contract, so `$( )` is safe here — it mutates nothing the caller needs back.
gate_ran() {
  local i
  for i in "${!GATED[@]}"; do
    if [[ "${GATED[$i]%%|*}" == "$1" ]]; then printf '%s' "${GATE_RAN[$i]}"; return 0; fi
  done
  printf 'MISSING'
  return 1
}

# $1 = arm label, $2 = newline-separated diff fixture, rest = extra VAR=VALUE env.
# Sets GATE_RAN (parallel to GATED) and GATE_OUT.
run_gate_arm() {
  local label="$1" diff_fixture="$2"; shift 2
  local sb="$TMP/test-all-gate-${label}.sh"
  # Reset BEFORE the build. Every caller uses `|| true`, so an early return here would leave the
  # PREVIOUS arm's verdicts in GATE_RAN/GATE_OUT and the assertions below would read them as this
  # arm's. Zeroing first makes a build failure read as "nothing ran", which is true.
  GATE_RAN=(); GATE_OUT=""
  local _i; for _i in "${!GATED[@]}"; do GATE_RAN[$_i]=0; done
  build_sandbox "$sb" 0 >/dev/null || { fail "sandbox build failed for gate arm $label"; return 1; }
  export SANDBOX_RECORD="$TMP/record-gate-${label}.txt"
  : > "$SANDBOX_RECORD"
  # SOLEUR_TEST_FORCE_ALL and CI are CLEARED here, before "$@", so an arm that wants either can
  # still set it and win (env takes the last assignment).
  #
  # This is not defensive noise — it is the arm's entire premise. Both are unconditional bypasses
  # in _diff_touches, so an INHERITED value makes every decline unreachable and each
  # "battery is declined" assertion passes vacuously. Two environments set them for real: the
  # sanctioned gate run exports SOLEUR_TEST_FORCE_ALL=1, and CI sets CI=1 on every job — so
  # without this line the suite is green on a developer laptop and RED in the required `test`
  # check, which is the worst possible split. Same class as the documented vitest trap where
  # vi.unstubAllEnvs() cannot clear a process-inherited variable.
  # TEST_TIMING_LOG is REDIRECTED to a per-arm file, never inherited. skip_suite and the
  # run-boundary bytes probe both append to whatever TEST_TIMING_LOG names, so a sandbox arm
  # that inherits the caller's path writes ITS rows into the operator's real timing log.
  # Measured on the sanctioned gate run before this line existed: 12 spurious
  # `skip=not_in_diff` rows and 26 spurious `bytes_tmp=0` boundary rows landed in the log the
  # run's own measurement was read from. A test suite must not write into the artifact the
  # thing under test produces.
  GATE_OUT=$(cd "$REPO_ROOT" && env SOLEUR_TEST_FORCE_ALL= CI= SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
             TEST_GROUP=all SOLEUR_INCIDENT_SKIP=0 \
             TEST_TIMING_LOG="$TMP/gate-timing-${label}.tsv" \
             SANDBOX_DIFF_NAMES="$diff_fixture" "$@" timeout 300 bash "$sb" 2>&1)
  # Reads a FILE directly, never `cmd | grep -q`: under this file's `set -o pipefail` an early
  # match makes the producer take SIGPIPE (141) and the condition evaluates FALSE despite the
  # match — a fail-open whose likelihood scales with the record's size.
  GATE_RAN=()
  local i lbl
  for i in "${!GATED[@]}"; do
    lbl="${GATED[$i]%%|*}"
    if grep -qxF "RECORDED_SUITE:$lbl" "$SANDBOX_RECORD"; then GATE_RAN[$i]=1; else GATE_RAN[$i]=0; fi
  done
  return 0
}

DOCS_ONLY_DIFF='README.md
knowledge-base/project/learnings/2026-01-01-some-learning.md'

# --- Negative-control PAIR. One arm alone proves nothing: an implementation that always skips
# --- passes the skip arm, and one that never skips passes the run arm. Only the pair is a gate.
run_gate_arm docs-only "$DOCS_ONLY_DIFF" || true
DOCS_GATE_OUT="$GATE_OUT"

# THE DECLINE IS A COUNTED VERDICT, NOT PRINTED TEXT. The per-suite grep below asserts the skip was
# ANNOUNCED; nothing asserted it was COUNTED. Measured: replacing a gate's skip_suite call with bare
# echoes emitting byte-identical output left this suite at 99/0 while the denominator dropped 303 ->
# 302 and `skipped` 5 -> 4 -- the #3366 class (a suite silently leaving the denominator behind a
# green summary) live for all four ADR-181 gates. The Phase-B denominator arms above cannot see it:
# they run with SOLEUR_TEST_FORCE_ALL=1, so they measure only the infra gate.
#
# Expected skipped = every gated suite + the infra runner's own not_in_diff decline on this fixture.
if parse_summary "$DOCS_GATE_OUT"; then
  DOCS_TOTAL="$PARSED_TOTAL"; DOCS_SKIP="$PARSED_SKIP"
  pass "the docs-only run reports a parseable summary"
else
  DOCS_TOTAL=""; DOCS_SKIP=""
  fail "the docs-only run's summary does not parse"
fi
if [[ "$DOCS_SKIP" == "$(( ${#GATED[@]} + 1 ))" ]]; then
  pass "every relevance decline is COUNTED (skipped=$DOCS_SKIP = ${#GATED[@]} gated + 1 infra)"
else
  fail "declines are announced but not counted: skipped=$DOCS_SKIP, expected $(( ${#GATED[@]} + 1 ))"
fi

for g in "${GATED[@]}"; do
  lbl="${g%%|*}"
  if [[ "$(gate_ran "$lbl")" == 0 ]]; then
    pass "docs-only diff: $lbl is declined"
  else
    fail "docs-only diff: $lbl ran anyway"
  fi
  # The decline must be an ANNOUNCED, counted verdict rather than an absence — the else-arm
  # property. Asserted per gated suite, so deleting any one gate's skip_suite else-arm (leaving a
  # bare `continue` or a silent `if`) reds here instead of silently dropping that suite from the
  # denominator.
  if grep -qF "[skip] $lbl (relevance)" <<<"$GATE_OUT"; then
    pass "$lbl is announced as a counted relevance skip"
  else
    fail "$lbl was declined silently"
  fi
  # ACTIONABLE, not merely honest. Measured: pointing a gate's re-run command at a nonexistent file
  # left the suite green -- the "skip must be ACTIONABLE" trio above was asserted for the infra
  # label only.
  #
  # Read the line FOLLOWING the label, do NOT assume `bash <label>`. The label is a DISPLAY string
  # and diverges from the suite path for both batteries (`tests/scripts/registry-gate-mutation-
  # battery` vs `tests/scripts/test-registry-gate-mutation-battery.sh`) -- a first draft of this very
  # assertion assumed they were equal and red-flagged two correctly-wired suites, which is the same
  # mistake that got the static pairing check cut at plan time.
  #
  # TWO accepted shapes, because not every gated suite is a shell script. The
  # webplat projects (#7498) are a vitest invocation, and forcing them into a
  # `bash …*.sh` spelling would mean printing `bash scripts/test-all.sh webplat`
  # — which re-enters the SAME gate on the SAME diff and declines again. A
  # re-run command that reproduces the decline is not actionable, which is the
  # property this arm exists to protect.
  #
  # The "points at something real" half is kept for both shapes: the referenced
  # script or workspace directory must exist. That is the measured failure the
  # comment above records, and it is what stops this from becoming a shape check.
  _rerun="$(grep -A3 -F "[skip] $lbl (relevance)" <<<"$GATE_OUT" | grep -E '^ +(bash .*\.sh( |$)|cd [A-Za-z0-9_./-]+ && npm run )' | head -1)"
  _rerun_target=""
  if [[ "$_rerun" =~ bash[[:space:]]+([A-Za-z0-9_./-]+\.sh) ]]; then
    _rerun_target="${BASH_REMATCH[1]}"
  elif [[ "$_rerun" =~ cd[[:space:]]+([A-Za-z0-9_./-]+)[[:space:]]+\&\& ]]; then
    _rerun_target="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$_rerun" && -n "$_rerun_target" && -e "$REPO_ROOT/$_rerun_target" ]]; then
    pass "$lbl's decline carries a runnable re-run command"
  else
    fail "$lbl's decline has no usable re-run command (line='$_rerun' target='$_rerun_target')"
  fi
done

# The recovery path for ALL declines, not just the per-suite re-run commands. EXACTLY ONCE:
# printed per-decline it would be five identical lines on an ordinary docs-only run, which is how
# an actionable line becomes noise a reader learns to skip.
if [[ "$(grep -cF 'SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh' <<<"$GATE_OUT")" == 1 ]]; then
  pass "a run with declines prints the force-all lever exactly once"
else
  fail "the force-all lever is printed $(grep -cF 'SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh' <<<"$GATE_OUT") times on a run with declines, expected exactly 1"
fi

run_gate_arm registry-touched 'scripts/registry-pull-path-health.sh' || true
if [[ "$(gate_ran 'tests/scripts/registry-gate-mutation-battery')" == 1 ]]; then
  pass "a diff touching registry-pull-path-health.sh runs the registry battery"
else
  fail "a diff touching the registry gate's own SUT did NOT run its battery"
fi
if [[ "$(gate_ran 'scripts/cf-tunnel-liveness-gate-mutations')" == 0 ]]; then
  pass "that same diff still declines the unrelated cf-tunnel battery"
else
  fail "the cf-tunnel battery ran on a diff that does not touch it"
fi

# --- P0-3 regression. The first draft's cf-tunnel predicate omitted four workflows the battery
# --- actually depends on. M4 mutates git-data-cutover.yml and the W7 oracle pins it, so a PR
# --- removing the bridge `uses:` there would fail W7 AND crash M4 — while the battery sat
# --- skipped, reporting green.
run_gate_arm cutover-touched '.github/workflows/git-data-cutover.yml' || true
if [[ "$(gate_ran 'scripts/cf-tunnel-liveness-gate-mutations')" == 1 ]]; then
  pass "a diff touching git-data-cutover.yml runs the cf-tunnel battery (P0-3)"
else
  fail "P0-3 regression: git-data-cutover.yml is not in the cf-tunnel predicate"
fi

# --- DIRECTORY pathspecs must match a CHILD path, not only the directory string ---------------
# check_element_arms below feeds each declared element LITERALLY, so a directory element proves
# substring matching on the directory string and nothing more. The "closed under future
# additions" claim that justifies declaring plugins/soleur/lib as a directory rests entirely on
# a CHILD path matching, which is what this arm pins. (An earlier comment claimed the
# grep -qF -> grep -qxF mutation "reds only here"; that is false -- rename-old-path and
# infra-suite-added red under it too. The mutation is caught, by three arms, not one.)
run_gate_arm dir-child 'plugins/soleur/lib/anything.ts' || true
if [[ "$(gate_ran 'plugins/soleur/test/c4-from-components.test.sh')" == 1 ]]; then
  pass "a directory pathspec arms its suite on a CHILD path (plugins/soleur/lib/anything.ts)"
else
  fail "a directory pathspec did NOT match a child path — the closed-by-construction claim is false"
fi

# --- The .github runner's non-obvious element -------------------------------------------------
# test-infra-suite-registration.sh derives its expected set from `git ls-files` against the REAL
# tree, so a commit ADDING an infra suite without registering it in infra-validation.yml is
# exactly the diff that must run this runner. A `.github`-only predicate would have declined it.
run_gate_arm infra-suite-added 'apps/web-platform/infra/new-thing.test.sh' || true
if [[ "$(gate_ran '.github/scripts/test/run-all.sh')" == 1 ]]; then
  pass "a diff adding an infra suite runs the .github fixture runner"
else
  fail "apps/web-platform/infra is not in the .github runner's predicate — the real-tree read is ungated"
fi

# --- WIDENING is a defect too, and it was observable by nothing --------------------------------
# Every arm above asserts a suite RUNS on a relevant diff, or that all four decline on a docs-only
# one. None can see a predicate becoming TOO BROAD: measured, adding "scripts" to C4_PRODUCER_PATHS
# left the suite green at one assertion MORE (the new element earns its own passing element arm),
# while the c4 gate would then arm on nearly every diff and the 96% skip rate the feature is
# justified by silently becomes ~0.
#
# A targeted negative fixture is the cheap pin: scripts/ is where this runner and its libraries
# live, it is touched constantly, and no c4 dependency sits there except the predicate data file
# itself -- which is named in full, so a whole-path element still declines on a sibling file.
run_gate_arm scripts-only 'scripts/test-all.sh' || true
if [[ "$(gate_ran 'plugins/soleur/test/c4-from-components.test.sh')" == 0 ]]; then
  pass "a scripts-only diff still declines the c4 suite (the predicate has not been widened)"
else
  fail "the c4 predicate arms on an unrelated scripts/ file -- it has been widened and the skip rate is gone"
fi

# --- COMPLETENESS: every declared predicate path must actually ARM its battery -----------
# THE GAP THIS CLOSES. Before this loop the suite drove a positive fixture for 1 of 8 registry
# elements and 5 of 11 cf-tunnel elements, so the predicate arrays could be TRIMMED to exactly
# the asserted paths and both this suite and lint-orphan-test-suites.sh stayed green (measured:
# 47/0 and `orphan test suites: none` with the bridge action -- the very gate the cf-tunnel
# battery exists to guard -- deleted from the array).
#
# That is a soundness/completeness split: the linter checks that every DECLARED path resolves,
# self-includes, is non-empty and is consumed. None of those can see a path silently REMOVED,
# because a shorter list satisfies all four. This loop is the completeness half -- one positive
# fixture per element, driven from the array itself, so deleting an element deletes its own
# assertion AND trips the derived floor below.
#
# The realistic mutation it blocks: someone measures that a battery "skips too rarely", trims the
# array to the paths the tests cover, and ships green -- after which a PR removing the bridge
# `uses:` declines the battery and reports green, which is verbatim the P0-3 scenario.
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$REPO_ROOT/scripts/lib/test-relevance-paths.sh"

check_element_arms() {
  local lbl="$1" path="$2"
  run_gate_arm "elem-$(printf '%s' "$path" | tr '/.' '__')" "$path" || return 0
  if [[ "$(gate_ran "$lbl")" == 1 ]]; then
    pass "predicate element arms its suite ($lbl): $path"
  else
    fail "predicate element does NOT arm its suite ($lbl): $path"
  fi
}

# DRIVEN FROM GATED, not from two named arrays. This is the completeness half for EVERY gated
# suite: without it C4_PRODUCER_PATHS could be trimmed to {self, THIS FILE} with the linter's five
# checks and this harness both green — and a PR editing only the C4 producer would then decline
# the very suite that exists to test it.
#
# ELEM_TOTAL is accumulated here rather than recomputed at the floor, so the floor cannot drift
# from what actually ran.
ELEM_TOTAL=0
for g in "${GATED[@]}"; do
  lbl="${g%%|*}"; arr="${g#*|}"
  # bash 3.2 has no `declare -n`, so the array is expanded by name via eval — the same idiom
  # scripts/lint-orphan-test-suites.sh uses, for the same reason. `${a[@]+"${a[@]}"}` so an EMPTY
  # array does not trip `set -u` on bash < 4.4.
  eval "elems=( \${${arr}[@]+\"\${${arr}[@]}\"} )"
  # shellcheck disable=SC2154  # elems is assigned by the eval above; bash 3.2 has no declare -n,
  #   so the array must be expanded by name and shellcheck cannot follow it.
  if [[ "${#elems[@]}" -eq 0 ]]; then
    fail "predicate array $arr is EMPTY or undeclared — every element arm for $lbl would pass over nothing"
    continue
  fi
  ELEM_TOTAL=$(( ELEM_TOTAL + ${#elems[@]} ))
  for p in "${elems[@]}"; do check_element_arms "$lbl" "$p"; done
done

# --- W7 completeness against the oracle's own literal ------------------------------------
# A pure SET check (no sandbox run): the loop above already proves each listed workflow arms the
# battery; this proves the LIST still matches what the oracle pins. Read from W7_EXPECTED rather
# than restated here, so a new bridge adopter reds until the predicate learns it too.
W7_LITERAL=$(grep -oE '^W7_EXPECTED="[^"]+"' "$REPO_ROOT/scripts/check-cloudflare-token-drift.test.sh" | head -1 | sed 's/^W7_EXPECTED="//; s/"$//')
W7_FILES=()
if [[ -n "$W7_LITERAL" ]]; then
  pass "the W7_EXPECTED literal was located in the oracle"
  IFS=',' read -r -a W7_FILES <<<"$W7_LITERAL"
  for wf in "${W7_FILES[@]}"; do
    if grep -qxF ".github/workflows/${wf}" <<<"$(printf '%s\n' "${CF_TUNNEL_BATTERY_PATHS[@]}")"; then
      pass "W7 workflow $wf is present in the cf-tunnel predicate"
    else
      fail "W7 workflow $wf is MISSING from the cf-tunnel predicate"
    fi
  done
else
  fail "could not read W7_EXPECTED from the oracle — the completeness check is vacuous"
fi

# --- RENAME: the OLD path must still arm the battery ----------------------------------------
# `git diff --name-only` emits only a rename's DESTINATION, so `git mv` on a declared predicate
# path leaves the array's path absent from the diff and declines the battery on the most
# destructive possible edit to its own SUT. The runner therefore also feeds `--name-status -M`,
# whose `R100<TAB>old<TAB>new` rows make BOTH paths matchable.
#
# Two arms, because they pin different halves and each is weak alone: the fixture proves the
# MATCHING works on a rename-shaped row, and the source anchor proves the runner actually asks
# git for those rows. Without the second, deleting the `--name-status` invocation leaves this
# fixture green; without the first, the invocation could feed a shape nothing matches.
run_gate_arm rename-old-path "$(printf 'R100\tscripts/registry-pull-path-health.sh\tscripts/registry-pph.sh')" || true
if [[ "$(gate_ran 'tests/scripts/registry-gate-mutation-battery')" == 1 ]]; then
  pass "a renamed predicate path still arms its battery via the rename source"
else
  fail "a rename hid the OLD path from the predicate — the battery declined on a git mv of its SUT"
fi
if grep -qE '^\$\(git -c core\.quotePath=false diff --name-status -M ' "$TARGET"; then
  pass "the runner feeds rename sources into the diff blob"
else
  fail "the runner no longer asks git for --name-status -M, so rename sources are invisible"
fi

# --- SOURCE ANCHORS for the UNTRACKED arm, for the same reason the rename arm carries one -----
# build_sandbox injects `[[ -n "$SANDBOX_DIFF_NAMES" ]] && _diff_names="$SANDBOX_DIFF_NAMES"`
# AFTER the four-source assembly, replacing the blob WHOLESALE. So every fixture arm above pins
# the MATCHER and none of them can pin the ASSEMBLY. Deleting the untracked line from test-all.sh
# leaves every arm in this file green — which is exactly what the existing rename pair says about
# `--name-status -M`, one source over.
#
# Two halves, because the untracked arm has two independent failure modes: the invocation can be
# deleted, or the prefix list it is scoped to can lose an entry. The second is what makes
# plugins/soleur load-bearing: without that prefix, a brand-new UNTRACKED fixture corpus is
# invisible to C4_PRODUCER_PATHS and the c4 suite declines on the diff that added it.
if grep -qF 'git ls-files --others --exclude-standard -- "${TEST_RELEVANCE_PREFIXES[@]}"' "$TARGET"; then
  pass "the runner feeds untracked files into the diff blob, scoped to the declared prefixes"
else
  fail "the runner no longer asks git for untracked files, so a new UNTRACKED target is invisible"
fi
if grep -qxF 'plugins/soleur' <<<"$(printf '%s\n' "${TEST_RELEVANCE_PREFIXES[@]}")"; then
  pass "TEST_RELEVANCE_PREFIXES covers plugins/soleur, so the untracked arm can see c4 fixtures"
else
  fail "TEST_RELEVANCE_PREFIXES lost plugins/soleur — untracked c4 fixtures are invisible to the predicate"
fi

# --- REAL GIT STATE: the assembly itself, not its spelling -------------------------------------
# THE GAP THIS CLOSES. Both source anchors above grep $TARGET for a command's TEXT. That pins the
# spelling and nothing else: measured, renaming the ASSIGNMENT TARGET one line above each of them
# (`_diff_names="${_diff_names}` -> `_unused=...`) left every anchor matching and this whole suite at
# 99/0, while a scratch repo showed the .github runner declining on an untracked infra suite and the
# registry battery declining on a `git mv` of its own SUT -- verbatim the two failures those arms
# were written for. No fixture arm can see it either, BY CONSTRUCTION: build_sandbox injects
# `_diff_names="$SANDBOX_DIFF_NAMES"` AFTER the four-source assembly, replacing the blob wholesale.
#
# So this arm drives neither. It extracts the real assembly from $TARGET and evaluates it inside a
# throwaway git repo carrying exactly the two states in question, then asserts the resulting blob
# contains what the predicates must match. Retarget any assignment in that block and this reds.
REAL_REPO="$TMP/realstate"
mkdir -p "$REAL_REPO"
(
  set -e
  cd "$REAL_REPO"
  git init -q -b main .
  git config user.email t@t; git config user.name t
  mkdir -p scripts/lib plugins/soleur/test/fixtures/component-docs apps/web-platform/infra
  echo x > scripts/registry-pull-path-health.sh
  git add -A && git commit -q -m base
  git branch -f origin/main main 2>/dev/null || true
  git update-ref refs/remotes/origin/main HEAD
  git mv scripts/registry-pull-path-health.sh scripts/registry-pph.sh
  git commit -q -am rename
  # untracked, under a declared prefix
  echo y > apps/web-platform/infra/brand-new.test.sh
) >/dev/null 2>&1 || { fail "real-state scratch repo could not be built"; }

if [[ -d "$REAL_REPO/.git" ]]; then
  ASSEMBLY="$TMP/assembly.sh"
  awk '/^_diff_detect_ok=0$/,/git ls-files --others/' "$TARGET" > "$ASSEMBLY"
  # Non-vacuity: an extraction that came back short would make every assertion below pass over an
  # empty blob. All four sources must be present in what we are about to run.
  if [[ "$(grep -c 'git ' "$ASSEMBLY")" -ge 4 ]]; then
    pass "the real _diff_names assembly was extracted from the runner (all four sources)"
  else
    fail "could not extract the four-source assembly from $TARGET -- the arms below certify nothing"
  fi
  REAL_BLOB=$(cd "$REAL_REPO" && env -u GIT_DIR bash -c "
    source '$REPO_ROOT/scripts/lib/test-relevance-paths.sh'
    $(cat "$ASSEMBLY")
    printf '%s' \"\$_diff_names\"" 2>/dev/null || true)

  if grep -qF 'scripts/registry-pull-path-health.sh' <<<"$REAL_BLOB"; then
    pass "the assembly really feeds a rename's OLD path into the blob"
  else
    fail "a git mv of a declared SUT does not reach _diff_names -- the battery declines on its own rename"
  fi
  if grep -qF 'apps/web-platform/infra/brand-new.test.sh' <<<"$REAL_BLOB"; then
    pass "the assembly really feeds UNTRACKED files into the blob"
  else
    fail "an untracked file under a declared prefix does not reach _diff_names -- the gate is blind to uncommitted work"
  fi
fi

# --- Fail SAFE, not fail quiet. An undeterminable diff must RUN everything. Skipping on a diff
# --- the runner could not read is the one direction that turns this feature into a hazard.
run_gate_arm undeterminable "$DOCS_ONLY_DIFF" SANDBOX_DETECT_OK=0 || true
for g in "${GATED[@]}"; do
  lbl="${g%%|*}"
  if [[ "$(gate_ran "$lbl")" == 1 ]]; then
    pass "an undeterminable diff runs $lbl (fail-SAFE)"
  else
    fail "an undeterminable diff DECLINED $lbl — the one direction that makes this a hazard"
  fi
done

# --- The two bypasses. Both assert the suite EXECUTES — not that a warning fired. Under CI the
# --- decline must be UNREACHABLE rather than merely detected: an assertion-based design would
# --- have reddened main-health-monitor every six hours, because on `main` both diff refs resolve
# --- and return empty, so both batteries would skip and the assertion would fire (P0-2).
run_gate_arm force-all "$DOCS_ONLY_DIFF" SOLEUR_TEST_FORCE_ALL=1 || true
# THE DENOMINATOR IS THE CONTROLLED VARIABLE. These two arms differ only in whether the gates
# declined, so `suites` must be identical: a decline that removed its suite from the denominator
# instead of counting it would show up here as a smaller total on the docs-only side. This is the
# Phase-B denominator assertion extended to the relevance gates, which it never covered.
if parse_summary "$GATE_OUT" && [[ -n "$DOCS_TOTAL" ]]; then
  if [[ "$PARSED_TOTAL" == "$DOCS_TOTAL" ]]; then
    pass "declining leaves the denominator intact ($DOCS_TOTAL both ways)"
  else
    fail "declining changed the denominator: forced=$PARSED_TOTAL declined=$DOCS_TOTAL"
  fi
else
  fail "could not compare denominators across the declining and forcing arms"
fi
for g in "${GATED[@]}"; do
  lbl="${g%%|*}"
  if [[ "$(gate_ran "$lbl")" == 1 ]]; then
    pass "SOLEUR_TEST_FORCE_ALL=1 runs $lbl on a docs-only diff"
  else
    fail "SOLEUR_TEST_FORCE_ALL=1 did not force $lbl"
  fi
done
# THE OTHER SIDE OF THE THRESHOLD. The "exactly once" assertion above is evaluated on an arm that
# always has declines, so it pins the count and not the CONDITION -- hoisting the lever out of its
# `if` so it printed on every run left the suite green. This arm has zero RELEVANCE declines (the
# infra runner still declines with not_in_diff, which the lever cannot recover), so a lever gated on
# `skipped` rather than on relevance declines reds here, and advice that does not terminate is
# caught rather than argued about.
if [[ "$(grep -cF 'SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh' <<<"$GATE_OUT")" == 0 ]]; then
  pass "the force-all lever is silent when no relevance decline occurred"
else
  fail "the force-all lever printed on a run it cannot help -- obeying it would re-print it verbatim"
fi

run_gate_arm ci-set "$DOCS_ONLY_DIFF" CI=1 || true
# CAPTURED IMMEDIATELY. The structural assertion below must read THIS arm's output; the
# predecessor consumed whatever the last arm happened to leave in GATE_OUT and was correct only
# by arm ordering, which a widened surface makes fragile.
CI_GATE_OUT="$GATE_OUT"
for g in "${GATED[@]}"; do
  lbl="${g%%|*}"
  if [[ "$(gate_ran "$lbl")" == 1 ]]; then
    pass "CI=1 runs $lbl on a docs-only diff (P0-2: the decline is unreachable)"
  else
    fail "CI=1 declined $lbl, which would leave it running in fewer runners than it needs"
  fi
done
# STRUCTURAL, not a member list. The predecessor named the two batteries under a comment saying
# "the two batteries have no other CI home at all" — true of them, and true of the c4 suite, whose
# ONLY CI home is `bash scripts/test-all.sh scripts`. Leaving the assertion enumerated would have
# made it cover 2 of 3 qualifying suites while its own comment silently became false, so it is
# re-pointed at the PROPERTY: under CI, no relevance decline may occur at all.
#
# Excluding by REASON rather than by naming members is what keeps the legitimate infra decline
# passing. In this arm TEST_GROUP=all, SOLEUR_INCIDENT_SKIP=0 and _infra_in_diff=0, so the only
# decline present is the infra runner's `not_in_diff`; `incident` requires the bypass variable,
# and `group` never reaches skip_suite. Every future gated suite is covered for free.
if grep -qE '^\[skip\] .* \(relevance\)$' <<<"$CI_GATE_OUT"; then
  fail "a CI run produced a relevance decline, which would leave a suite running in zero runners: $(grep -E '^\[skip\] .* \(relevance\)$' <<<"$CI_GATE_OUT" | tr '\n' ' ')"
else
  pass "a CI run produces no relevance decline at all (structural, not a member list)"
fi

# --- Anti-vacuity floor ---------------------------------------------------------------------
# Every assertion above lives inside a loop or a conditional. Strand the block — an early exit,
# a renamed TARGET, a sandbox build that silently fails — and this file would report
# "0 passed, 0 failed / exit 0", which reads exactly like a clean run. A FLOOR, not equality:
# the count is developer-incremented and `-eq` turns every added assertion into a false red.
# DERIVED, not a hand-typed integer. The loops above contribute one assertion per predicate
# element and one per W7 workflow, all of which are variable-cardinality — so a fixed literal
# acquires slack every time a list grows, and that slack can then subsidise a DELETED fixed
# assertion. Measured before this change: adding one W7 adopter and deleting the entire P0-3
# regression block left the suite at 47/47 green with `grep -c 'P0-3'` == 0.
#
# MIN_FIXED is the count of assertions NOT produced by those loops; it is the only number that
# should ever be edited by hand, and only when a fixed assertion is deliberately added.
#
# EVERY VARIABLE-CARDINALITY LOOP MUST APPEAR IN THIS EXPRESSION, or its growth becomes slack that
# can subsidise a deleted fixed assertion. There are three such sources:
#
#   6 * ${#GATED[@]}  — the per-gated-suite arms: docs-only contributes THREE (declined, announced,
#                       re-run command), then undeterminable, force-all and ci-set one each.
#   $ELEM_TOTAL       — one arm per declared predicate element, ACCUMULATED by the loop that ran
#                       them rather than recomputed here, so the floor cannot drift from reality.
#   ${#W7_FILES[@]}   — one per workflow the cf-tunnel oracle pins.
#
# MIN_FIXED is the count of assertions produced by NONE of those loops, and it is the only number
# here that is ever edited by hand. Derivation from the pre-review revision, stated so the next
# editor can check it rather than trust it: 44 (that revision's MIN_FIXED) − 6 relevance assertions
# that became per-GATED loop members (two docs-only declines, one "announced", plus one each from
# the undeterminable / force-all / ci-set arms) + 12 fixed assertions added since (the force-all
# lever count; dir-child; infra-suite-added; the two source anchors; the two pass()/fail() controls;
# the docs-only summary parse; the counted-verdict check; the real-state extraction control; and the
# real-state rename and untracked arms; the cross-arm denominator check; the lever-silent-when-inert check; and the widening guard) = 53.
#
# KNOWN, AND DELIBERATE: this floor cannot certify the predicate ARRAYS, because ELEM_TOTAL is
# derived from the same arrays the element loop walks — trim one and both the observed count and the
# floor drop together. That completeness question is answered in scripts/lint-orphan-test-suites.sh,
# which reads the arrays independently (a per-array cardinality floor plus the this-file
# self-inclusion check). Do not try to fix it here; a floor derived from its own subject is a
# tautology whichever way it is written.
MIN_FIXED=53
MIN_ASSERTIONS=$(( MIN_FIXED + (6 * ${#GATED[@]}) + ELEM_TOTAL + ${#W7_FILES[@]} ))
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= $MIN_ASSERTIONS — the suite was stranded, not clean." >&2
  exit 1
fi

echo ""
echo "test-all-infra-coverage-notice.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
