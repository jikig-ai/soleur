#!/usr/bin/env bash

# Tests for scripts/lint-bot-synthetic-statuses.sh
# Run: bash plugins/soleur/test/lint-bot-synthetic-statuses.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Resolve lint script relative to repo root (3 levels up from plugins/soleur/test/)
REPO_ROOT="$SCRIPT_DIR/../../.."
LINT_SCRIPT="$REPO_ROOT/scripts/lint-bot-synthetic-statuses.sh"

echo "=== lint-bot-synthetic-statuses Tests ==="
echo ""

# --- Helpers ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

setup_wf_dir() {
  local dir="$TMPDIR_BASE/$1/.github/workflows"
  mkdir -p "$dir"
  echo "$dir"
}

# --- Tests ---

# Test 1: File with gh pr create and no [skip ci] passes
echo "Test 1: File with gh pr create and no [skip ci] passes"
WF=$(setup_wf_dir "test1")
cat > "$WF/scheduled-good.yml" << 'YAML'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit"
          gh pr create --title "test" --base main
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no [skip ci] present"
assert_contains "$output" "ok:" "reports passing file"
assert_contains "$output" "All 1 bot workflow(s)" "reports summary"
echo ""

# Test 2: File with [skip ci] in commit message fails
echo "Test 2: File with [skip ci] in commit message fails"
WF=$(setup_wf_dir "test2")
cat > "$WF/scheduled-skip-ci.yml" << 'YAML'
name: SkipCI
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when [skip ci] present"
assert_contains "$output" "[skip ci]" "reports [skip ci] as the problem"
echo ""

# Test 3: File with [skip ci] but no gh pr create is skipped
echo "Test 3: File with [skip ci] but no gh pr create is skipped"
WF=$(setup_wf_dir "test3")
cat > "$WF/scheduled-no-pr.yml" << 'YAML'
name: NoPR
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "ci: update [skip ci]"
          echo "no PR creation"
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no gh pr create present"
echo ""

# Test 4: File without gh pr create is skipped
echo "Test 4: File without gh pr create is skipped"
WF=$(setup_wf_dir "test4")
cat > "$WF/scheduled-no-pr.yml" << 'YAML'
name: NoPR
on: schedule
jobs:
  run:
    steps:
      - run: echo "no PR creation here"
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no gh pr create present"
echo ""

# Test 5: Empty directory (no scheduled-*.yml files) passes
echo "Test 5: Empty workflow directory passes"
WF=$(setup_wf_dir "test5")
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no scheduled-*.yml files exist"
echo ""

# Test 6: Multi-file directory aggregates failures correctly
echo "Test 6: Multi-file directory aggregates failures correctly"
WF=$(setup_wf_dir "test6")
cat > "$WF/scheduled-good.yml" << 'YAML'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit"
          gh pr create --title "test"
YAML
cat > "$WF/scheduled-bad.yml" << 'YAML'
name: Bad
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when one file has [skip ci] in multi-file directory"
assert_contains "$output" "ok:" "reports passing file"
assert_contains "$output" "scheduled-bad.yml" "names the failing file"
echo ""

# Test 7: Multiple [skip ci] files reports correct count
echo "Test 7: Multiple [skip ci] files reports correct count"
WF=$(setup_wf_dir "test7")
cat > "$WF/scheduled-bad1.yml" << 'YAML'
name: Bad1
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: audit [skip ci]"
          gh pr create --title "test"
YAML
cat > "$WF/scheduled-bad2.yml" << 'YAML'
name: Bad2
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "ci: update [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when multiple files have [skip ci]"
assert_contains "$output" "2 workflow(s)" "reports correct failure count"
echo ""

# Test 8: Non-scheduled-prefixed file with gh pr create and [skip ci] fails (#3548).
# Locks in the widened content-based enumeration: bot workflows whose
# filename does not start with `scheduled-` must still be caught.
echo "Test 8: monthly-foo.yml with [skip ci] fails (widened scope)"
WF=$(setup_wf_dir "test8")
cat > "$WF/monthly-foo.yml" << 'YAML'
name: MonthlyFoo
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "ops: monthly audit [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 for non-scheduled-prefixed file with [skip ci]"
assert_contains "$output" "monthly-foo.yml" "names the non-scheduled file"
echo ""

# Test 9: skill-security-scan-pr-trailer.yml is excluded by name (#3548).
echo "Test 9: skill-security-scan-pr-trailer.yml is excluded"
WF=$(setup_wf_dir "test9")
cat > "$WF/skill-security-scan-pr-trailer.yml" << 'YAML'
name: skill-security-scan PR trailer
on: pull_request_target
jobs:
  run:
    steps:
      - run: |
          git commit -m "trailer [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 — trailer file is excluded from the lint"
if [[ "$output" == *"skill-security-scan-pr-trailer.yml"* ]]; then
  echo "  FAIL: trailer file leaked into output"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: trailer file silently excluded"
  PASS=$((PASS + 1))
fi
echo ""

# Test 10: trailer lookalike is NOT excluded (basename-exact-match).
echo "Test 10: evil-skill-security-scan-pr-trailer.yml is NOT excluded"
WF=$(setup_wf_dir "test10")
cat > "$WF/evil-skill-security-scan-pr-trailer.yml" << 'YAML'
name: Evil Spoof
on: schedule
jobs:
  spoof:
    steps:
      - run: |
          git commit -m "spoof [skip ci]"
          gh pr create --title "spoof"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 — spoofed lookalike is linted and fails on CI-skip directive"
assert_contains "$output" "evil-skill-security-scan-pr-trailer.yml" "lookalike named in output"
echo ""

# Test 11: alternate CI-skip directive variants are detected.
echo "Test 11: [ci skip] and [no ci] variants are detected"
for variant in "[ci skip]" "[no ci]" "[skip actions]" "[actions skip]" "***NO_CI***"; do
  WF=$(setup_wf_dir "test11-${variant// /_}")
  cat > "$WF/scheduled-skip-variant.yml" << YAML
name: SkipVariant
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "ops: change ${variant}"
          gh pr create --title "test"
YAML
  rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "exits 1 for variant '${variant}'"
done
echo ""

# Test 12: whitespace-flexible `gh pr create` matching (defense-in-depth).
echo "Test 12: 'gh  pr  create' (extra whitespace) is still in scope"
WF=$(setup_wf_dir "test12")
cat > "$WF/scheduled-extra-space.yml" << 'YAML'
name: ExtraSpace
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "test [skip ci]"
          gh  pr  create --title "extra space"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 — whitespace-flexible grep matches `gh  pr  create`"
echo ""

print_results
