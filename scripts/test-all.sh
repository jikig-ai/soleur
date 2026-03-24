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

run_suite "test/content-publisher" bun test test/content-publisher.test.ts
run_suite "test/x-community" bun test test/x-community.test.ts
run_suite "test/pre-merge-rebase" bun test test/pre-merge-rebase.test.ts
run_suite "apps/web-platform" bun test apps/web-platform/
run_suite "apps/telegram-bridge" bun test apps/telegram-bridge/
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
