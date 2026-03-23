#!/usr/bin/env bash
set -euo pipefail

# Lint: scheduled workflows that create PRs must NOT use [skip ci].
#
# [skip ci] prevents CI from running on the PR, which means the
# required "test" Check Run is never created and auto-merge is
# permanently blocked.
#
# Refs: #826, #827, #842, #1014

WORKFLOW_DIR="${WORKFLOW_DIR:-.github/workflows}"
PATTERN="scheduled-*.yml"

failures=0
checked=0

for file in "$WORKFLOW_DIR"/$PATTERN; do
  [[ -f "$file" ]] || continue

  # Only check files that create PRs
  grep -q "gh pr create" "$file" || continue

  checked=$((checked + 1))

  if grep -qF '[skip ci]' "$file"; then
    echo "FAIL: $file contains [skip ci] — this blocks auto-merge on required checks"
    failures=$((failures + 1))
  else
    echo "ok: $file"
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo ""
  echo "$failures workflow(s) use [skip ci] which prevents CI and blocks auto-merge."
  echo "Remove [skip ci] so the required 'test' Check Run is created."
  echo "See: #1014"
  exit 1
fi

echo "All $checked scheduled bot workflow(s) pass (no [skip ci])."
exit 0
