#!/usr/bin/env bash
# Detect PRs dominated by the autonomous loop's auto-commit headlines (#2905).
#
# Reads PR_NUMBER from env. Counts how many commit headlines on the PR branch
# match the exact strings emitted by `apps/web-platform/server/session-sync.ts`
# (`Auto-commit before sync pull`, `Auto-commit after session`) or the
# `git pull --no-rebase` merge headline (`Merge branches 'main' and 'main' of …`).
# Fails if more than 50% of the headlines match — indicating the PR was
# largely synthesized by the auto-commit sweep rather than by an authored
# change.

set -uo pipefail

: "${PR_NUMBER:?PR_NUMBER env var required}"

headlines=$(gh pr view "$PR_NUMBER" --json commits --jq '.commits[].messageHeadline' 2>/dev/null || echo "")

if [[ -z "$headlines" ]]; then
  echo "::warning::Could not fetch commit headlines; skipping auto-commit density check"
  exit 0
fi

total=0
matched=0
# Anchored regex: only the EXACT strings from session-sync.ts plus the
# git-pull merge headline. Anchored with ^ to avoid prose mentions.
# SYNC: AUTO_COMMIT_MSG_PULL / AUTO_COMMIT_MSG_PUSH in
# apps/web-platform/server/session-sync.ts. If either constant changes,
# update the regex below in the same PR.
auto_re='^(Auto-commit (before sync pull|after session)|Merge branches '\''main'\'' and '\''main'\'' of )'

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  total=$((total + 1))
  if [[ "$line" =~ $auto_re ]]; then
    matched=$((matched + 1))
  fi
done <<<"$headlines"

if [[ "$total" -eq 0 ]]; then
  exit 0
fi

pct=$(( matched * 100 / total ))
echo "Total commits: $total, auto-commit headlines: $matched ($pct%)"

if [[ "$pct" -gt 50 ]]; then
  echo "::error::More than 50% of commit headlines match the auto-commit sweep pattern."
  echo "Rebase or amend with human-readable commit messages. See #2905."
  exit 1
fi
exit 0
