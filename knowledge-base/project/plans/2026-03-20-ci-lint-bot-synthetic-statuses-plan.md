---
title: "ci: lint check for bot workflows missing synthetic statuses"
type: feat
date: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6 (Technical Considerations, Acceptance Criteria, Test Scenarios, MVP, Dependencies & Risks, References)
**Reviewers applied:** code-simplicity, test-design, security-sentinel, pattern-recognition, architecture-strategist

### Key Improvements

1. Fixed test file location: `plugins/soleur/test/*.test.sh` (not `test/`) -- consistent with `test-all.sh` bash test discovery loop
2. Made lint script testable via `WORKFLOW_DIR` environment variable override instead of hardcoded relative path
3. Added `checked` counter and verbose output for CI debuggability
4. Expanded incomplete test skeleton into 6 full test cases using project `test-helpers.sh` pattern
5. Added `nullglob` handling, repo-root resolution via `git rev-parse`, and `shopt` safety

### New Considerations Discovered

- `test-all.sh` only discovers bash tests in `plugins/soleur/test/*.test.sh` -- placing the test elsewhere means it silently never runs in CI
- The lint script uses a relative path (`.github/workflows`), which breaks when run from a subdirectory. The deepened version resolves the repo root via `git rev-parse --show-toplevel` for robustness
- The test in the original plan redefines `assert_exit` locally instead of using the shared `test-helpers.sh` pattern (`assert_eq`, `assert_contains`, `print_results`)

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

### Research Insights

**Repo-root resolution**: The script must work regardless of the caller's CWD. Use `git rev-parse --show-toplevel` to resolve the repo root, or accept `WORKFLOW_DIR` as an environment variable override (needed for tests that use temp directories). This follows the pattern in `scripts/test-all.sh` which assumes repo-root CWD via CI checkout.

**Nullglob safety**: Without `shopt -s nullglob`, if no `scheduled-*.yml` files exist, bash iterates once with the literal glob string. The `[[ -f "$file" ]] || continue` guard handles this correctly. Adding `nullglob` would be cleaner but the guard is sufficient and avoids `shopt` state leakage.

**CI debuggability**: Print each file checked (not just failures) so CI logs show coverage. Pattern: `echo "ok: $file"` for passing files. This helps catch the case where the glob unexpectedly matches zero files.

### Performance

The lint runs `grep` on ~14 small YAML files (<300 lines each). Execution time is negligible (<1 second).

## Acceptance Criteria

- [x] New script `scripts/lint-bot-synthetic-statuses.sh` exists and is executable
- [x] Script scans all `.github/workflows/scheduled-*.yml` files
- [x] Script passes when every file with `gh pr create` also has both `context=cla-check` and `context=test`
- [x] Script fails with clear error listing non-compliant files when a synthetic status is missing
- [x] Script exits 0 when no `scheduled-*.yml` files contain `gh pr create` (no false failures)
- [x] Script accepts `WORKFLOW_DIR` env var override for testability
- [x] New `lint-bot-statuses` job added to `.github/workflows/ci.yml`
- [x] Job runs on `ubuntu-latest`, checks out repo, and executes the lint script
- [x] Existing CI `test` job is unaffected
- [x] Bash test in `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` covers all 6 scenarios below
- [x] `scripts/test-all.sh` does NOT need updating (bash tests in `plugins/soleur/test/` are auto-discovered by the existing `for f in plugins/soleur/test/*.test.sh` loop)

## Test Scenarios

- Given all scheduled workflows have `gh pr create` and both synthetic statuses, when the lint runs, then it exits 0 with a summary of files checked
- Given a `scheduled-foo.yml` with `gh pr create` but missing `context=test`, when the lint runs, then it exits 1 and names the file and the missing context
- Given a `scheduled-bar.yml` with `gh pr create` but missing `context=cla-check`, when the lint runs, then it exits 1 and names the file and the missing context
- Given a `scheduled-baz.yml` with `gh pr create` but missing both contexts, when the lint runs, then it exits 1 and reports both failures
- Given a `scheduled-*.yml` file without `gh pr create`, when the lint runs, then it skips the file silently
- Given zero `scheduled-*.yml` files matching the glob, when the lint runs, then it exits 0

### Test Design Notes

- Tests must create temp directories with `.github/workflows/` structure and set `WORKFLOW_DIR` to point the lint script at them
- Use `assert_eq` from `plugins/soleur/test/test-helpers.sh` (shared test infrastructure) instead of defining a local `assert_exit`
- Each test must clean up after the previous test's files to ensure isolation (or use unique filenames per test)

## MVP

### scripts/lint-bot-synthetic-statuses.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Lint: every scheduled-*.yml with "gh pr create" must also have
# synthetic statuses for all required CI checks.
# Refs: #826, #827, #842

REQUIRED_CONTEXTS=("cla-check" "test")
WORKFLOW_DIR="${WORKFLOW_DIR:-.github/workflows}"
PATTERN="scheduled-*.yml"

failures=0
checked=0

for file in "$WORKFLOW_DIR"/$PATTERN; do
  [[ -f "$file" ]] || continue

  # Only check files that create PRs
  grep -q "gh pr create" "$file" || continue

  checked=$((checked + 1))
  file_ok=true

  for ctx in "${REQUIRED_CONTEXTS[@]}"; do
    if ! grep -q "context=$ctx" "$file"; then
      echo "FAIL: $file contains 'gh pr create' but is missing 'context=$ctx'"
      failures=$((failures + 1))
      file_ok=false
    fi
  done

  if [[ "$file_ok" == "true" ]]; then
    echo "ok: $file"
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo ""
  echo "$failures missing synthetic status(es) found."
  echo "Bot PRs with [skip ci] need synthetic statuses for all required checks."
  echo "See: #826, #827"
  exit 1
fi

echo "All $checked scheduled bot workflow(s) have required synthetic statuses."
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

### plugins/soleur/test/lint-bot-synthetic-statuses.test.sh

```bash
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

# Test 1: File with gh pr create and both contexts passes
echo "Test 1: File with gh pr create and both contexts passes"
WF=$(setup_wf_dir "test1")
cat > "$WF/scheduled-good.yml" << 'YAML'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f state=success -f context=cla-check -f description="ok"
          gh api repos/foo/statuses/$SHA -f state=success -f context=test -f description="ok"
          gh pr create --title "test" --base main
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when both contexts present"
echo ""

# Test 2: Missing context=test fails
echo "Test 2: File missing context=test fails"
WF=$(setup_wf_dir "test2")
cat > "$WF/scheduled-no-test.yml" << 'YAML'
name: NoTest
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f context=cla-check
          gh pr create --title "test"
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when context=test missing"
echo ""

# Test 3: Missing context=cla-check fails
echo "Test 3: File missing context=cla-check fails"
WF=$(setup_wf_dir "test3")
cat > "$WF/scheduled-no-cla.yml" << 'YAML'
name: NoCla
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f context=test
          gh pr create --title "test"
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when context=cla-check missing"
echo ""

# Test 4: Missing both contexts fails
echo "Test 4: File missing both contexts fails"
WF=$(setup_wf_dir "test4")
cat > "$WF/scheduled-no-both.yml" << 'YAML'
name: NoBoth
on: schedule
jobs:
  run:
    steps:
      - run: gh pr create --title "test"
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when both contexts missing"
echo ""

# Test 5: File without gh pr create is skipped (passes)
echo "Test 5: File without gh pr create is skipped"
WF=$(setup_wf_dir "test5")
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

# Test 6: Empty directory (no scheduled-*.yml files) passes
echo "Test 6: Empty workflow directory passes"
WF=$(setup_wf_dir "test6")
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no scheduled-*.yml files exist"
echo ""

print_results
```

## Dependencies & Risks

- **No external dependencies**: Script uses only `bash`, `grep`, and file globs
- **Risk: new required statuses**: If the CI Required ruleset adds new required checks, the `REQUIRED_CONTEXTS` array must be updated manually. Mitigation: the script can be extended to read required contexts from a config file or the ruleset API, but that is out of scope for MVP
- **Risk: workflow naming convention changes**: If bot workflows stop using the `scheduled-*` prefix, the glob must be updated. This is unlikely given established convention
- **Risk: WORKFLOW_DIR env var collision**: The `WORKFLOW_DIR` env var is used for testability. If another tool sets this env var, the lint would scan the wrong directory. Mitigated by using a descriptive default and only overriding in tests.

### Research Insights: Simplicity Check

The implementation is appropriately minimal:

- No YAML parsing library needed -- `grep -q` on file content is correct for this pattern
- No external tools (`actionlint`, `yamllint`) -- they would add a dependency for a simple string presence check
- No configuration file for required contexts -- the array is 2 elements; a config file adds indirection without value at this scale
- The `WORKFLOW_DIR` env var override is the minimum needed for testability -- no argument parsing, no flags

## References & Research

- Issue #842: this issue
- PR #827: added synthetic statuses to all 9 bot workflows
- Issue #826: CI Required ruleset design
- `scripts/create-ci-required-ruleset.sh`: script that creates the ruleset (pre-flight check pattern)
- `.github/workflows/ci.yml`: existing CI workflow (1 job: `test`)
- `plugins/soleur/test/test-helpers.sh`: shared bash test helpers (`assert_eq`, `assert_contains`, `print_results`)
- `scripts/test-all.sh`: test runner that auto-discovers bash tests from `plugins/soleur/test/*.test.sh`
- `plugins/soleur/test/resolve-git-root.test.sh`: reference bash test using `test-helpers.sh` pattern
