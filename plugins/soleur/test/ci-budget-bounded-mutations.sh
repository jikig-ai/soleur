#!/usr/bin/env bash
#
# MUTATION BATTERY for Guard 2 (#7902 AC13).
#
# Guard 2 (plugins/soleur/test/ci-budget-bounded-by-deploy-gate.test.sh) asserts that CI's
# declared ceilings fit under the deploy gate's CEILING_S. This breaks that seven ways and
# requires the guard to notice each.
#
# NOT NAMED `*.test.sh`, deliberately — same reason as the Guard 1 battery: it mutates workflow
# files in place, and `plugins/soleur/test/*.test.sh` is glob-discovered into the scripts group,
# so under that name it would edit files while a parent runner was mid-run. It runs from the
# dedicated `shard-totality-mutations` job in ci.yml, whose checkout is exclusive to it.
#
# Same anti-vacuity mechanics as the Guard 1 battery: pristine copies (never `git checkout`),
# an unmutated CONTROL read first, every mutation asserted to have LANDED before its verdict is
# read, exact unique anchors rather than a file-wide sed, and a re-verified restore per row.
#
# set -u, not -e: accumulate-then-exit.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARD="$REPO_ROOT/plugins/soleur/test/ci-budget-bounded-by-deploy-gate.test.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
REL_YML="$REPO_ROOT/.github/workflows/web-platform-release.yml"

PASS=0
FAIL=0
pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; }

WORK="$(mktemp -d -t budget-mut.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
P_GUARD="$WORK/guard.pristine"; cp "$GUARD" "$P_GUARD" || exit 2
P_CI="$WORK/ci.pristine";       cp "$CI_YML" "$P_CI"   || exit 2
P_REL="$WORK/rel.pristine";     cp "$REL_YML" "$P_REL" || exit 2
restore_all() { cp "$P_GUARD" "$GUARD"; cp "$P_CI" "$CI_YML"; cp "$P_REL" "$REL_YML"; }
trap 'restore_all; rm -rf "$WORK"' EXIT

echo "=== Guard 2 mutation battery (#7902 AC13) ==="

_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)"
fail "instrument self-test (expected — subtracted)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  echo "FATAL: instrument self-test did not move both counters." >&2; exit 2
fi
PASS=$_p0; FAIL=$_f0
echo "  (instrument self-test OK — both counters move; counters reset)"

mutate() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
n = s.count(old)
if n == 0: sys.stderr.write("ANCHOR MISSING\n"); sys.exit(3)
if n > 1: sys.stderr.write("ANCHOR AMBIGUOUS (%d)\n" % n); sys.exit(4)
open(path, "w").write(s.replace(old, new, 1))
PY
}
guard_rc() { bash "$GUARD" > "$WORK/out" 2>&1; echo $?; }

row() {
  local id="$1" file="$2" old="$3" new="$4" want="$5" desc="$6" pristine
  case "$file" in
    "$GUARD") pristine="$P_GUARD" ;; "$CI_YML") pristine="$P_CI" ;; "$REL_YML") pristine="$P_REL" ;;
    *) fail "$id — unknown file"; return ;;
  esac
  if ! mutate "$file" "$old" "$new" 2>"$WORK/muterr"; then
    fail "$id — mutation could not be applied: $(cat "$WORK/muterr"). This row measured NOTHING."
    cp "$pristine" "$file"; return
  fi
  if cmp -s "$pristine" "$file"; then
    fail "$id — mutation DID NOT LAND; a verdict now would be the baseline, not the mutant."
    cp "$pristine" "$file"; return
  fi
  local rc; rc=$(guard_rc)
  cp "$pristine" "$file"
  cmp -s "$pristine" "$file" || { echo "FATAL: restore of $file did not take." >&2; exit 2; }
  if [[ "$want" == "RED" ]]; then
    if (( rc != 0 )); then pass "$id — guard went RED as required ($desc)"
    else fail "$id — SURVIVOR: guard stayed GREEN under '$desc'. Fixture-inadequate or equivalent — decide which."; fi
  else
    if (( rc == 0 )); then pass "$id — guard stayed GREEN as required ($desc)"
    else fail "$id — guard went RED on a must-PASS input ($desc): $(tail -3 "$WORK/out" | tr '\n' ' ')"; fi
  fi
}

_control=$(guard_rc)
if (( _control == 0 )); then
  pass "CONTROL — the unmutated tree is GREEN, so every row below scores a real mutation"
else
  echo "FATAL: CONTROL IS RED (exit $_control). This battery is VOID, not failing." >&2
  tail -20 "$WORK/out" >&2; exit 2
fi

# Row 1: remove test-scripts' ceiling. Absence must read as the 360 default, not as zero.
row "ROW1" "$CI_YML" \
  '    timeout-minutes: 30
    # No setup-node' \
  '    # No setup-node' \
  RED "test-scripts declares no ceiling (must read as GitHub's 360 default)"

# Row 2: make the graph walk return an empty job set — a guard reporting 0 checked is vacuous.
row "ROW2" "$CI_YML" \
  '    needs: [test-webplat, test-bun, test-scripts]' \
  '    needs: []' \
  RED "test's needs-closure walk returns an empty set"

# Row 3: add a SECOND job to the closure after a compliant first, with no ceiling.
row "ROW3" "$CI_YML" \
  '    needs: [test-webplat, test-bun, test-scripts]' \
  '    needs: [test-webplat, test-bun, test-scripts, lockfile-sync]' \
  RED "a job joins the closure carrying no declared ceiling"

# Row 4: raise a closure ceiling past what the gate can absorb.
row "ROW4" "$CI_YML" \
  '    timeout-minutes: 30
    # No setup-node' \
  '    timeout-minutes: 55
    # No setup-node' \
  RED "a closure ceiling is raised so the critical path exceeds CEILING_S/60"

# Row 5: lower CEILING_S without lowering the closure ceilings.
row "ROW5" "$REL_YML" \
  'CEILING_S: "3600"' \
  'CEILING_S: "1800"' \
  RED "CEILING_S is lowered while CI's declared budget stays put"

# Row 6: remove a needs edge — the job still gates the deploy but leaves the derived set.
row "ROW6" "$CI_YML" \
  '    needs: [test-webplat, test-bun, test-scripts]' \
  '    needs: [test-webplat, test-bun]' \
  RED "a job leaves the derived closure while still gating the deploy (pinned closure must catch it)"

# Row 7: replace the resolved CEILING_S read with a hardcoded literal that drifts.
row "ROW7" "$GUARD" \
  'CEILING_S=$(awk '"'"'/^[[:space:]]*CEILING_S:[[:space:]]*"[0-9]+"/ {' \
  'CEILING_S=99999; _unused_awk=$(awk '"'"'/^[[:space:]]*CEILING_S:[[:space:]]*"[0-9]+"/ {' \
  RED "the guard hardcodes CEILING_S instead of resolving it (value no longer occurs in the workflow)"

# HARNESS: neuter the budget comparison itself; its positive control must catch it.
row "HARNESS" "$GUARD" \
  '  (( ceiling_min > 0 && max_shard + own <= ceiling_min ))' \
  '  return 0  # mutated: everything fits' \
  RED "budget_fits is neutered to always succeed (must be caught by its positive control)"

# MUST-PASS: raising a closure ceiling AND CEILING_S together, by DIFFERENT amounts, is legal.
# The contract permits any critical path under the ceiling, not one specific set of values.
if mutate "$CI_YML" '    timeout-minutes: 30
    # No setup-node' '    timeout-minutes: 44
    # No setup-node' 2>/dev/null && mutate "$REL_YML" 'CEILING_S: "3600"' 'CEILING_S: "4200"' 2>/dev/null; then
  _mp=$(guard_rc)
  cp "$P_CI" "$CI_YML"; cp "$P_REL" "$REL_YML"
  if (( _mp == 0 )); then
    pass "MUSTPASS — raising a closure ceiling (30->44) and CEILING_S (3600->4200) together by different amounts stays GREEN"
  else
    fail "MUSTPASS — the guard went RED on a legal coordinated raise; it pins specific values rather than the bound: $(tail -3 "$WORK/out" | tr '\n' ' ')"
  fi
else
  fail "MUSTPASS — could not apply the coordinated-raise mutation."
  cp "$P_CI" "$CI_YML"; cp "$P_REL" "$REL_YML"
fi

MIN_ROWS=9
TOTAL=$(( PASS + FAIL ))
if (( TOTAL < MIN_ROWS )); then
  printf 'FAIL: assertion floor — %d rows executed, expected at least %d.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi

echo ""
echo "ci-budget-bounded-mutations.sh: $TOTAL rows, $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then exit 1; fi
echo "All tests passed"
