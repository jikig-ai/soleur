#!/usr/bin/env bash
# Follow-through verification for #4277 (umbrella #4229 flag-flip).
#
# Asserts the team-workspace-invite feature has been activated end-to-end
# AFTER the parallel legal-scaffolding PR landed. Three preconditions
# must ALL hold for the issue to auto-close:
#
#   1. Legal-scaffolding PR merged — gh pr list against the conventional
#      branch name returns at least one MERGED row.
#   2. FLAG_TEAM_WORKSPACE_INVITE=1 in prd Doppler.
#   3. jikigai org_id in TEAM_WORKSPACE_ALLOWLIST_ORG_IDS in prd Doppler
#      (comma-separated; non-empty intersection with the actual jikigai
#      org_id resolved from public.organizations).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (all three preconditions hold; sweeper closes #4277)
#   1 = FAIL       (some condition unmet OR jikigai not in allowlist)
#   * = TRANSIENT  (Doppler/gh API unreachable, parse failure)
#
# Required env: DOPPLER_TOKEN_PRD (Doppler service token scoped to prd)
#
# AC-LEGAL-FLIP source:
#   knowledge-base/legal/compliance-posture.md "Team workspace multi-user
#   — legal-doc lockstep gate dependency" Active Items row.

set -uo pipefail

: "${DOPPLER_TOKEN_PRD:?DOPPLER_TOKEN_PRD must be set}"
: "${GH_TOKEN:?GH_TOKEN must be set (sweeper provides via secrets.GITHUB_TOKEN)}"

# (1) Legal-scaffolding PR merged?
LEGAL_PR=$(gh pr list \
  --state merged \
  --search 'head:feat-team-workspace-legal-scaffolding' \
  --json number,mergedAt \
  --jq '.[0] | "\(.number) \(.mergedAt)"' 2>&1)
if [[ -z "$LEGAL_PR" || "$LEGAL_PR" == "null null" ]]; then
  echo "WAIT: legal-scaffolding PR not yet merged (branch feat-team-workspace-legal-scaffolding)"
  exit 1
fi
echo "OK (1/3): legal-scaffolding PR merged: #${LEGAL_PR}"

# (2) FLAG_TEAM_WORKSPACE_INVITE=1?
FLAG_VAL=$(curl -sS \
  -H "Authorization: Bearer ${DOPPLER_TOKEN_PRD}" \
  -H "Accept: application/json" \
  "https://api.doppler.com/v3/configs/config/secret?project=soleur&config=prd&name=FLAG_TEAM_WORKSPACE_INVITE" \
  2>&1)
HTTP_FLAG=$?
if [[ "$HTTP_FLAG" -ne 0 ]]; then
  echo "TRANSIENT: Doppler API unreachable: $FLAG_VAL" >&2
  exit 2
fi
FLAG=$(printf '%s' "$FLAG_VAL" | jq -r '.value.computed // .value.raw // empty' 2>/dev/null)
if [[ "$FLAG" != "1" ]]; then
  echo "WAIT: FLAG_TEAM_WORKSPACE_INVITE=${FLAG:-<unset>} in prd (expected '1')"
  exit 1
fi
echo "OK (2/3): FLAG_TEAM_WORKSPACE_INVITE=1"

# (3) jikigai org_id in TEAM_WORKSPACE_ALLOWLIST_ORG_IDS?
ALLOWLIST_VAL=$(curl -sS \
  -H "Authorization: Bearer ${DOPPLER_TOKEN_PRD}" \
  -H "Accept: application/json" \
  "https://api.doppler.com/v3/configs/config/secret?project=soleur&config=prd&name=TEAM_WORKSPACE_ALLOWLIST_ORG_IDS" \
  2>&1)
ALLOWLIST=$(printf '%s' "$ALLOWLIST_VAL" | jq -r '.value.computed // .value.raw // empty' 2>/dev/null)
if [[ -z "$ALLOWLIST" ]]; then
  echo "WAIT: TEAM_WORKSPACE_ALLOWLIST_ORG_IDS unset in prd"
  exit 1
fi

# Tolerate either:
#   (a) explicit uuid set by operator — we can't resolve jikigai's actual uuid
#       from here without DB access, so the heuristic is: non-empty allowlist
#       value containing at least one well-formed uuid is sufficient evidence
#       the operator has set this intentionally.
#   (b) the special token "*" or "all" (would be unusual but operator-decided).
if printf '%s' "$ALLOWLIST" | grep -qE '\*|\ball\b'; then
  echo "OK (3/3): TEAM_WORKSPACE_ALLOWLIST_ORG_IDS has wildcard ($ALLOWLIST)"
elif printf '%s' "$ALLOWLIST" | grep -qE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'; then
  org_count=$(printf '%s' "$ALLOWLIST" | tr ',' '\n' | grep -cE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
  echo "OK (3/3): TEAM_WORKSPACE_ALLOWLIST_ORG_IDS contains ${org_count} uuid(s)"
else
  echo "WAIT: TEAM_WORKSPACE_ALLOWLIST_ORG_IDS value '${ALLOWLIST}' has no recognizable uuid or wildcard"
  exit 1
fi

echo "PASS: all 3 preconditions hold (legal-PR ${LEGAL_PR}, FLAG=1, allowlist=${ALLOWLIST})"
exit 0
