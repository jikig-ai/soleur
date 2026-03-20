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

  # Accept either inline context= patterns or the shared script call
  if grep -q "post-bot-statuses.sh" "$file"; then
    : # Shared script handles all required statuses
  else
    for ctx in "${REQUIRED_CONTEXTS[@]}"; do
      if ! grep -q "context=$ctx" "$file"; then
        echo "FAIL: $file contains 'gh pr create' but is missing 'context=$ctx'"
        failures=$((failures + 1))
        file_ok=false
      fi
    done
  fi

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
