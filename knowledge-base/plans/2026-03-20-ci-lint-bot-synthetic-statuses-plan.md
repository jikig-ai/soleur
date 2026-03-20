---
title: "ci: lint check for bot workflows missing synthetic statuses"
type: feat
date: 2026-03-20
---

# ci: lint check for bot workflows missing synthetic statuses

## Overview

Add an automated CI check that enforces the convention: every `scheduled-*.yml` workflow file containing `gh pr create` must also contain both `context=cla-check` and `context=test` synthetic status posts. This prevents bot PRs from being permanently blocked by the CI Required ruleset when they use `[skip ci]`.

## Problem Statement / Motivation

PR #827 (closing #826) added synthetic `test` and `cla-check` statuses to all 9 bot workflows that create PRs with `[skip ci]`. Without these synthetic statuses, the CI Required ruleset blocks auto-merge indefinitely because the real CI never runs.

Currently this is a convention enforced only by code review. When a new scheduled workflow is added (or an existing one gains a `gh pr create` step), there is no automated guardrail to ensure the synthetic statuses are included. A single missed workflow would result in permanently-blocked bot PRs that require manual intervention.

## Proposed Solution

Add a standalone lint script (`scripts/lint-bot-synthetic-statuses.sh`) invoked as a new job in `.github/workflows/ci.yml`. The script:

1. Scans all `.github/workflows/scheduled-*.yml` files
2. For each file containing `gh pr create`, verifies it also contains `context=cla-check` and `context=test`
3. Exits non-zero with a clear error message listing any non-compliant files

### Why a standalone script + CI job (not inline in ci.yml)

- **Testable**: The script can be tested locally and in bash test suites (consistent with `plugins/soleur/test/*.test.sh` pattern)
- **Reusable**: Can be run as a pre-commit hook or by agents during `soleur:work`
- **Clear separation**: CI job is a thin invocation; logic lives in the script

### Why not a standalone workflow file

The check validates repository content (not runtime behavior), so it fits naturally as a CI job alongside `test`. A standalone workflow would add scheduling/trigger complexity with no benefit.

## Technical Considerations

### Edge Cases

1. **`claude-code-action` prompt blocks**: Some workflows (e.g., `scheduled-content-generator.yml`) embed `gh pr create` and synthetic status commands inside a `prompt:` field for `claude-code-action`, not as direct shell commands. The grep-based lint must still match these because the strings are present in the YAML file regardless of indentation context. Simple `grep -q` on the file content handles this correctly.

2. **Workflows using `claude-code-action` without explicit `gh pr create`**: Workflows like `scheduled-bug-fixer.yml` and `scheduled-ship-merge.yml` delegate PR creation to the claude-code-action agent, which handles its own PR creation and does NOT use `[skip ci]`. These workflows correctly do NOT contain `gh pr create` in the file, so the lint naturally skips them. No special handling needed.

3. **Workflows without PR creation**: 5 scheduled workflows (`scheduled-daily-triage.yml`, `scheduled-linkedin-token-check.yml`, `scheduled-plausible-goals.yml`, `scheduled-bug-fixer.yml`, `scheduled-ship-merge.yml`) do not contain `gh pr create` and should be silently skipped.

4. **Future required statuses**: If additional required status checks are added to the ruleset beyond `test` and `cla-check`, the lint script should be easy to extend (array of required contexts).

5. **False positives from comments**: A `# gh pr create` comment would trigger the lint. This is acceptable -- if a workflow has a commented-out `gh pr create`, it should still be flagged for attention. The convention is to include synthetic statuses whenever PR creation is part of the workflow's design.

### Performance

The lint runs `grep` on ~14 small YAML files (<300 lines each). Execution time is negligible (<1 second).

## Acceptance Criteria

- [ ] New script `scripts/lint-bot-synthetic-statuses.sh` exists and is executable
- [ ] Script scans all `.github/workflows/scheduled-*.yml` files
- [ ] Script passes when every file with `gh pr create` also has both `context=cla-check` and `context=test`
- [ ] Script fails with clear error listing non-compliant files when a synthetic status is missing
- [ ] Script exits 0 when no `scheduled-*.yml` files contain `gh pr create` (no false failures)
- [ ] New `lint-bot-statuses` job added to `.github/workflows/ci.yml`
- [ ] Job runs on `ubuntu-latest`, checks out repo, and executes the lint script
- [ ] Existing CI `test` job is unaffected
- [ ] Bash test in `test/lint-bot-synthetic-statuses.test.sh` covers: passing case, missing `context=test`, missing `context=cla-check`, missing both, file without `gh pr create` (skipped)

## Test Scenarios

- Given all 9 scheduled workflows have `gh pr create` and both synthetic statuses, when the lint runs, then it exits 0 with a summary of files checked
- Given a new `scheduled-foo.yml` with `gh pr create` but no `context=test`, when the lint runs, then it exits 1 and names `scheduled-foo.yml` and the missing context
- Given a new `scheduled-bar.yml` with `gh pr create` but no `context=cla-check`, when the lint runs, then it exits 1 and names `scheduled-bar.yml` and the missing context
- Given a `scheduled-*.yml` file without `gh pr create`, when the lint runs, then it skips the file silently
- Given zero `scheduled-*.yml` files (unlikely but defensive), when the lint runs, then it exits 0

## MVP

### scripts/lint-bot-synthetic-statuses.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Lint: every scheduled-*.yml with "gh pr create" must also have
# synthetic statuses for all required CI checks.
# Refs: #826, #827, #842

REQUIRED_CONTEXTS=("cla-check" "test")
WORKFLOW_DIR=".github/workflows"
PATTERN="scheduled-*.yml"

failures=0

for file in "$WORKFLOW_DIR"/$PATTERN; do
  [[ -f "$file" ]] || continue

  # Only check files that create PRs
  grep -q "gh pr create" "$file" || continue

  for ctx in "${REQUIRED_CONTEXTS[@]}"; do
    if ! grep -q "context=$ctx" "$file"; then
      echo "FAIL: $file contains 'gh pr create' but is missing 'context=$ctx'"
      failures=$((failures + 1))
    fi
  done
done

if [[ "$failures" -gt 0 ]]; then
  echo ""
  echo "$failures missing synthetic status(es) found."
  echo "Bot PRs with [skip ci] need synthetic statuses for all required checks."
  echo "See: #826, #827"
  exit 1
fi

echo "All scheduled bot workflows have required synthetic statuses."
exit 0
```

### .github/workflows/ci.yml (addition)

```yaml
  lint-bot-statuses:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      - name: Lint bot synthetic statuses
        run: bash scripts/lint-bot-synthetic-statuses.sh
```

### test/lint-bot-synthetic-statuses.test.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script lives at repo-root/scripts/lint-bot-synthetic-statuses.sh
LINT_SCRIPT="$SCRIPT_DIR/../scripts/lint-bot-synthetic-statuses.sh"

PASS=0
FAIL=0

assert_exit() {
  local expected="$1" actual="$2" msg="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (expected exit $expected, got $actual)"; FAIL=$((FAIL + 1))
  fi
}

echo "=== lint-bot-synthetic-statuses Tests ==="

# Setup temp workflow dir
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
WF="$TMPDIR/.github/workflows"
mkdir -p "$WF"

# Test 1: Passing -- file has gh pr create + both contexts
echo "Test 1: File with gh pr create and both contexts passes"
cat > "$WF/scheduled-good.yml" << 'EOF'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f context=cla-check
          gh api repos/foo/statuses/$SHA -f context=test
          gh pr create --title "test"
EOF
(cd "$TMPDIR" && bash "$LINT_SCRIPT") >/dev/null 2>&1; assert_exit 0 $? "passes with both contexts"

# Test 2: Missing context=test
echo "Test 2: File missing context=test fails"
cat > "$WF/scheduled-bad.yml" << 'EOF'
name: Bad
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f context=cla-check
          gh pr create --title "test"
EOF
(cd "$TMPDIR" && bash "$LINT_SCRIPT") >/dev/null 2>&1; assert_exit 1 $? "fails with missing context=test"

# ... additional test cases for missing cla-check, missing both, file without gh pr create

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
```

## Dependencies & Risks

- **No external dependencies**: Script uses only `bash`, `grep`, and file globs
- **Risk: new required statuses**: If the CI Required ruleset adds new required checks, the `REQUIRED_CONTEXTS` array must be updated manually. Mitigation: the script can be extended to read required contexts from a config file or the ruleset API, but that is out of scope for MVP
- **Risk: workflow naming convention changes**: If bot workflows stop using the `scheduled-*` prefix, the glob must be updated. This is unlikely given established convention

## References & Research

- Issue #842: this issue
- PR #827: added synthetic statuses to all 9 bot workflows
- Issue #826: CI Required ruleset design
- `scripts/create-ci-required-ruleset.sh`: script that creates the ruleset (pre-flight check pattern)
- `.github/workflows/ci.yml`: existing CI workflow (2 jobs: `test`)
- `plugins/soleur/test/test-helpers.sh`: shared bash test helpers
- `scripts/test-all.sh`: test runner that discovers bash tests
