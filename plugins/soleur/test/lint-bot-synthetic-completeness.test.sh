#!/usr/bin/env bash

# Tests for scripts/lint-bot-synthetic-completeness.sh
# Run: bash plugins/soleur/test/lint-bot-synthetic-completeness.test.sh
#
# Covers both regression (scheduled-*.yml) AND the widened content-based
# enumeration introduced for #3548 (R15 follow-up D5): the lint must now
# detect any bot PR-creator workflow regardless of filename prefix, while
# continuing to exempt composite-action consumers and the
# skill-security-scan-pr-trailer CI workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# Resolve lint script relative to repo root (3 levels up from plugins/soleur/test/)
REPO_ROOT="$SCRIPT_DIR/../../.."
LINT_SCRIPT="$REPO_ROOT/scripts/lint-bot-synthetic-completeness.sh"

echo "=== lint-bot-synthetic-completeness Tests ==="
echo ""

# --- Helpers ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

setup_wf_dir() {
  local dir="$TMPDIR_BASE/$1/.github/workflows"
  mkdir -p "$dir"
  echo "$dir"
}

setup_config_file() {
  # Minimal required-checks fixture. Multi-word check name exercises the
  # quoted-context path in the lint regex.
  local path="$1"
  cat > "$path" << 'CONF'
test
dependency-review
cla-check
skill-security-scan PR gate
CONF
}

# A canonical inline synthetic-posting fragment that satisfies all 4 required
# checks in the fixture config. Mirrors scheduled-content-publisher.yml's
# multi-line `gh api .../check-runs` shape.
SYNTHETIC_POSTS=$(cat << 'YAML'
      - name: Post synthetic check-runs
        run: |
          set -euo pipefail
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=test \
            -f head_sha="$SHA" \
            -f status=completed \
            -f conclusion=success
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=dependency-review \
            -f head_sha="$SHA" \
            -f status=completed \
            -f conclusion=success
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=cla-check \
            -f head_sha="$SHA" \
            -f status=completed \
            -f conclusion=success
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name="skill-security-scan PR gate" \
            -f head_sha="$SHA" \
            -f status=completed \
            -f conclusion=success
YAML
)

# --- Tests ---

# Test (a): scheduled-*.yml with full synthetics passes (regression).
echo "Test (a): scheduled-foo.yml with full synthetics passes"
WF=$(setup_wf_dir "a")
CONF="$TMPDIR_BASE/a/required-checks.txt"
setup_config_file "$CONF"
cat > "$WF/scheduled-foo.yml" << YAML
name: Foo
on: schedule
jobs:
  run:
    steps:
      - name: Create PR
        run: |
          gh pr create --title "test" --base main
$SYNTHETIC_POSTS
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "(a) exits 0 for scheduled-* with full synthetics"
assert_contains "$output" "ok:" "(a) reports passing file"
echo ""

# Test (b): scheduled-*.yml missing a required check fails (regression).
echo "Test (b): scheduled-foo.yml missing a required check fails"
WF=$(setup_wf_dir "b")
CONF="$TMPDIR_BASE/b/required-checks.txt"
setup_config_file "$CONF"
cat > "$WF/scheduled-foo.yml" << 'YAML'
name: Foo
on: schedule
jobs:
  run:
    steps:
      - name: Create PR
        run: |
          gh pr create --title "test"
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=test -f head_sha="$SHA"
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "(b) exits 1 when required check missing"
assert_contains "$output" "FAIL:" "(b) reports the failing file"
assert_contains "$output" "dependency-review" "(b) names a missing synthetic"
echo ""

# Test (c): non-scheduled-prefixed file with full synthetics passes (NEW).
echo "Test (c): monthly-foo.yml with full synthetics passes (widened scope)"
WF=$(setup_wf_dir "c")
CONF="$TMPDIR_BASE/c/required-checks.txt"
setup_config_file "$CONF"
cat > "$WF/monthly-foo.yml" << YAML
name: MonthlyFoo
on: schedule
jobs:
  run:
    steps:
      - name: Create PR
        run: |
          gh pr create --title "test"
$SYNTHETIC_POSTS
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "(c) exits 0 for non-scheduled-prefixed file with full synthetics"
assert_contains "$output" "monthly-foo.yml" "(c) lint sees the non-scheduled file"
assert_contains "$output" "ok:" "(c) reports it as passing"
echo ""

# Test (d): non-scheduled-prefixed file missing a required check fails (NEW).
echo "Test (d): release-foo.yml missing a required check fails (widened scope)"
WF=$(setup_wf_dir "d")
CONF="$TMPDIR_BASE/d/required-checks.txt"
setup_config_file "$CONF"
cat > "$WF/release-foo.yml" << 'YAML'
name: ReleaseFoo
on: schedule
jobs:
  run:
    steps:
      - name: Create PR
        run: |
          gh pr create --title "test"
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=test -f head_sha="$SHA"
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "(d) exits 1 when widened scope catches a missing-check file"
assert_contains "$output" "release-foo.yml" "(d) names the failing non-scheduled file"
echo ""

# Test (e): skill-security-scan-pr-trailer.yml is excluded even with full pattern (NEW).
echo "Test (e): skill-security-scan-pr-trailer.yml is excluded by name"
WF=$(setup_wf_dir "e")
CONF="$TMPDIR_BASE/e/required-checks.txt"
setup_config_file "$CONF"
# Looks like a bot workflow (has gh pr create AND check-runs) but must be skipped.
cat > "$WF/skill-security-scan-pr-trailer.yml" << 'YAML'
name: skill-security-scan PR trailer
on: pull_request_target
jobs:
  run:
    steps:
      - run: |
          gh pr create --title "test"
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=test
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "(e) exits 0 (trailer is excluded, not linted)"
# Must NOT appear in output as either ok/FAIL/skip line.
if [[ "$output" == *"skill-security-scan-pr-trailer.yml"* ]]; then
  echo "  FAIL: (e) skill-security-scan-pr-trailer.yml leaked into output"
  echo "    output: $output"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: (e) trailer file is silently excluded"
  PASS=$((PASS + 1))
fi
echo ""

# Test (f): composite-action consumer (header-comment bare "check-runs") is excluded (NEW).
# Locks in the predicate refinement: we use `gh api .../check-runs` inside a
# run: block, not a bare substring grep that would false-positive on header
# comments mentioning "check-runs".
echo "Test (f): composite-action-only consumer is excluded (bare-substring guard)"
WF=$(setup_wf_dir "f")
CONF="$TMPDIR_BASE/f/required-checks.txt"
setup_config_file "$CONF"
cat > "$WF/scheduled-composite-consumer.yml" << 'YAML'
# Composite consumer: synthetic check-runs are posted by the shared action,
# not by this workflow. The header mentions "check-runs" for operator
# context only — the bare token must NOT trigger the lint.
name: CompositeConsumer
on: schedule
jobs:
  run:
    steps:
      - name: Create PR via composite
        uses: ./.github/actions/bot-pr-with-synthetic-checks
        with:
          title: "test"
      - run: |
          gh pr create --title "fallback"
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "(f) exits 0 — composite-consumer is excluded"
# The widened lint must not enumerate a workflow whose only check-runs
# reference is in a header comment.
if [[ "$output" == *"FAIL:"*"scheduled-composite-consumer.yml"* ]]; then
  echo "  FAIL: (f) composite-consumer fixture was incorrectly flagged"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: (f) composite-consumer (bare 'check-runs' in comments) is exempt"
  PASS=$((PASS + 1))
fi
echo ""

# Test (g): prompt:-only gh pr create is skipped via App-token escape hatch.
echo "Test (g): prompt:-only gh pr create is skipped (App token escape hatch)"
WF=$(setup_wf_dir "g")
CONF="$TMPDIR_BASE/g/required-checks.txt"
setup_config_file "$CONF"
cat > "$WF/scheduled-prompt-only.yml" << 'YAML'
name: PromptOnly
on: schedule
jobs:
  audit:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            Run gh pr create to file a PR.
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "(g) exits 0 for prompt:-only PR creator"
assert_contains "$output" "skip:" "(g) reports the file as skipped"
echo ""

# Test (h): pr-auto-close-scanner.yml shape — gh pr create only in file-scope
# comments — must be skipped under widened glob. Locks in has_shell_pr_create
# correctness for non-scheduled-prefixed files.
echo "Test (h): comment-only gh pr create (pr-auto-close-scanner.yml shape) is skipped"
WF=$(setup_wf_dir "h")
CONF="$TMPDIR_BASE/h/required-checks.txt"
setup_config_file "$CONF"
cat > "$WF/pr-auto-close-scanner.yml" << 'YAML'
# Scanner workflow: this file scans PR bodies for auto-close keywords
# accidentally landed by gh pr create / gh pr edit. The `gh pr create`
# tokens above appear only in this YAML-level header comment — no shell
# block in this file ever runs gh pr create.
name: pr-auto-close-scanner
on: pull_request
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - name: Scan
        run: |
          echo "scanning PR body for auto-close keywords"
YAML
output=$(WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" CONFIG_FILE="$CONF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "(h) exits 0 — comment-only gh pr create is skipped"
# Must not be enumerated as ok/FAIL (skip-via-has-shell-pr-create-false is fine,
# but the file does have `gh pr create` in a comment which DOES trigger the
# top-level `grep -q`. With has_shell_pr_create returning false it should
# either be skipped or fall through silently — never flagged FAIL.
if [[ "$output" == *"FAIL:"*"pr-auto-close-scanner.yml"* ]]; then
  echo "  FAIL: (h) pr-auto-close-scanner.yml was incorrectly flagged"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: (h) comment-only gh pr create not flagged"
  PASS=$((PASS + 1))
fi
echo ""

print_results
