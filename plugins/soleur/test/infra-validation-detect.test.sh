#!/usr/bin/env bash

# Tests for the detect-changes pipeline in .github/workflows/infra-validation.yml.
# Run: bash plugins/soleur/test/infra-validation-detect.test.sh
#
# Defect class: git pathspec `*` does not cross `/` in default semantics, so
# `'apps/*/infra/'` (single `*`, trailing slash, no `**`) returns empty for
# every changed infra file. The pipeline silently emits `[]`, the gated
# `validate` matrix fans out to zero jobs, and GitHub Actions reports
# `success`. See #4012 and learning 2026-03-21-lefthook-gobwas-glob-double-star.md
# for the sibling class (Lefthook gobwas glob `**` semantics).
#
# Test isolation: detect_infra_dirs() reads stdin (synthetic `git diff
# --name-only` output) so the test is hermetic — no real git invocation,
# no version-of-git dependency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# The detect_infra_dirs() function under test is byte-identical to the shell
# pipeline body inside .github/workflows/infra-validation.yml's detect-changes
# job (modulo the `git diff` call, which the workflow pipes in upstream).
# Pathspec → regex translation per learning
# 2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md.
detect_infra_dirs() {
  { grep -E '^(apps/[^/]+/infra|infra/[^/]+)/' || true; } \
    | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' \
    | sort -u \
    | jq -R -s -c 'split("\n") | map(select(. != ""))'
}

echo "=== infra-validation-detect tests ==="
echo ""

# --- TS1: apps/<x>/infra/ direct child ---
echo "TS1: apps/<x>/infra/ direct child collapses to single-ancestor dir"
OUT=$(printf '%s\n' "apps/web-platform/infra/uptime-alerts.tf" | detect_infra_dirs)
assert_eq '["apps/web-platform/infra"]' "$OUT" "direct child → [apps/web-platform/infra]"
echo ""

# --- TS2: apps/<x>/infra/ single-ancestor nested ---
echo "TS2: apps/<x>/infra/<sub>/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "apps/web-platform/infra/sentry/uptime-monitors.tf" | detect_infra_dirs)
assert_eq '["apps/web-platform/infra"]' "$OUT" "single-ancestor nested → [apps/web-platform/infra]"
echo ""

# --- TS3: apps/<x>/infra/ deep-nested ---
echo "TS3: apps/<x>/infra/a/b/c/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "apps/web-platform/infra/test-fixtures/audit-bwrap/foo.tf" | detect_infra_dirs)
assert_eq '["apps/web-platform/infra"]' "$OUT" "deep-nested → [apps/web-platform/infra]"
echo ""

# --- TS4: infra/<x>/ direct child ---
echo "TS4: infra/<x>/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "infra/github/main.tf" | detect_infra_dirs)
assert_eq '["infra/github"]' "$OUT" "direct child → [infra/github]"
echo ""

# --- TS5: infra/<x>/ deep-nested ---
echo "TS5: infra/<x>/a/b/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "infra/github/deeply/nested/foo.tf" | detect_infra_dirs)
assert_eq '["infra/github"]' "$OUT" "deep-nested → [infra/github]"
echo ""

# --- TS6: mixed + non-infra controls ---
echo "TS6: mixed infra paths and non-infra controls → sorted, deduped, non-infra filtered"
OUT=$(printf '%s\n' \
  "apps/web-platform/infra/uptime-alerts.tf" \
  "apps/cla-evidence/infra/main.tf" \
  "infra/github/main.tf" \
  "apps/web-platform/server/route.ts" \
  "knowledge-base/project/plans/foo.md" \
  | detect_infra_dirs)
assert_eq '["apps/cla-evidence/infra","apps/web-platform/infra","infra/github"]' "$OUT" \
  "mixed input → 3 sorted infra dirs, non-infra filtered"
echo ""

# --- TS7: empty / zero-match (non-infra only) ---
echo "TS7: non-infra-only input → empty matrix [] (no failure under bash -e)"
OUT=$(printf '%s\n' "apps/web-platform/server/route.ts" | detect_infra_dirs)
assert_eq '[]' "$OUT" "non-infra only → []"
echo ""

# --- TS8: real-commit baseline (pathspec→regex equivalence per learning 2026-05-09) ---
# Pipeline-mode guard: if commit 7e6f6726 is not in this repo (e.g., shallow
# clone in a CI test runner), skip TS8 gracefully — the unit-test scenarios
# above already exercise every shape that TS8 would.
echo "TS8: real-commit baseline against 7e6f6726 (uptime-alerting motivating commit)"
REPO_ROOT="$SCRIPT_DIR/../../.."
if git -C "$REPO_ROOT" rev-parse --verify --quiet '7e6f6726^{commit}' >/dev/null; then
  EXPECTED='["apps/web-platform/infra"]'
  ACTUAL=$(git -C "$REPO_ROOT" diff --name-only 7e6f6726^..7e6f6726 | detect_infra_dirs)
  assert_eq "$EXPECTED" "$ACTUAL" "real-commit 7e6f6726 → [apps/web-platform/infra]"
else
  echo "  SKIP: commit 7e6f6726 not present in repo (shallow clone?); unit scenarios above cover the shape matrix"
fi
echo ""

print_results
