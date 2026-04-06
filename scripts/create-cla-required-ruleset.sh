#!/usr/bin/env bash
# Create the "CLA Required" repository ruleset on jikig-ai/soleur.
#
# This script adds the `cla-check` status check as a required check on main,
# ensuring all contributors have signed the CLA before merging.
#
# bypass_mode is "pull_request" for OrganizationAdmin and RepositoryRole,
# blocking direct pushes to main while allowing admin bypass on PRs.
# The CLA bot Integration retains "always" so it can update CLA status.
#
# Refs: #1655

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_NAME="CLA Required"

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
  "name": "CLA Required",
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
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          {
            "context": "cla-check",
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
    },
    {
      "actor_id": 1236702,
      "actor_type": "Integration",
      "bypass_mode": "always"
    }
  ]
}
EOF

echo "Creating '${RULESET_NAME}' ruleset on ${REPO}..."
result=$(gh api "repos/${REPO}/rulesets" -X POST --input "$payload")

echo "Ruleset created. Verification:"
echo "$result" | jq '{id, name, enforcement, checks: .rules[0].parameters.required_status_checks, bypass_actors: [.bypass_actors[] | {actor_type, bypass_mode}]}'
