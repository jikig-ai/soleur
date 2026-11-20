#!/usr/bin/env bash
# One-shot bootstrap for the rundevoo.run zone root (issue #12971).
#
# Why this exists: this root must never carry a `cloudflare_api_token`
# resource — its permission-groups data source needs `User -> API Tokens ->
# Read`, which the Tier-A zone-scoped credential lacks (the same reason
# apps/cla-evidence/infra carries .pr-plan-skip; this root deliberately does
# NOT, per plan TR5). Minting tokens requires `User -> API Tokens -> Edit`,
# a scope no standing credential carries. So a one-hour dashboard-minted
# admin token does the mint once, out of band, then self-revokes.
#
# Operator step (one-time, second and last — the purchase was the first):
#   1. Mint a ONE-HOUR CF admin token at
#      https://dash.cloudflare.com/profile/api-tokens with:
#        User -> API Tokens -> Edit
#        Zone -> Zone -> Read            (needed to discover the zone id)
#   2. Run:
#        CF_ADMIN_TOKEN_BOOTSTRAP=<paste> bash infra/rundevoo-run/bootstrap.sh
#   3. The script self-revokes the admin token on EXIT (trap, not end-of-success
#      — a partial failure must not leave a standing admin token; the
#      cla-evidence precedent revokes only on success, which is the gap this
#      trap closes). Any token minted before a later failure is also revoked.
#
# What it does:
#   - verifies the admin token (shared _cf-admin-token.sh helper), discovers
#     the rundevoo.run zone id, resolves the zone-scoped permission-group ids
#     for Zone Read / DNS Write / Zone Settings Write (DNSSEC is covered by
#     DNS Write — PATCH /zones/{id}/dnssec's accepted permission);
#   - POSTs /user/tokens to mint `soleur-tf-rundevoo-run` scoped to
#     com.cloudflare.api.account.zone.<zone_id>; on re-run, revokes the
#     previous token of the same name first (rotate = re-run);
#   - writes CF_API_TOKEN_RUNDEVOO to Doppler prd_terraform on stdin and
#     read-back verifies the stored value matches byte-for-byte;
#   - verifies coverage by LIVE PROBE with the minted token (ADR-130 — never
#     the permission label): GET /zones/{id}, GET /dns_records, GET /dnssec,
#     plus a real DNS-write probe (create + delete a throwaway TXT record);
#   - negative retained-scope probe: GET /zones/{soleur_ai_zone_id} must 4xx
#     (a ?name= list call returns 200 with result:[], not 403 — the probe
#     must fetch the specific zone id).
#
# Idempotent: re-run rotates the token (revoke-on-remint). Safe to re-run on
# partial failure — every step checks state before mutating.
#
# Cross-app coupling: sources apps/cla-evidence/scripts/_cf-admin-token.sh
# (shared verify + self-revoke + confined-curl helpers). If that file moves,
# this script breaks — the dependency is recorded in README.md.

set -euo pipefail

# Refuse to run under xtrace: -x prints a variable's value the moment it is
# bound (see #7797), and this script handles a live Cloudflare admin token and
# the minted zone token. There is no legitimate traced run, so the refusal is
# unconditional and sits before anything is bound.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; NC='\033[0m'
red()    { printf '%b%s%b\n' "$RED"    "$*" "$NC" >&2; }
green()  { printf '%b%s%b\n' "$GREEN"  "$*" "$NC"; }
yellow() { printf '%b%s%b\n' "$YELLOW" "$*" "$NC"; }
step()   { printf '\n→ %s\n' "$*"; }

# Shared CF-admin-token helpers (verify + self-revoke + confined bearer curl).
# Sourced AFTER the red/green/yellow helpers above (sourcing precondition).
# shellcheck source=../../apps/cla-evidence/scripts/_cf-admin-token.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../apps/cla-evidence/scripts" && pwd)/_cf-admin-token.sh"

CF_API_BASE="https://api.cloudflare.com/client/v4"
TOKEN_NAME="soleur-tf-rundevoo-run"
ZONE_NAME="rundevoo.run"
DOPPLER_PROJECT="soleur"
DOPPLER_CONFIG="prd_terraform"
DOPPLER_KEY="CF_API_TOKEN_RUNDEVOO"

# ─────────────────────────────────────────────────────────────────────────
# trap-on-EXIT self-revoke. The admin token is dead on any exit — success,
# failure, or signal-driven abort — never a standing credential. The minted
# zone token is revoked only if the script exits before the Doppler read-back
# verification succeeds (BOOTSTRAP_VERIFIED flag), so a half-finished run
# leaves no credential behind either.
# ─────────────────────────────────────────────────────────────────────────
BOOTSTRAP_VERIFIED=0
MINTED_TOKEN_ID=""
MINTED_TOKEN_VALUE=""
cleanup() {
  rc=$?
  # Order matters: the minted-token revoke rides the admin token, so it must
  # run BEFORE the admin self-revoke — after that the DELETE would 401 and a
  # half-finished bootstrap would leave a live zone credential.
  if [[ "$BOOTSTRAP_VERIFIED" != "1" && -n "$MINTED_TOKEN_ID" && -n "${CF_ADMIN_TOKEN_BOOTSTRAP:-}" ]]; then
    yellow "  bootstrap incomplete — revoking minted token $MINTED_TOKEN_ID"
    _cf_admin_curl "$CF_ADMIN_TOKEN_BOOTSTRAP" \
      "$CF_API_BASE/user/tokens/$MINTED_TOKEN_ID" --max-time 30 -fsS -X DELETE \
      >/dev/null 2>&1 || true
  fi
  if [[ -n "${CF_ADMIN_TOKEN_BOOTSTRAP:-}" && -n "${CF_ADMIN_TOKEN_ID:-}" ]]; then
    cf_token_self_revoke "$CF_ADMIN_TOKEN_BOOTSTRAP" "$CF_ADMIN_TOKEN_ID" >/dev/null 2>&1 || true
  fi
  if [[ "$BOOTSTRAP_VERIFIED" == "1" && $rc -eq 0 ]]; then
    green "  admin token self-revoked (trap EXIT)"
  fi
}
trap cleanup EXIT

# ─────────────────────────────────────────────────────────────────────────
# Pre-flight: deps + doppler auth + admin token
# ─────────────────────────────────────────────────────────────────────────
step "[1/6] pre-flight"

for bin in doppler jq curl; do
  command -v "$bin" >/dev/null || { red "missing $bin on PATH"; exit 64; }
done

doppler configure get token --plain >/dev/null 2>&1 \
  || { red "doppler not authenticated; run \`doppler login\`"; exit 64; }

if [[ -z "${CF_ADMIN_TOKEN_BOOTSTRAP:-}" ]]; then
  red "CF_ADMIN_TOKEN_BOOTSTRAP env var is required."
  red "Mint a 1h token at https://dash.cloudflare.com/profile/api-tokens with:"
  red "  User -> API Tokens -> Edit   AND   Zone -> Zone -> Read"
  exit 64
fi

CF_ADMIN_TOKEN_ID=$(cf_token_verify "$CF_ADMIN_TOKEN_BOOTSTRAP") || exit 1
green "  admin token verified (id $CF_ADMIN_TOKEN_ID)"

# ─────────────────────────────────────────────────────────────────────────
# Step 2 — discover zone id + soleur.ai zone id (negative-probe target)
# ─────────────────────────────────────────────────────────────────────────
step "[2/6] zone discovery"

zone_resp=$(_cf_admin_curl "$CF_ADMIN_TOKEN_BOOTSTRAP" \
  "$CF_API_BASE/zones?name=$ZONE_NAME" --max-time 30 -fsS) \
  || { red "GET /zones failed"; exit 1; }
ZONE_ID=$(printf '%s' "$zone_resp" | jq -r '.result[0].id // ""')
[[ -n "$ZONE_ID" ]] || {
  red "zone $ZONE_NAME not visible to the admin token — it needs Zone -> Zone -> Read."
  exit 1
}
green "  zone $ZONE_NAME -> $ZONE_ID"

# The negative probe needs soleur.ai's literal zone id: a ?name= list returns
# 200/result:[] for an out-of-scope zone, never 403 — only fetching the id
# discriminates. Source it from Doppler rather than the admin token's zone
# list (the admin token may be account-wide and would lie about the minted
# token's scope boundary).
SOLEUR_AI_ZONE_ID=$(doppler secrets get CF_ZONE_ID \
  --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --plain 2>/dev/null) || SOLEUR_AI_ZONE_ID=""
[[ -n "$SOLEUR_AI_ZONE_ID" ]] || { red "CF_ZONE_ID missing from prd_terraform"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────
# Step 3 — resolve permission-group ids + mint the zone-scoped token
# ─────────────────────────────────────────────────────────────────────────
step "[3/6] mint $TOKEN_NAME (zone-scoped)"

groups=$(_cf_admin_curl "$CF_ADMIN_TOKEN_BOOTSTRAP" \
  "$CF_API_BASE/user/tokens/permission_groups" --max-time 30 -fsS) \
  || { red "GET /user/tokens/permission_groups failed"; exit 1; }

pg_id() {
  local want="$1"
  printf '%s' "$groups" | jq -r --arg want "$want" '
    .result[]
    | select(.name == $want)
    | select(.scopes | index("com.cloudflare.api.account.zone") != null)
    | .id' | head -n 1
}
PG_ZONE_READ=$(pg_id "Zone Read")
PG_DNS_WRITE=$(pg_id "DNS Write")
PG_ZONE_SETTINGS_WRITE=$(pg_id "Zone Settings Write")
for pair in "Zone Read:$PG_ZONE_READ" "DNS Write:$PG_DNS_WRITE" "Zone Settings Write:$PG_ZONE_SETTINGS_WRITE"; do
  [[ -n "${pair#*:}" ]] || { red "permission group '${pair%%:*}' not found (zone scope)"; exit 1; }
done

# Revoke-on-remint: an existing same-named token is a stale credential —
# rotate it out before minting, so a re-run never leaves two live copies.
existing_ids=$(_cf_admin_curl "$CF_ADMIN_TOKEN_BOOTSTRAP" \
  "$CF_API_BASE/user/tokens" --max-time 30 -fsS \
  | jq -r --arg n "$TOKEN_NAME" '.result[]? | select(.name == $n) | .id') || existing_ids=""
while IFS= read -r old_id; do
  [[ -n "$old_id" ]] || continue
  _cf_admin_curl "$CF_ADMIN_TOKEN_BOOTSTRAP" \
    "$CF_API_BASE/user/tokens/$old_id" --max-time 30 -fsS -X DELETE >/dev/null \
    && yellow "  revoked previous $TOKEN_NAME ($old_id)" \
    || yellow "  WARN: could not revoke previous token $old_id — check the dashboard"
done <<< "$existing_ids"

mint_body=$(jq -nc \
  --arg name "$TOKEN_NAME" \
  --arg zone_res "com.cloudflare.api.account.zone.$ZONE_ID" \
  --arg p1 "$PG_ZONE_READ" --arg p2 "$PG_DNS_WRITE" --arg p3 "$PG_ZONE_SETTINGS_WRITE" \
  '{name: $name,
    policies: [{
      effect: "allow",
      resources: {($zone_res): "*"},
      permission_groups: [{id: $p1}, {id: $p2}, {id: $p3}]
    }]}')

mint_resp=$(_cf_admin_curl "$CF_ADMIN_TOKEN_BOOTSTRAP" \
  "$CF_API_BASE/user/tokens" --max-time 30 -fsS \
  -H "Content-Type: application/json" -d "$mint_body") \
  || { red "POST /user/tokens failed"; exit 1; }
MINTED_TOKEN_ID=$(printf '%s' "$mint_resp" | jq -r '.result.id // ""')
MINTED_TOKEN_VALUE=$(printf '%s' "$mint_resp" | jq -r '.result.value // ""')
[[ -n "$MINTED_TOKEN_ID" && -n "$MINTED_TOKEN_VALUE" ]] \
  || { red "mint response missing id/value"; exit 1; }
green "  minted $TOKEN_NAME ($MINTED_TOKEN_ID)"

# ─────────────────────────────────────────────────────────────────────────
# Step 4 — live coverage probes WITH THE MINTED TOKEN (ADR-130)
# ─────────────────────────────────────────────────────────────────────────
step "[4/6] live coverage probes"

probe() {
  local path="$1" want="$2" label="$3" code
  code=$(_cf_admin_curl "$MINTED_TOKEN_VALUE" \
    "$CF_API_BASE/zones/$path" --max-time 30 -sS -o /dev/null -w '%{http_code}') || code="000"
  if [[ "$code" != "$want" ]]; then
    red "  probe $label: got $code, want $want — the minted token's scope is wrong; aborting (minted token revoked by trap)"
    exit 1
  fi
  green "  probe $label: $code"
}
probe "$ZONE_ID"            200 "GET /zones/{rundevoo}"
probe "$ZONE_ID/dns_records" 200 "GET /dns_records"
probe "$ZONE_ID/dnssec"     200 "GET /dnssec"
# 4xx needs a range check, not the probe() equality — negative probe inline.
neg_code=$(_cf_admin_curl "$MINTED_TOKEN_VALUE" \
  "$CF_API_BASE/zones/$SOLEUR_AI_ZONE_ID" --max-time 30 -sS -o /dev/null -w '%{http_code}') || neg_code="000"
case "$neg_code" in
  4*) green "  probe GET /zones/{soleur.ai}: $neg_code (retained-scope boundary holds)" ;;
  *)  red "  probe GET /zones/{soleur.ai}: got $neg_code, want 4xx — token is wider than the zone scope; aborting"; exit 1 ;;
esac

# Write probe: a throwaway TXT record proves DNS Write live (a GET-only verify
# would ship a token that plans but cannot apply). The record is created and
# deleted in the same step; a delete failure leaves only a visible stray.
wr_resp=$(_cf_admin_curl "$MINTED_TOKEN_VALUE" \
  "$CF_API_BASE/zones/$ZONE_ID/dns_records" --max-time 30 -fsS \
  -H "Content-Type: application/json" \
  -d '{"type":"TXT","name":"_bootstrap-probe.rundevoo.run","content":"bootstrap-write-probe","ttl":120}') \
  || { red "write probe create failed — minted token cannot write DNS"; exit 1; }
wr_id=$(printf '%s' "$wr_resp" | jq -r '.result.id // ""')
[[ -n "$wr_id" ]] || { red "write probe returned no record id"; exit 1; }
_cf_admin_curl "$MINTED_TOKEN_VALUE" \
  "$CF_API_BASE/zones/$ZONE_ID/dns_records/$wr_id" --max-time 30 -fsS -X DELETE \
  >/dev/null || yellow "  WARN: probe record $wr_id delete failed — remove _bootstrap-probe TXT in dashboard"
green "  write probe: TXT _bootstrap-probe created + deleted"

# ─────────────────────────────────────────────────────────────────────────
# Step 5 — Doppler write + byte-exact read-back
# ─────────────────────────────────────────────────────────────────────────
step "[5/6] Doppler prd_terraform write"

printf '%s' "$MINTED_TOKEN_VALUE" | doppler secrets set "$DOPPLER_KEY" \
  --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --no-interactive \
  >/dev/null || { red "Doppler write of $DOPPLER_KEY failed"; exit 1; }

stored=$(doppler secrets get "$DOPPLER_KEY" \
  --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --plain 2>/dev/null) || stored=""
if [[ "$stored" != "$MINTED_TOKEN_VALUE" ]]; then
  red "Doppler read-back of $DOPPLER_KEY does not match the minted value"
  exit 1
fi
green "  $DOPPLER_KEY stored in prd_terraform (read-back verified)"

# ─────────────────────────────────────────────────────────────────────────
# Step 6 — done
# ─────────────────────────────────────────────────────────────────────────
step "[6/6] summary"
BOOTSTRAP_VERIFIED=1
green "  zone_id:        $ZONE_ID"
green "  token:          $TOKEN_NAME ($MINTED_TOKEN_ID) — no expiry; re-run this script to rotate"
green "  doppler:        $DOPPLER_KEY in $DOPPLER_CONFIG"
green ""
green "BOOTSTRAP COMPLETE. Next: terraform init + a real plan under"
green "TF_VAR_cf_api_token_rundevoo (doppler run --name-transformer tf-var"
green "-p soleur -c prd_terraform -- terraform plan). The account id is a"
green "literal in zone.tf — the zone lives in the 'Soleur' account, not the"
green "prd_terraform CF_ACCOUNT_ID (R2/state account)."
