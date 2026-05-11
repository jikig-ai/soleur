#!/usr/bin/env bash
# Add `skill-security-scan PR gate` to the "CI Required" ruleset
# (R15 mitigation, #3542).
#
# Idempotent: if the check is already in required_status_checks, exit 0
# with a no-op message.
#
# Dry-run: `--dry-run` prints the payload without PUT.
#
# IMPORTANT: Run AFTER bot workflow updates (Phase 2 in
# plans/2026-05-11-feat-skill-security-scan-branch-protection-plan.md)
# have merged to main. If run before, bot PRs from the 3 inline workflows
# + 5 composite-action workflows will deadlock on the new required check
# until their next run reflects the merge.
#
# Refs: #3542, #2719, learning 2026-04-03-github-ruleset-put-replaces-entire-payload.md

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_ID=14145388
NEW_CHECK="skill-security-scan PR gate"
GITHUB_ACTIONS_INTEGRATION_ID=15368  # github-actions[bot]
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

before=$(mktemp)
payload=$(mktemp)
after=$(mktemp)
trap 'rm -f "$before" "$payload" "$after"' EXIT

# 1. Preflight: confirm the composite action on main already has the new
#    check token. If not, the ruleset PUT would deadlock 5+ bot workflows.
echo "Preflight: checking composite action on main..."
composite_b64=$(gh api "repos/${REPO}/contents/.github/actions/bot-pr-with-synthetic-checks/action.yml?ref=main" --jq '.content' 2>/dev/null || true)
if [[ -z "$composite_b64" ]]; then
  echo "::error::Could not fetch composite action from main"
  exit 1
fi
if ! echo "$composite_b64" | base64 -d | grep -q '"skill-security-scan PR gate"'; then
  echo "::error::Composite action on main does NOT include 'skill-security-scan PR gate'."
  echo "         Merge Phase 2 first, then re-run this script."
  exit 1
fi
echo "Preflight OK: composite action has the new check token."

# 2. Snapshot current ruleset (live; never trust cached values)
gh api "repos/${REPO}/rulesets/${RULESET_ID}" > "$before"

# 3. Idempotency check
if jq -e --arg c "$NEW_CHECK" \
    '.rules[0].parameters.required_status_checks | map(.context) | index($c) != null' \
    "$before" >/dev/null; then
  echo "Already present in required_status_checks. No-op."
  exit 0
fi

# 4. Build updated payload — preserve bypass_actors, conditions, name,
#    target, enforcement verbatim from the GET. The PUT API replaces the
#    entire payload, so any omission silently strips the field.
jq --arg c "$NEW_CHECK" --argjson iid "$GITHUB_ACTIONS_INTEGRATION_ID" '{
  name: .name,
  target: .target,
  enforcement: .enforcement,
  bypass_actors: .bypass_actors,
  conditions: .conditions,
  rules: [
    {
      type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: .rules[0].parameters.strict_required_status_checks_policy,
        do_not_enforce_on_create: .rules[0].parameters.do_not_enforce_on_create,
        required_status_checks: (
          .rules[0].parameters.required_status_checks + [{context: $c, integration_id: $iid}]
        )
      }
    }
  ]
}' "$before" > "$payload"

echo "Proposed required_status_checks contexts:"
jq -r '.rules[0].parameters.required_status_checks[].context' "$payload" | sort
echo "---"
echo "bypass_actors (verbatim from before-snapshot):"
jq '.bypass_actors' "$payload"
echo "---"
echo "conditions (verbatim from before-snapshot):"
jq '.conditions' "$payload"

if (( DRY_RUN )); then
  echo "---"
  echo "Dry-run mode -- no mutation."
  exit 0
fi

# 5. Apply (per hr-menu-option-ack-not-prod-write-auth, the caller has
#    already shown the exact command to the operator and received explicit
#    per-command go-ahead).
echo "---"
echo "Applying PUT..."
gh api --method PUT "repos/${REPO}/rulesets/${RULESET_ID}" --input "$payload" > "$after"
echo "PUT succeeded. Verifying preserved fields..."

# 6. Verify bypass_actors and conditions are preserved verbatim. The PUT
#    API silently strips any field omitted from the payload.
if ! diff <(jq -S .bypass_actors "$before") <(jq -S .bypass_actors "$after") >/dev/null; then
  echo "::error::bypass_actors drifted after PUT -- INVESTIGATE"
  diff <(jq -S .bypass_actors "$before") <(jq -S .bypass_actors "$after") || true
  exit 2
fi
if ! diff <(jq -S .conditions "$before") <(jq -S .conditions "$after") >/dev/null; then
  echo "::error::conditions drifted after PUT -- INVESTIGATE"
  diff <(jq -S .conditions "$before") <(jq -S .conditions "$after") || true
  exit 2
fi

echo "Verification OK. Final required_status_checks contexts:"
gh api "repos/${REPO}/rulesets/${RULESET_ID}" \
  --jq '.rules[0].parameters.required_status_checks[].context' | sort
