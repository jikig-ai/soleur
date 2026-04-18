#!/usr/bin/env bash
set -euo pipefail

# Sequential test runner that isolates test suites to avoid Bun's FPE crash
# when running all tests via recursive directory discovery.
# See: knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md

# --- Version Check ---
if [[ -f .bun-version ]]; then
  expected=$(tr -d '[:space:]' < .bun-version)
  actual=$(bun --version)
  if [[ "$actual" != "$expected" ]]; then
    echo "WARNING: Bun $actual installed, expected $expected (from .bun-version)" >&2
    echo "Run: bun upgrade" >&2
  fi
fi

# --- Git Hook Isolation ---
# When invoked as a lefthook pre-commit hook, git sets GIT_DIR, GIT_INDEX_FILE,
# and GIT_WORK_TREE in the environment. These override GIT_CEILING_DIRECTORIES
# and cause test-spawned git commands to operate on the parent repo instead of
# their temp directories. Unsetting them restores normal git discovery behavior.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

# --- Bare Repo Guard ---
# Bare repos contain stale working-tree files that diverge from HEAD.
# Running tests from a bare root produces phantom failures.
# Use a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh
if git rev-parse --is-bare-repository 2>/dev/null | grep -q true; then
  echo "ERROR: Cannot run tests from a bare repository root." >&2
  echo "Stale files at the bare root diverge from HEAD and produce phantom test failures." >&2
  echo "Run from a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh" >&2
  exit 1
fi

# --- Run Tests Per Directory ---
failed=0
suites=0

run_suite() {
  local label="$1"; shift
  suites=$((suites + 1))
  echo "--- $label ---"
  if "$@"; then
    echo "[ok] $label"
  else
    echo "[FAIL] $label" >&2
    failed=$((failed + 1))
  fi
}

run_suite "tests/hooks/incidents" bash tests/hooks/test_incidents.sh
run_suite "tests/hooks/emissions" bash tests/hooks/test_hook_emissions.sh
run_suite "tests/scripts/lint-rule-ids" python3 -m unittest tests.scripts.test_lint_rule_ids
run_suite "tests/scripts/rule-id-regex-parity" python3 -m unittest tests.scripts.test_rule_id_regex_parity
run_suite "tests/scripts/rule-metrics-aggregate" bash tests/scripts/test-rule-metrics-aggregate.sh
run_suite "tests/commands/sync-rule-prune" bash tests/commands/test-sync-rule-prune.sh
run_suite "test/content-publisher" bun test test/content-publisher.test.ts
run_suite "test/x-community" bun test test/x-community.test.ts
run_suite "test/pre-merge-rebase" bun test test/pre-merge-rebase.test.ts
run_suite "apps/web-platform" bash -c "cd apps/web-platform && npm run test:ci 2>&1"
run_suite "plugins/soleur" bun test plugins/soleur/
run_suite "blog-link-validation" bash scripts/validate-blog-links.sh

# Bash tests (not discovered by bun test; ci-deploy.test.sh runs in infra-validation.yml)
for f in plugins/soleur/test/*.test.sh; do
  [[ -f "$f" ]] || continue
  run_suite "$f" bash "$f"
done

echo "=== $((suites - failed))/$suites suites passed ==="
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
