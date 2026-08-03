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
m = re.search(r'^run_suite\(\) \{.*?^\}', s, re.S | re.M)
assert m, "could not locate run_suite() definition"
s = s[:m.start()] + 'run_suite() { echo "RECORDED_SUITE:$1" >> "$SANDBOX_RECORD"; }' + s[m.end():]

open(path, 'w').write(s)
print("sandbox built")
PY
}

# Run one arm. $1=group $2=in_diff $3=incident_skip -> sets ARM_OUT / ARM_RAN
run_arm() {
  local group="$1" in_diff="$2" incident="$3"
  local sb="$TMP/test-all-${group}-${in_diff}-${incident}.sh"
  build_sandbox "$sb" "$in_diff" >/dev/null || { fail "sandbox build failed for $group"; return 1; }
  export SANDBOX_RECORD="$TMP/record-${group}-${in_diff}-${incident}.txt"
  : > "$SANDBOX_RECORD"
  ARM_OUT=$(cd "$REPO_ROOT" && SOLEUR_INCIDENT_SKIP="$incident" TEST_GROUP="$group" \
            timeout 120 bash "$sb" 2>&1)
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

# --- Anti-vacuity floor ---------------------------------------------------------------------
# Every assertion above lives inside a loop or a conditional. Strand the block — an early exit,
# a renamed TARGET, a sandbox build that silently fails — and this file would report
# "0 passed, 0 failed / exit 0", which reads exactly like a clean run. A FLOOR, not equality:
# the count is developer-incremented and `-eq` turns every added assertion into a false red.
MIN_ASSERTIONS=20
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= $MIN_ASSERTIONS — the suite was stranded, not clean." >&2
  exit 1
fi

echo ""
echo "test-all-infra-coverage-notice.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
