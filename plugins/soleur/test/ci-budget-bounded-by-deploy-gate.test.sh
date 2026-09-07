#!/usr/bin/env bash
#
# Guard 2 (#7902) — CI'S DECLARED BUDGET IS BOUNDED BY THE DEPLOY GATE'S CEILING.
#
# PROPERTY. The declared execution ceilings of `test`'s `needs`-closure, plus `test`'s own, fit
# under `web-platform-release.yml`'s `CEILING_S` — so CI cannot be grown past what the deploy
# gate can absorb without a required check going red AT THE MOMENT OF DIVERGENCE, rather than
# days later as a blocked production deploy. That is exactly how #7902 was discovered.
#
# MAX, NOT SUM, and the distinction is the arithmetic rather than a simplification. The three
# shards carry no `needs:` between them, so they run in PARALLEL; only the aggregator is serial
# after them. The critical path is therefore `max(shard ceilings) + test's own`. This mirrors
# `scripts/prod-version-drift-check.sh`, which computes `max(release, await-ci) + migrate + ...`
# for the same reason.
#
# RESOLVED, NOT RESTATED. `CEILING_S` is read out of web-platform-release.yml rather than copied
# here, so the two cannot drift. A row below pins that: the value this guard used must actually
# occur in that workflow, which is what makes a hardcoded literal detectable.
#
# THE PINNED CLOSURE IS NOT REDUNDANT WITH THE DERIVED WALK (B8e's shape). A guard that derives
# closure membership from the graph is definitionally green after a graph edit — and a graph edit
# is precisely how a job leaves the guarded set while still gating the deploy. The derived walk
# catches ceiling drift; the pin catches membership drift. Neither subsumes the other.
#
# ABSENT MEANS 360, NEVER ZERO. GitHub's default job timeout is 360 minutes. Reading an absent
# `timeout-minutes` as 0 would make DELETING a ceiling shrink the computed bound and turn this
# guard green on the change it most needs to catch.
#
# set -u, NOT set -e: accumulate-then-exit.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
REL_YML="$REPO_ROOT/.github/workflows/web-platform-release.yml"

# The pinned closure (B8e's shape). Sorted, space-delimited. Changing CI's job graph so that
# `test` waits on a different set is a deliberate act that must edit this line.
PINNED_CLOSURE="test-bun test-scripts test-webplat"

GITHUB_DEFAULT_TIMEOUT_MIN=360

PASS=0
FAIL=0
pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; }

echo "=== Guard 2: CI's declared budget is bounded by the deploy gate (#7902) ==="

# --- INSTRUMENT SELF-TEST (ADR-193) ----------------------------------------------------------
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)"
fail "instrument self-test (expected — subtracted)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  echo "FATAL: instrument self-test did not move both counters — assertions here prove nothing." >&2
  exit 2
fi
PASS=$_p0; FAIL=$_f0
echo "  (instrument self-test OK — both counters move; counters reset)"

for f in "$CI_YML" "$REL_YML"; do
  [[ -f "$f" ]] || { echo "FATAL: missing $f" >&2; exit 2; }
done

# --- Derive `test`'s needs-closure from the graph --------------------------------------------
DERIVED_CLOSURE=$(awk '
  /^  test:$/ { inj=1; next }
  inj && /^  [a-z0-9_-]+:$/ { inj=0 }
  inj && /^    needs:[[:space:]]*\[/ {
    line=$0
    sub(/^[^[]*\[/, "", line)
    sub(/\].*$/, "", line)
    gsub(/[ \t]/, "", line)
    n=split(line, a, ",")
    for (i=1; i<=n; i++) if (a[i] != "") print a[i]
  }
' "$CI_YML" | sort | tr '\n' ' ' | sed 's/ $//')

# ROW (mutation 2): the walk must not return an empty set. A guard reporting "0 checked" and
# exiting 0 is vacuous, and an empty derived closure would make the max below trivially satisfied.
if [[ -n "${DERIVED_CLOSURE// /}" ]]; then
  pass "derived test's needs-closure from the graph: [$DERIVED_CLOSURE]"
else
  fail "the needs-closure walk returned an EMPTY job set — every ceiling assertion below would be vacuous. The 'test:' job block or its 'needs:' line no longer matches the expected shape."
fi

# ROW (mutation 6): derived membership must equal the pinned closure.
if [[ "$DERIVED_CLOSURE" == "$PINNED_CLOSURE" ]]; then
  pass "derived closure equals the pinned closure — no job has silently joined or left the set"
else
  fail "CLOSURE DRIFT: pinned [$PINNED_CLOSURE] but the graph now says [$DERIVED_CLOSURE]. A job that leaves this set still gates the deploy while escaping the budget; a job that joins it consumes budget nothing accounted for. If the change is deliberate, update PINNED_CLOSURE in this file in the same commit."
fi

# --- Read a job's declared ceiling ------------------------------------------------------------
#
# An absent value reads as GitHub's 360-minute default, never as zero (see header).
job_ceiling() {
  local job="$1" v
  v=$(awk -v want="  $job:" '
    $0 == want { inj=1; next }
    inj && /^  [a-z0-9_-]+:$/ { inj=0 }
    inj && /^    timeout-minutes:[[:space:]]*[0-9]+[[:space:]]*$/ {
      line=$0; sub(/^[^0-9]*/, "", line); gsub(/[[:space:]]/, "", line); print line; exit
    }
  ' "$CI_YML")
  if [[ -z "$v" ]]; then echo "$GITHUB_DEFAULT_TIMEOUT_MIN"; else echo "$v"; fi
}

# --- Resolve CEILING_S out of the release workflow ---------------------------------------------
CEILING_S=$(awk '/^[[:space:]]*CEILING_S:[[:space:]]*"[0-9]+"/ {
  line=$0; sub(/^[^"]*"/, "", line); sub(/".*$/, "", line); print line; exit
}' "$REL_YML")

if [[ "$CEILING_S" =~ ^[0-9]+$ ]] && (( CEILING_S > 0 )); then
  pass "resolved CEILING_S=${CEILING_S}s out of web-platform-release.yml"
else
  fail "could not resolve CEILING_S from web-platform-release.yml (got: '${CEILING_S:-<empty>}'). Without it this guard has no bound to check."
  CEILING_S=0
fi

# ROW (mutation 7): the value used must ACTUALLY occur in the release workflow.
#
# This is what makes a hardcoded literal detectable. A guard that restates CEILING_S instead of
# resolving it stays green while the workflow drifts underneath it — the exact coupling failure
# this guard exists to prevent, reproduced inside the guard.
if (( CEILING_S > 0 )) && grep -qF "CEILING_S: \"${CEILING_S}\"" "$REL_YML"; then
  pass "the CEILING_S this guard used is present verbatim in web-platform-release.yml (resolved, not restated)"
else
  fail "the CEILING_S value this guard is using (${CEILING_S}) does not occur in web-platform-release.yml. It has been hardcoded or the read has drifted, so the bound below is checked against a number nothing owns."
fi

# --- The bound ---------------------------------------------------------------------------------
CEILING_MIN=$(( CEILING_S / 60 ))
MAX_SHARD=0
MAX_SHARD_JOB="(none)"
for job in $DERIVED_CLOSURE; do
  c=$(job_ceiling "$job")
  if (( c >= MAX_SHARD )); then MAX_SHARD=$c; MAX_SHARD_JOB="$job"; fi
  if (( c >= GITHUB_DEFAULT_TIMEOUT_MIN )); then
    fail "job '$job' declares no timeout-minutes, so its budget is GitHub's ${GITHUB_DEFAULT_TIMEOUT_MIN}-minute default. Presence without a bound is not a budget — declare one."
  else
    pass "closure job '$job' declares a ceiling of ${c} min"
  fi
done

TEST_OWN=$(job_ceiling "test")
if (( TEST_OWN >= GITHUB_DEFAULT_TIMEOUT_MIN )); then
  fail "the 'test' aggregator declares no timeout-minutes (reads as the ${GITHUB_DEFAULT_TIMEOUT_MIN}-minute default). It sits on the deploy gate's critical path after the shards and must carry a ceiling."
else
  pass "aggregator 'test' declares a ceiling of ${TEST_OWN} min"
fi

# The comparison, as a FUNCTION so it can be positive-controlled below. Written inline it is
# neuterable by a one-token edit that leaves the row count unchanged — the failure mode Guard 1's
# battery actually demonstrated.
budget_fits() {
  local max_shard="$1" own="$2" ceiling_min="$3"
  (( ceiling_min > 0 && max_shard + own <= ceiling_min ))
}

CRITICAL_PATH=$(( MAX_SHARD + TEST_OWN ))
if budget_fits "$MAX_SHARD" "$TEST_OWN" "$CEILING_MIN"; then
  pass "BUDGET: max(closure)=${MAX_SHARD} (${MAX_SHARD_JOB}) + test=${TEST_OWN} = ${CRITICAL_PATH} min <= CEILING_S/60 = ${CEILING_MIN} min"
else
  fail "BUDGET EXCEEDED: max(closure)=${MAX_SHARD} (${MAX_SHARD_JOB}) + test=${TEST_OWN} = ${CRITICAL_PATH} min > CEILING_S/60 = ${CEILING_MIN} min. CI's declared budget no longer fits inside the deploy gate's ceiling, so a slow-but-healthy run will fail-close the deploy exactly as in #7902. Either lower a ceiling or raise CEILING_S (and DRIFT_SUSTAINED_THRESHOLD_MIN first — B9 asserts threshold >= critical path)."
fi

# POSITIVE CONTROL on the comparison. Feed it a case that MUST NOT fit and require it to say so.
if budget_fits "$CEILING_MIN" "$CEILING_MIN" "$CEILING_MIN"; then
  fail "POSITIVE CONTROL: budget_fits reported ${CEILING_MIN}+${CEILING_MIN} as fitting under ${CEILING_MIN}. It is neutered, so the budget verdict above is decorative."
else
  pass "positive control: the budget comparison rejects a critical path that exceeds the ceiling"
fi

# --- ASSERTION FLOOR ----------------------------------------------------------------------------
# printf + exit 1, never through fail() — the helper this floor backstops is what one edit disarms.
MIN_ROWS=9
TOTAL=$(( PASS + FAIL ))
if (( TOTAL < MIN_ROWS )); then
  printf 'FAIL: assertion floor — %d rows executed, expected at least %d. The suite did not run to completion, so its verdict is not evidence.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi

echo ""
echo "ci-budget-bounded-by-deploy-gate.test.sh: $TOTAL rows, $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  exit 1
fi
echo "All tests passed"
