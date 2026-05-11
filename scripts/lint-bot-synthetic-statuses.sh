#!/usr/bin/env bash
set -euo pipefail

# Lint: bot workflows that create PRs must NOT use [skip ci].
#
# [skip ci] prevents CI from running on the PR, which means the
# required "test" Check Run is never created and auto-merge is
# permanently blocked.
#
# Scope is content-based (since #3548): walks every workflow in
# .github/workflows/ and exempts skill-security-scan-pr-trailer.yml
# (real CI, not a bot workflow). Any file with `gh pr create` is in
# scope regardless of filename prefix.
#
# Refs: #826, #827, #842, #1014, #3548

WORKFLOW_DIR="${WORKFLOW_DIR:-.github/workflows}"

failures=0
checked=0

for file in "$WORKFLOW_DIR"/*.yml; do
  [[ -f "$file" ]] || continue

  # Exclude skill-security-scan-pr-trailer.yml: real CI workflow on
  # pull_request_target, not a bot PR-creator. Mirrors the exclusion in
  # lint-bot-synthetic-completeness.sh and audit-bot-codeql-coverage.sh.
  [[ "$file" == *skill-security-scan-pr-trailer* ]] && continue

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

echo "All $checked bot workflow(s) pass (no [skip ci])."
exit 0
