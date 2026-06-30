#!/usr/bin/env bash
# Create the "CI Required" repository ruleset on jikig-ai/soleur.
#
# This is the documented DISASTER-RECOVERY restore path: it POSTs the full
# ruleset skeleton ONLY when no "CI Required" ruleset exists (it exits early
# if one is already present, so it never replaces a live ruleset). The
# canonical management path is Terraform (infra/github/ruleset-ci-required.tf
# + apply-github-infra.yml). After running this DR restore, run
# `terraform import` + `terraform plan/apply` to reconcile the ruleset back
# to Terraform-managed state.
#
# The skeleton restores the single `required_status_checks` rule. (#5780 briefly
# added a `merge_queue` rule here too, but that was REVERTED — the merge queue
# deadlocked main because CodeQL default setup does not post on `merge_group`
# temp refs. See ADR-032 + the PIR.) The jq below addresses the status-checks
# rule by TYPE (not a positional `.rules[0]`) so it stays correct if a second
# rule is ever re-introduced.
#
# IMPORTANT: Run this AFTER the bot workflow updates have merged to main.
# If run before, bot PRs using [skip ci] will be permanently blocked
# because the required checks remain in "Pending" state forever.
#
# Refs: #826, #820, #5780

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_NAME="CI Required"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CANONICAL_BYPASS_FILE="${SCRIPT_DIR}/ci-required-ruleset-canonical-bypass-actors.json"
CANONICAL_RSC_FILE="${SCRIPT_DIR}/ci-required-ruleset-canonical-required-status-checks.json"

# Both `bypass_actors` (#3544) and `required_status_checks` (#3547) source
# of truth live in sibling JSON files shared with the daily audit workflow
# (.github/workflows/scheduled-ruleset-bypass-audit.yml). Editing the
# arrays inline here is a workflow violation -- update the JSON files
# instead so the audit's canonical reference stays in sync. R10 Sharp
# Edge ("JSON payload via heredoc into a file, then --input \"\$payload\"")
# still applies; both canonical JSONs are read via jq --slurpfile and
# merged into the skeleton heredoc payload below.
for f in "$CANONICAL_BYPASS_FILE" "$CANONICAL_RSC_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: canonical file not found: $f" >&2
    exit 1
  fi
  if ! jq -e 'type == "array"' "$f" >/dev/null 2>&1; then
    echo "ERROR: $f is not a JSON array" >&2
    exit 1
  fi
done

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
        "required_status_checks": []
      }
    }
  ]
}
EOF

# Merge canonical bypass_actors AND required_status_checks into the skeleton.
# Address the status-checks rule by TYPE, never a positional .rules[0], so this
# stays correct if a second rule (e.g. a future merge_queue) is reintroduced.
jq --slurpfile bypass "$CANONICAL_BYPASS_FILE" --slurpfile rsc "$CANONICAL_RSC_FILE" \
  '. + {bypass_actors: $bypass[0]}
     | (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks) = $rsc[0]' \
  "$skeleton" > "$payload"

echo "Creating '${RULESET_NAME}' ruleset on ${REPO}..."
result=$(gh api "repos/${REPO}/rulesets" -X POST --input "$payload")

echo "Ruleset created. Verification:"
echo "$result" | jq '{
  id, name, enforcement,
  checks: (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks),
  bypass_actors: [.bypass_actors[] | {actor_type, bypass_mode}]
}'
