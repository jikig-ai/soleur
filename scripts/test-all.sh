#!/usr/bin/env bash
set -euo pipefail

# Sequential test runner that isolates test suites to avoid Bun's FPE crash
# when running all tests via recursive directory discovery.
# See: knowledge-base/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md

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
  if bun test "$@"; then
    echo "[ok] $label"
  else
    echo "[FAIL] $label" >&2
    failed=$((failed + 1))
  fi
}

run_suite "test/content-publisher" test/content-publisher.test.ts
run_suite "test/x-community" test/x-community.test.ts
run_suite "test/pre-merge-rebase" test/pre-merge-rebase.test.ts
run_suite "apps/web-platform" apps/web-platform/
run_suite "apps/telegram-bridge" apps/telegram-bridge/
run_suite "plugins/soleur" plugins/soleur/

echo "=== $((suites - failed))/$suites suites passed ==="
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
