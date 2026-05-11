#!/usr/bin/env bash
# Create the "CI Required" repository ruleset on jikig-ai/soleur.
#
# This script adds the `test`, `dependency-review`, and `e2e` status checks
# as required checks on main, preventing auto-merge when CI fails or is skipped.
#
# IMPORTANT: Run this AFTER the bot workflow updates have merged to main.
# If run before, bot PRs using [skip ci] will be permanently blocked
# because the required checks remain in "Pending" state forever.
#
# Refs: #826, #820

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_NAME="CI Required"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CANONICAL_BYPASS_FILE="${SCRIPT_DIR}/ci-required-ruleset-canonical-bypass-actors.json"

# bypass_actors source-of-truth lives in a sibling JSON file shared with
# .github/workflows/scheduled-ruleset-bypass-audit.yml (#3544). Editing
# the array here is a workflow violation -- update the JSON instead so
# the audit's canonical reference stays in sync. R10 Sharp Edge ("JSON
# payload via heredoc into a file, then --input \"\$payload\"") still
# applies; the canonical JSON is read via jq --slurpfile and merged
# into the heredoc payload below.
if [[ ! -f "$CANONICAL_BYPASS_FILE" ]]; then
  echo "ERROR: canonical bypass_actors file not found: $CANONICAL_BYPASS_FILE" >&2
  exit 1
fi
if ! jq -e 'type == "array"' "$CANONICAL_BYPASS_FILE" >/dev/null 2>&1; then
  echo "ERROR: $CANONICAL_BYPASS_FILE is not a JSON array" >&2
  exit 1
fi

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

# Write payload to temp file to avoid shell escaping issues (per institutional learning).
# bypass_actors is sourced from the canonical JSON file via --slurpfile so it
# stays in sync with the daily audit's reference (#3544).
payload=$(mktemp)
skeleton=$(mktemp)
trap 'rm -f "$payload" "$skeleton"' EXIT

cat > "$skeleton" << 'EOF'
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
  ]
}
EOF

# Merge canonical bypass_actors into the skeleton.
jq --slurpfile bypass "$CANONICAL_BYPASS_FILE" '. + {bypass_actors: $bypass[0]}' "$skeleton" > "$payload"

echo "Creating '${RULESET_NAME}' ruleset on ${REPO}..."
result=$(gh api "repos/${REPO}/rulesets" -X POST --input "$payload")

echo "Ruleset created. Verification:"
echo "$result" | jq '{id, name, enforcement, checks: .rules[0].parameters.required_status_checks, bypass_actors: [.bypass_actors[] | {actor_type, bypass_mode}]}'
