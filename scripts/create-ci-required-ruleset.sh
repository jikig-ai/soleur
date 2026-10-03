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
# The skeleton restores BOTH rules the live ruleset carries: `required_status_checks`
# AND `merge_queue` (re-adopted by #9454; #5780/#5800 adopted it first and it was
# reverted 2026-06-30 because CodeQL cannot report a status on `merge_group`).
# `CodeQL` is therefore NOT in the canonical required-checks JSON and NOT in this
# skeleton: it is advisory (codeql-main-alert-gate.yml watches pushes to main). The
# jq below addresses each rule by TYPE (never a positional `.rules[0]`).
#
# SYNC GUARD (#9454): the `merge_queue` parameters in the skeleton MUST stay in
# lockstep with the `merge_queue {}` block in infra/github/ruleset-ci-required.tf
# AND the params table in infra/github/README.md. tests/scripts/test-audit-ruleset-bypass.sh
# (T-mq-1) fails CI on any divergence of the seven values, or if a `CodeQL` required
# context reappears beside the queue. The REST API requires ALL SEVEN parameters
# together (a partial payload 422s), so all seven are written here explicitly; do NOT
# copy the 15/5/5 values from the historical skeleton (commit 1f041b9d6a).
#
# EMERGENCY PATH (queue deadlocked AND `gh pr merge --admin` bypass failed): a stuck
# queue is normally rolled back with the single Terraform diff in infra/github/README.md.
# If that cannot be applied, re-create the ruleset WITHOUT the queue rule:
#   OMIT_MERGE_QUEUE=1 bash scripts/create-ci-required-ruleset.sh
# This script only POSTs when no "CI Required" ruleset exists, so the live ruleset must
# first be deleted (deliberate, operator-authorized: it is the same DR flow as a
# from-scratch restore), then `terraform import` + `plan/apply` reconcile it back. With
# OMIT_MERGE_QUEUE=1 the queue rule is stripped from the payload; the verification
# output below then prints `merge_queue: null`.
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
    },
    {
      "type": "merge_queue",
      "parameters": {
        "merge_method": "SQUASH",
        "grouping_strategy": "ALLGREEN",
        "max_entries_to_merge": 1,
        "min_entries_to_merge": 1,
        "min_entries_to_merge_wait_minutes": 0,
        "max_entries_to_build": 2,
        "check_response_timeout_minutes": 60
      }
    }
  ]
}
EOF

# Merge canonical bypass_actors AND required_status_checks into the skeleton.
# Address the status-checks rule by TYPE, never a positional .rules[0]: the skeleton
# holds two rules (required_status_checks + merge_queue). The PUT/POST carries
# bypass_actors and conditions too (replace semantics; the skeleton has `conditions`).
# OMIT_MERGE_QUEUE=1 strips the queue rule (emergency path, see header).
omit_queue=false
[[ "${OMIT_MERGE_QUEUE:-}" == "1" ]] && omit_queue=true
jq --argjson omit_queue "$omit_queue" \
  --slurpfile bypass "$CANONICAL_BYPASS_FILE" --slurpfile rsc "$CANONICAL_RSC_FILE" \
  '. + {bypass_actors: $bypass[0]}
     | (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks) = $rsc[0]
     | if $omit_queue then .rules |= map(select(.type != "merge_queue")) else . end' \
  "$skeleton" > "$payload"

echo "Creating '${RULESET_NAME}' ruleset on ${REPO}..."
result=$(gh api "repos/${REPO}/rulesets" -X POST --input "$payload")

echo "Ruleset created. Verification:"
echo "$result" | jq '{
  id, name, enforcement,
  checks: (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks),
  merge_queue: ([.rules[] | select(.type == "merge_queue") | .parameters] | first // null),
  bypass_actors: [.bypass_actors[] | {actor_type, bypass_mode}]
}'
