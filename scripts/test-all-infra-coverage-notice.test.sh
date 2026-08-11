#!/usr/bin/env bash
# Regression suite for scripts/test-all.sh's infra COVERAGE CLAIM (#7103 R5(a) follow-up).
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

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Build a sandbox copy whose run_suite records instead of running, and whose diff-detection
# result is forced. $1 = sandbox path, $2 = 1|0 for "diff touches infra".
build_sandbox() {
  local out="$1" in_diff="$2"
  cp "$TARGET" "$out" || return 1
  # Recorder. Appended AFTER the original definition so it wins, and before any invocation.
  python3 - "$out" "$in_diff" <<'PY'
import sys, re
path, in_diff = sys.argv[1], sys.argv[2]
s = open(path).read()

# 1. Force the diff verdict deterministically: this suite is about the NOTICE, not about
#    git plumbing, and deriving it from the real repo would make the arms depend on whatever
#    the working tree happens to touch today.
old = '_infra_in_diff=0'
assert s.count(old) == 1, f"expected exactly one '{old}', found {s.count(old)}"
s = s.replace(old, f'_infra_in_diff={in_diff}\n_SANDBOX_FORCED_DIFF=1')

# 2. Neuter the detection block so it cannot overwrite the forced value.
old2 = '_infra_detect_ok=0'
assert s.count(old2) == 1, f"expected exactly one '{old2}', found {s.count(old2)}"
s = s.replace(old2, '_infra_detect_ok=1')

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

# Parse the terminal summary line into PARSED_PASS / PARSED_TOTAL / PARSED_FAIL / PARSED_SKIP.
# Returns non-zero when the line is absent or does not carry all four numbers, so a summary that
# silently reverts to a shape without the skip breakdown FAILS rather than reading as zero skips.
parse_summary() {
  local out="$1" line
  PARSED_PASS=""; PARSED_TOTAL=""; PARSED_FAIL=""; PARSED_SKIP=""
  line=$(grep -oE '=== [0-9]+/[0-9]+ suites passed \([0-9]+ failed, [0-9]+ skipped\) ===' <<<"$out" | tail -1)
  [[ -n "$line" ]] || return 1
  # shellcheck disable=SC2001
  local nums; nums=$(sed 's/[^0-9]\+/ /g' <<<"$line")
  read -r PARSED_PASS PARSED_TOTAL PARSED_FAIL PARSED_SKIP <<<"$nums"
  [[ -n "$PARSED_SKIP" ]] || return 1
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
  ARM_OUT=$(cd "$REPO_ROOT" && SOLEUR_INCIDENT_SKIP="$incident" TEST_GROUP="$group" \
            TEST_TIMING_LOG="$ARM_TIMING" timeout 120 bash "$sb" 2>&1)
  ARM_RAN=0
  grep -q 'RECORDED_SUITE:apps/web-platform/infra/run-registered-suites.sh' "$SANDBOX_RECORD" && ARM_RAN=1
  return 0
}

echo "=== test-all.sh infra coverage-notice suite ==="

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
RUN_OUT="$ARM_OUT"; RUN_TIMING="$ARM_TIMING"
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

# --- Anti-vacuity floor ---------------------------------------------------------------------
# Every assertion above lives inside a loop or a conditional. Strand the block — an early exit,
# a renamed TARGET, a sandbox build that silently fails — and this file would report
# "0 passed, 0 failed / exit 0", which reads exactly like a clean run. A FLOOR, not equality:
# the count is developer-incremented and `-eq` turns every added assertion into a false red.
MIN_ASSERTIONS=31
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= $MIN_ASSERTIONS — the suite was stranded, not clean." >&2
  exit 1
fi

echo ""
echo "test-all-infra-coverage-notice.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
