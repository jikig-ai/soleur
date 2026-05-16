#!/usr/bin/env bash
# Create or update the "CLA Required" repository ruleset on jikig-ai/soleur.
#
# Required status checks (integration_id 15368 = GitHub Actions Check Runs API):
#   - cla-check     (existing job in .github/workflows/cla.yml)
#   - cla-evidence  (sidecar evidence-write gate from .github/workflows/cla-evidence.yml)
#
# bypass_mode is "pull_request" for OrganizationAdmin and RepositoryRole,
# blocking direct pushes to main while allowing admin bypass on PRs.
# The CLA bot Integration retains "always" so it can update CLA status.
#
# Re-apply semantics: GitHub ruleset PUT is full-replace, not partial (learning
# #11). When the ruleset exists, this script PUTs the entire desired payload to
# the ruleset's ID — sweeping any ghost bypass actors and reconciling the
# required-checks list. When it does not exist, it POSTs to create.
#
# Refs: #1655, #3209

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_NAME="CLA Required"

# Check if ruleset already exists
existing=$(gh api "repos/${REPO}/rulesets" --jq ".[] | select(.name == \"${RULESET_NAME}\") | .id" 2>/dev/null || true)

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
          },
          {
            "context": "cla-evidence",
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

if [[ -n "$existing" ]]; then
  echo "Updating '${RULESET_NAME}' ruleset (ID: ${existing}) via full-replace PUT (learning #11)..."
  result=$(gh api "repos/${REPO}/rulesets/${existing}" -X PUT --input "$payload")
  echo "Ruleset updated. Verification:"
else
  echo "Creating '${RULESET_NAME}' ruleset on ${REPO}..."
  result=$(gh api "repos/${REPO}/rulesets" -X POST --input "$payload")
  echo "Ruleset created. Verification:"
fi
echo "$result" | jq '{id, name, enforcement, checks: .rules[0].parameters.required_status_checks, bypass_actors: [.bypass_actors[] | {actor_type, bypass_mode}]}'
