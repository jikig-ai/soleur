#!/usr/bin/env bash
# Create the "CI Required" repository ruleset on jikig-ai/soleur.
#
# This script adds the `test` status check as a required check on main,
# preventing auto-merge when CI fails or is skipped.
#
# IMPORTANT: Run this AFTER the bot workflow updates have merged to main.
# If run before, bot PRs using [skip ci] will be permanently blocked
# because the `test` check remains in "Pending" state forever.
#
# Refs: #826, #820

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_NAME="CI Required"

# Pre-flight: verify bot workflows on main already have synthetic test status
main_content=$(gh api "repos/${REPO}/contents/.github/workflows/scheduled-weekly-analytics.yml" --jq '.content' 2>/dev/null || true)
if [[ -n "$main_content" ]] && ! echo "$main_content" | base64 -d 2>/dev/null | grep -q 'context=test'; then
  echo "ERROR: Bot workflows on main do not yet have the synthetic test status."
  echo "Merge the workflow update PR first, then run this script."
  exit 1
fi

# Check if ruleset already exists
existing=$(gh api "repos/${REPO}/rulesets" --jq ".[] | select(.name == \"${RULESET_NAME}\") | .id" 2>/dev/null || true)
if [[ -n "$existing" ]]; then
  echo "Ruleset '${RULESET_NAME}' already exists (ID: ${existing}). Skipping creation."
  exit 0
fi

# Write payload to temp file to avoid shell escaping issues (per institutional learning)
payload=$(mktemp)
trap 'rm -f "$payload"' EXIT

cat > "$payload" << 'EOF'
{
  "name": "CI Required",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          {
            "context": "test",
            "integration_id": 15368
          },
          {
            "context": "dependency-review",
            "integration_id": 15368
          },
          {
            "context": "e2e",
            "integration_id": 15368
          }
        ]
      }
    }
  ],
  "bypass_actors": [
    {
      "actor_id": null,
      "actor_type": "OrganizationAdmin",
      "bypass_mode": "pull_request"
    },
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "pull_request"
    }
  ]
}
EOF

echo "Creating '${RULESET_NAME}' ruleset on ${REPO}..."
result=$(gh api "repos/${REPO}/rulesets" -X POST --input "$payload")

echo "Ruleset created. Verification:"
echo "$result" | jq '{id, name, enforcement, checks: .rules[0].parameters.required_status_checks, bypass_actors: [.bypass_actors[] | {actor_type, bypass_mode}]}'
