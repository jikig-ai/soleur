#!/usr/bin/env bash
# scripts-shard-runtime-coverage.test.sh — every runtime a scripts-shard suite
# invokes must actually be installed in the `test-scripts` CI job.
#
# WHY THIS EXISTS (#7332). `ci.yml`'s `test-scripts` job carried a comment asserting
# "No `bun` in the scripts group", justified by
# `grep -l '^bun ' plugins/soleur/test/*.test.sh` returning zero matches. That
# predicate is anchored to column 1, so it was structurally unable to see a `bun`
# call inside a function body — which is exactly what
# `c4-from-components.test.sh:60` added (`run_producer() { bun "$PRODUCER" … }`).
#
# The result: a guard that restated the condition it protected, kept reporting
# "clean", and let a suite into a shard with no `bun`. It failed with
# `bun: command not found` — and because the failure was inside the suite rather
# than at collection, its actual render arms never ran while the shard went red for
# a reason unrelated to the code under test.
#
# So the lesson is not "add setup-bun" (already done). It is that a detection
# predicate anchored more narrowly than the thing it detects fails SILENTLY and in
# the reassuring direction. This asserts the invariant directly instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

echo "=== scripts-shard runtime coverage ==="
echo ""

assert_file_exists "$CI_YML" "ci.yml exists"
if [[ "$FAIL" -gt 0 ]]; then print_results; fi

# The scripts shard's own job block. Bounded by the next top-level job key so a
# later job's steps cannot leak in and satisfy an assertion about this one.
job_block() {
  awk '/^  test-scripts:/{f=1} f&&/^  [a-z][a-z0-9-]*:$/&&!/^  test-scripts:/{exit} f' "$CI_YML"
}
BLOCK="$(job_block)"

if [[ -z "$BLOCK" ]]; then
  echo "  FAIL: could not extract the test-scripts job block from ci.yml"
  FAIL=$((FAIL + 1))
  print_results
fi

# Non-vacuity: the extraction must have found a real job, not an empty string that
# makes every `grep -q` below trivially false and every negative assertion pass.
BLOCK_LINES="$(printf '%s\n' "$BLOCK" | wc -l)"
if [[ "$BLOCK_LINES" -lt 10 ]]; then
  echo "  FAIL: test-scripts block is only $BLOCK_LINES lines — extraction is wrong"
  FAIL=$((FAIL + 1))
  print_results
fi
echo "  PASS: extracted the test-scripts job block ($BLOCK_LINES lines)"
PASS=$((PASS + 1))

# Which suites does the scripts shard actually run? Mirror test-all.sh's glob.
# NOT anchored to column 1 — that anchoring is the defect this file exists to stop.
RUNTIME_RE='(^|[^[:alnum:]_./-])'

check_runtime() {
  local runtime="$1" setup_marker="$2"
  local users=()
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # Strip comments before searching so a suite that merely DISCUSSES a runtime
    # is not counted as invoking it (the comment-vs-code collision class).
    if sed 's/#.*$//' "$f" | grep -qE "${RUNTIME_RE}${runtime}[[:space:]]"; then
      users+=("$(basename "$f")")
    fi
  done < <(ls "$REPO_ROOT"/plugins/soleur/test/*.test.sh 2>/dev/null)

  if [[ ${#users[@]} -eq 0 ]]; then
    echo "  SKIP: no scripts-shard suite invokes '$runtime'"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if printf '%s\n' "$BLOCK" | grep -qE "$setup_marker"; then
    echo "  PASS: '$runtime' is invoked by ${#users[@]} suite(s) (${users[*]}) and installed in test-scripts"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${#users[@]} scripts-shard suite(s) invoke '$runtime' but test-scripts does not install it"
    echo "    suites: ${users[*]}"
    echo "    expected a step matching: $setup_marker"
    FAIL=$((FAIL + 1))
  fi
}

check_runtime "bun" 'oven-sh/setup-bun'
check_runtime "likec4" 'npm install -g likec4@'
check_runtime "gitleaks" 'gitleaks'

# Mutation-proof the central assertion: with the setup step removed from the block,
# the bun check MUST fail. A guard nobody has seen red is not a guard.
MUTATED="$(printf '%s\n' "$BLOCK" | grep -v 'oven-sh/setup-bun')"
if printf '%s\n' "$MUTATED" | grep -qE 'oven-sh/setup-bun'; then
  echo "  FAIL: self-check — could not remove the setup-bun line to prove non-vacuity"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: self-check — the setup-bun assertion is reading a real line (removing it changes the block)"
  PASS=$((PASS + 1))
fi

print_results
