#!/usr/bin/env bash
# Restore the "CLA Required" repository ruleset on jikig-ai/soleur.
#
# This is the documented DISASTER-RECOVERY restore path: it POSTs the full
# ruleset skeleton ONLY when no "CLA Required" ruleset exists (it exits early
# if one is already present, so it never replaces a live ruleset). The canonical
# management path is Terraform (infra/github/ruleset-cla-required.tf +
# apply-github-infra.yml) as of #6072. After running this DR restore, run
#   terraform import github_repository_ruleset.cla_required soleur:<id>
# then `terraform plan` + `terraform apply` to reconcile the ruleset back to
# Terraform-managed state.
#
# Required status checks (integration_id 15368 = GitHub Actions Check Runs API):
#   - cla-check     (job in .github/workflows/cla.yml)
#   - cla-evidence  (sidecar evidence-write gate from .github/workflows/cla-evidence.yml)
#
# bypass_mode is "pull_request" for OrganizationAdmin and RepositoryRole,
# blocking direct pushes to main while allowing admin bypass on PRs. The CLA bot
# Integration retains "always" so it can update CLA status.
#
# Both the bypass_actors and required_status_checks source of truth live in
# sibling canonical JSON files shared with the daily audit
# (apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts).
# Editing the arrays inline here is a workflow violation — update the JSON files
# instead (and reconcile ruleset-cla-required.tf) so the audit's canonical
# reference stays in sync. Both canonical JSONs are read via jq --slurpfile and
# merged into the skeleton payload below; the former inline heredoc payload was
# retired in #6072 when the CLA ruleset moved to Terraform.
#
# Refs: #1655, #3209, #6061, #6072

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_NAME="CLA Required"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CANONICAL_BYPASS_FILE="${SCRIPT_DIR}/ci-cla-required-ruleset-canonical-bypass-actors.json"
CANONICAL_RSC_FILE="${SCRIPT_DIR}/ci-cla-required-ruleset-canonical-required-status-checks.json"

# Both canonical files must exist and be JSON arrays before we merge them.
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

# DR-only guard: never replace a live ruleset. The update / full-replace path is
# now `terraform apply` (infra/github/ruleset-cla-required.tf). (Unlike the CI DR
# script, there is no `context=test` bot-workflow preflight — that check is
# CI-semantic; CLA's required checks are cla-check / cla-evidence.)
existing=$(gh api "repos/${REPO}/rulesets" --jq ".[] | select(.name == \"${RULESET_NAME}\") | .id" 2>/dev/null || true)
if [[ -n "$existing" ]]; then
  echo "Ruleset '${RULESET_NAME}' already exists (ID: ${existing}). Skipping creation."
  echo "To modify it, edit infra/github/ruleset-cla-required.tf and let apply-github-infra.yml apply on merge."
  exit 0
fi

# Write payload to temp file to avoid shell escaping issues (per institutional
# learning). Both arrays are sourced from the canonical JSON files via
# --slurpfile so they stay in sync with the daily audit's reference.
payload=$(mktemp)
skeleton=$(mktemp)
trap 'rm -f "$payload" "$skeleton"' EXIT

cat > "$skeleton" << 'EOF'
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
        "required_status_checks": []
      }
    }
  ]
}
EOF

# Merge canonical bypass_actors AND required_status_checks into the skeleton.
# Address the status-checks rule by TYPE, never a positional .rules[0], so this
# stays correct if a second rule is ever introduced.
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
