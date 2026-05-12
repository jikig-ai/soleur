#!/usr/bin/env bash
# Tests for scripts/lint-agents-enforcement-tags.py --check-anchors flag.
#
# Covers Phase 4 of the AGENTS.md pre-commit-hook plan (issue #3684):
#   T1: tag with single-skill resolved anchor → exit 0
#   T2: tag with multi-skill comma-separated anchors all resolved → exit 0
#   T3: tag with one dangling segment → exit 1 + descriptive error naming the
#       segment
#   T4: dangling segment listed in scripts/agents-anchor-ignore.txt → exit 0
#       (allowlist consulted)
#   T5: backward-compat — invocation WITHOUT --check-anchors keeps existing
#       behavior (file existence check only)
#
# Isolation: each test builds a tempdir with synthetic AGENTS.md and a
# fake plugins/soleur/skills/<name>/SKILL.md tree, then runs the SUT
# against the tempdir.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-agents-enforcement-tags.py"

PASS=0
FAIL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  needle:   $needle"
    echo "  haystack: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# Build a tempdir with a fake repo layout:
#   AGENTS.md (controlled body)
#   plugins/soleur/skills/<skill>/SKILL.md for each given skill
make_fixture() {
  local agents_body="$1"
  shift
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/plugins/soleur/skills"
  printf '%s' "$agents_body" > "$tmpdir/AGENTS.md"
  while [[ "$#" -gt 0 ]]; do
    local skill="$1" body="$2"
    shift 2
    mkdir -p "$tmpdir/plugins/soleur/skills/$skill"
    printf '%s' "$body" > "$tmpdir/plugins/soleur/skills/$skill/SKILL.md"
  done
  echo "$tmpdir"
}

echo
echo "=== T1: single-skill resolved anchor → exit 0 ==="
TMP=$(make_fixture \
  "- rule [id: cq-foo] [skill-enforced: plan Phase 1.4]" \
  plan "# plan
## Phase 1.4 something")
OUT=$(cd "$TMP" && python3 "$SUT" --check-anchors AGENTS.md 2>&1); RC=$?
assert_eq "T1.exit_code" "0" "$RC"
rm -rf "$TMP"

echo
echo "=== T2: multi-skill comma-separated all resolved → exit 0 ==="
TMP=$(make_fixture \
  "- rule [id: cq-foo] [skill-enforced: plan Phase 2.6, deepen-plan Phase 4.6, review user-impact-reviewer]" \
  plan "# plan
## Phase 2.6 User-Brand Impact" \
  deepen-plan "# deepen
## Phase 4.6 User-Brand Impact" \
  review "# review
mention user-impact-reviewer here")
OUT=$(cd "$TMP" && python3 "$SUT" --check-anchors AGENTS.md 2>&1); RC=$?
assert_eq "T2.exit_code" "0" "$RC"
rm -rf "$TMP"

echo
echo "=== T3: one dangling segment → exit 1 + named in error ==="
TMP=$(make_fixture \
  "- rule [id: cq-foo] [skill-enforced: plan Phase 2.6, deepen-plan Phase 99.99]" \
  plan "# plan
## Phase 2.6 something" \
  deepen-plan "# deepen
## Phase 4.6 nothing matching the bogus tag")
OUT=$(cd "$TMP" && python3 "$SUT" --check-anchors AGENTS.md 2>&1); RC=$?
assert_eq "T3.exit_code" "1" "$RC"
assert_contains "T3.error_names_skill" "deepen-plan" "$OUT"
assert_contains "T3.error_names_anchor" "Phase 99.99" "$OUT"
rm -rf "$TMP"

echo
echo "=== T4: allowlist entry skips grep check → exit 0 ==="
TMP=$(make_fixture \
  "- rule [id: cq-foo] [skill-enforced: plan Phase 99.99]" \
  plan "# plan
nothing matching here")
mkdir -p "$TMP/scripts"
{
  echo "# allowlist test fixture"
  echo "plan Phase 99.99"
} > "$TMP/scripts/agents-anchor-ignore.txt"
OUT=$(cd "$TMP" && python3 "$SUT" --check-anchors AGENTS.md 2>&1); RC=$?
assert_eq "T4.exit_code" "0" "$RC"
rm -rf "$TMP"

echo
echo "=== T5: backward-compat — no --check-anchors keeps existing behavior ==="
TMP=$(make_fixture \
  "- rule [id: cq-foo] [skill-enforced: plan Phase 99.99]" \
  plan "# plan
nothing matching here")
OUT=$(cd "$TMP" && python3 "$SUT" AGENTS.md 2>&1); RC=$?
# Without --check-anchors, the dangling Phase 99.99 anchor is NOT a failure
# (existing behavior only checks the skill directory exists).
assert_eq "T5.exit_code" "0" "$RC"
rm -rf "$TMP"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "ALL TESTS PASSED"
