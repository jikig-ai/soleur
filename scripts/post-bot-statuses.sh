#!/usr/bin/env bash
# post-bot-statuses.sh -- Post synthetic success statuses for bot commits so
# that required status checks (cla-check, test) do not block auto-merge.
#
# Usage: post-bot-statuses.sh <commit-sha>
#
# Environment variables:
#   GITHUB_REPOSITORY - owner/repo (set automatically by GitHub Actions)
#   GH_TOKEN          - GitHub token for API auth (set by workflow step env)
#
# Exit codes:
#   0 - All statuses posted successfully
#   1 - Missing argument or gh api failure
#
# Refs: #841, #826, #827

set -euo pipefail

# --- Argument Validation ---

if [[ $# -lt 1 ]]; then
  echo "Usage: post-bot-statuses.sh <commit-sha>" >&2
  exit 1
fi

local_sha="$1"

if [[ ! "$local_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Error: invalid commit SHA: $local_sha" >&2
  exit 1
fi

# --- Status Definitions ---
# Add new required status checks here. Each entry: "context|description"
# When adding a new entry, also update scripts/create-ci-required-ruleset.sh
# to include the new context in the required_status_checks array.

STATUSES=(
  "cla-check|CLA not required for automated PRs"
  "test|Bot commit - CI not required"
)

# --- Post Statuses ---

for entry in "${STATUSES[@]}"; do
  local_context="${entry%%|*}"
  local_description="${entry#*|}"
  gh api "repos/${GITHUB_REPOSITORY}/statuses/${local_sha}" \
    -f state=success \
    -f context="$local_context" \
    -f description="$local_description" > /dev/null
done
