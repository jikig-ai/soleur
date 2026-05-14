#!/usr/bin/env bash
# Test harness for plugins/soleur/skills/incident/scripts/redact-sentinel.sh
#
# Pattern mirrors plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh:
# - set -uo pipefail (NOT -e — single test failure must not abort the suite)
# - PASS/FAIL counter
# - trap-based cleanup
#
# Tests (RED before sentinel impl, GREEN after):
#   1. Negative-baseline: existing hand-redacted PIR exits 0
#   2. Positive-corpus: every regex class triggers ≥1 (exit non-zero)
#   3. Invalid arg: missing file / unreadable path → exit 2
#   4. Output format: lines match `at offset \d+: .{8}\*\*\*.{8}`
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../../.." && pwd)"

SENTINEL="${SKILL_DIR}/scripts/redact-sentinel.sh"
POSITIVE_CORPUS="${SCRIPT_DIR}/fixtures/positive-corpus.md"
NEGATIVE_BASELINE="${REPO_ROOT}/knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md"

PASS=0
FAIL=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "PASS: ${label} (exit=${actual})"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (expected exit=${expected}, got ${actual})"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE "${pattern}" "${file}"; then
    echo "PASS: ${label} (pattern matched in ${file##*/})"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (pattern '${pattern}' not found in ${file##*/})"
    FAIL=$((FAIL + 1))
  fi
}

# Test 1 — negative-baseline
out="${TMP_DIR}/test1.out"
bash "${SENTINEL}" "${NEGATIVE_BASELINE}" >"${out}" 2>&1
assert_exit "Test 1: negative-baseline exits 0 on hand-redacted PIR" 0 $?

# Test 2 — positive-corpus
out="${TMP_DIR}/test2.out"
bash "${SENTINEL}" "${POSITIVE_CORPUS}" >"${out}" 2>&1
rc=$?
assert_exit "Test 2: positive-corpus exits non-zero" 1 "${rc}"

# Every regex class triggers ≥1 (look for the matched-pattern label in output)
for class in JWT email UUID stripe_key stripe_whsec stripe_acct stripe_cust_pi_seti_sub_in IPv4 env_var; do
  assert_grep "Test 2.${class}: pattern '${class}' present" "matched pattern ${class}" "${out}"
done

# Test 3 — invalid arg
out="${TMP_DIR}/test3.out"
bash "${SENTINEL}" /nonexistent/path/to/file.md >"${out}" 2>&1
assert_exit "Test 3: nonexistent file exits 2" 2 $?

bash "${SENTINEL}" >"${out}" 2>&1
assert_exit "Test 3: missing arg exits 2" 2 $?

# Test 4 — output format
out="${TMP_DIR}/test4.out"
bash "${SENTINEL}" "${POSITIVE_CORPUS}" >"${out}" 2>&1 || true
assert_grep "Test 4: output format 'at offset N: 8-prefix***8-suffix matched pattern X'" \
  'at offset [0-9]+: .{8}\*\*\*.{8} matched pattern [A-Za-z_]+' "${out}"

echo
echo "Total: ${PASS} pass, ${FAIL} fail"
[[ "${FAIL}" -eq 0 ]]
