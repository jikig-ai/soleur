#!/usr/bin/env bash
#
# (#9294 G1, PR-2, ADR-241 D10) The deploy Access service token leaves Terraform state WITHOUT being destroyed.
#
# PROPERTY. `cloudflare_zero_trust_access_service_token.deploy` is forgotten (`removed { destroy = false }`), the
# deploy application's policy keeps admitting the same token through the committed `deploy_service_token_ids`
# list, and the two sensitive outputs that carried the token's client_id/client_secret are gone. After the
# apply the secret is absent from current state and the token keeps working in Cloudflare until the owner
# rotates it. This change is FORWARD-FIX ONLY: re-declaring the resource would mint a new token whose secret is
# in no Doppler project.
#
# WHAT THIS PROVES (offline, no network): the source shape of tunnel.tf, the plan shape of a synthesized fixture
# (0 add, 0 destroy, the token only forgotten, the policy include unchanged) run through the REAL web-platform
# destroy-guard filter (a forget of a Cloudflare type can trip its nested counters; the CTO's read of the filter
# was unverified until this suite), and that the -target line the `removed` block needs is still in the workflow.
# WHAT IT CANNOT PROVE: that the committed id list equals the LIVE token id. CI cannot know the live id; that is
# the owner's read-only state/plan check before merge (the plan must show the policy unchanged, 0 add, 0 destroy).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF="$ROOT/apps/web-platform/infra/tunnel.tf"
WF="$ROOT/.github/workflows/apply-web-platform-infra.yml"
FILTER="$ROOT/tests/scripts/lib/destroy-guard-filter-web-platform.jq"
FIX="$ROOT/tests/scripts/fixtures/tfplan-deploy-access-token-forget.json"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }

echo "=== deploy Access token forget (G1, PR-2; #9294) ==="

# --- source shape of tunnel.tf (comments stripped so prose cannot satisfy a pin) -------------------------
CODE="$(sed -E 's/^[[:space:]]*#.*$//' "$TF")"

check "S1: the deploy token is not a declared resource any more (re-declaring it would mint a token no Doppler project holds)" \
  bash -c '! grep -qE "^resource \"cloudflare_zero_trust_access_service_token\" \"deploy\"" <<<"$1"' _ "$CODE"
check "S2: a removed block forgets the deploy token with destroy = false" \
  bash -c 'tr -d "\n" <<<"$1" | grep -qE "removed[[:space:]]*\{[[:space:]]*from[[:space:]]*=[[:space:]]*cloudflare_zero_trust_access_service_token\.deploy[[:space:]]*lifecycle[[:space:]]*\{[[:space:]]*destroy[[:space:]]*=[[:space:]]*false"' _ "$CODE"
check "S3: the deploy policy admits var.deploy_service_token_ids (not a resource reference)" \
  bash -c 'tr -d "\n" <<<"$1" | grep -qE "resource \"cloudflare_zero_trust_access_policy\" \"deploy_service_token\"[^}]*include[[:space:]]*\{[[:space:]]*service_token[[:space:]]*=[[:space:]]*var\.deploy_service_token_ids"' _ "$CODE"
check "S4: no output block reads the deploy token (its client_id/client_secret sat in Tier-A-readable state)" \
  bash -c '! grep -qE "output \"access_service_token_client_(id|secret)\"" <<<"$1"' _ "$CODE"
check "S5: nothing in tunnel.tf reads .client_secret of the deploy token" \
  bash -c '! grep -qE "access_service_token\.deploy\.client_" <<<"$1"' _ "$CODE"

# The variable: a non-empty list of UUIDs, enforced by validation. A default, once the owner-read live id is committed,
# must itself be a non-empty list of well-formed ids; an EMPTY include would lock the deploy webhook out.
check "S6: deploy_service_token_ids is a list(string) variable validated non-empty and UUID-shaped" \
  bash -c 'tr -d "\n" <<<"$1" | grep -qE "variable \"deploy_service_token_ids\"[^}]*type[[:space:]]*=[[:space:]]*list\(string\)" && grep -q "length(var.deploy_service_token_ids) > 0" <<<"$1" && grep -qF "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" <<<"$1"' _ "$CODE"
default_ids="$(tr -d '\n' <<<"$CODE" | grep -oE 'variable "deploy_service_token_ids"[^}]*default[[:space:]]*=[[:space:]]*\[[^]]*\]' | grep -oE '\[[^]]*\]' || true)"
if [[ -z "$default_ids" ]]; then
  ok "S7: no committed default yet (DRAFT: the owner-read live token id is committed before merge; until then every plan of this root refuses)"
else
  check "S7: the committed default is a non-empty list of UUID-shaped ids" \
    bash -c 'grep -qE "\"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\"" <<<"$1"' _ "$default_ids"
fi

# --- the -target line a removed block needs (a removed block is only planned when its address is targeted) -------
check "T1: apply-web-platform-infra.yml still targets the forgotten address" \
  grep -qF -- '-target=cloudflare_zero_trust_access_service_token.deploy' "$WF"
check "T2: no workflow replaces or destroys the deploy token (-replace would re-create it; never)" \
  bash -c '! grep -rEn -- "-replace[= ]+[\"'"'"']?[^ ]*access_service_token\.deploy" "$1/.github" >/dev/null 2>&1' _ "$ROOT"

# --- plan shape of the fixture, through the real destroy-guard filter ---------------------------------------------
check "P1: the fixture holds exactly one forget (the token) and one no-op (the policy), no add, no delete, no update" \
  bash -c 'jq -e "[.resource_changes[].change.actions] == [[\"forget\"],[\"no-op\"]]" "$1" >/dev/null' _ "$FIX"
check "P2: the policy include is unchanged across the plan (the same token id before and after)" \
  bash -c 'jq -e "(.resource_changes[] | select(.type == \"cloudflare_zero_trust_access_policy\") | .change) | .before.include == .after.include" "$1" >/dev/null' _ "$FIX"
check "P3: the fixture carries no client_secret / client_id value anywhere (a forgotten token must not surface its secret)" \
  bash -c '! grep -qE "client_(id|secret)\"?[[:space:]]*:[[:space:]]*\"[^\"]" "$1"' _ "$FIX"
counts="$(jq -f "$FILTER" "$FIX" 2>/dev/null || echo '{}')"
check "P4: the destroy-guard filter counts nothing for this plan (resource_deletes, nested_deletes, host_creates all 0): a forget of the Access token does not trip the gate" \
  bash -c 'jq -e --argjson c "$1" -n "\$c.resource_deletes == 0 and \$c.nested_deletes == 0 and \$c.host_creates == 0 and \$c.reboot_updates == 0" >/dev/null' _ "$counts"

# --- anti-vacuity: the pins above must be able to fail -------------------------------------------------------------
MUT="$(mktemp)"; trap 'rm -f "$MUT"' EXIT
sed -E 's/^(resource "cloudflare_zero_trust_access_policy" "deploy_service_token" \{)/\1\n  # mutated/; s/service_token = var\.deploy_service_token_ids/service_token = [cloudflare_zero_trust_access_service_token.deploy.id]/' "$TF" > "$MUT"
MUTCODE="$(sed -E 's/^[[:space:]]*#.*$//' "$MUT")"
check "M1: a policy pointed back at the (forgotten) resource fails S3's pattern" \
  bash -c '! tr -d "\n" <<<"$1" | grep -qE "include[[:space:]]*\{[[:space:]]*service_token[[:space:]]*=[[:space:]]*var\.deploy_service_token_ids"' _ "$MUTCODE"
jq '.resource_changes[1].change.after.include[0].service_token = []' "$FIX" > "$MUT"
check "M2: a policy whose include loses the token fails P2's equality" \
  bash -c '! jq -e "(.resource_changes[] | select(.type == \"cloudflare_zero_trust_access_policy\") | .change) | .before.include == .after.include" "$1" >/dev/null' _ "$MUT"
jq '.resource_changes[0].change.actions = ["delete"]' "$FIX" > "$MUT"
dels="$(jq -f "$FILTER" "$MUT" | jq '.resource_deletes')"
check "M3: the token DELETED instead of forgotten is counted by the destroy-guard (resource_deletes >= 1)" \
  test "$dels" -ge 1

echo ""
echo "=== deploy-access-token-forget: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
